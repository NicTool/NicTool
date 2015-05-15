package NicToolServerAPI;
# ABSTRACT: manage the connection to the NicToolServer

use strict;

use LWP::UserAgent;
use RPC::XML;
use RPC::XML::Parser;
use SOAP::Lite;
use XML::Parser();
use Data::Dumper;

$NicToolServerAPI::VERSION          = '2.11';
$NicToolServerAPI::protocol_version = "1.0";
$NicToolServerAPI::default_transfer_protocol = 'http';

sub new {
    my $class = shift;

    $NicToolServerAPI::transfer_protocol = $NicToolServerAPI::default_transfer_protocol
        unless( $NicToolServerAPI::transfer_protocol );

    bless {}, $class;
}

sub check_setup {
    my $self = shift;

    my $message = 'OK';

    $message
        = "ERROR: server_host not set in $NicToolClient::app_dir/lib/NicToolServerAPI.pm"
        unless ($NicToolServerAPI::server_host);
    $message
        = "ERROR: server_port not set in $NicToolClient::app_dir/lib/NicToolServerAPI.pm"
        unless ($NicToolServerAPI::server_port);
    $message
        = "ERROR: protocol_version not set in $NicToolClient::app_dir/lib/NicToolServerAPI.pm"
        unless ($NicToolServerAPI::protocol_version);

    return $message;
}

sub send_request {
    my $self = shift;
    my $url = sprintf( '%s://%s:%d',
                       $NicToolServerAPI::transfer_protocol,
                       $NicToolServerAPI::server_host,
                       $NicToolServerAPI::server_port );
    my $func = 'send_' . $NicToolServerAPI::data_protocol . '_request';
    if ( ! $self->can($func) ) {
        return {
            'error_code' => 501,
            'error_msg'  => 'Data protocol not supported: '
                . $NicToolServerAPI::data_protocol
        };
    }
    return $self->$func( $url, @_ );
}

sub send_soap_request {
    my $self = shift;
    my $url  = shift;
    my %vars = @_;

    my $func = $vars{action};
    delete $vars{action};
    foreach ( keys %vars ) {
        $vars{$_} = "" unless defined $vars{$_};
    }

    #$vars{'NicTool-protocol_version'}=$NicToolServerAPI::protocol_version;
    $vars{'nt_protocol_version'} = $NicToolServerAPI::protocol_version;
    my $soap = SOAP::Lite->new(

        #location of NicToolServer soap server
        proxy => $url . '/soap',

        #URI is typically org name followed by module path
        uri => sprintf( '%s://%s/NicToolServer/SOAP',
                        $NicToolServerAPI::transfer_protocol,
                        $NicToolServerAPI::server_host ),

        #don't die on fault, just return result.
        on_fault => sub { my ( $soap, $res ) = @_; return $res; }
    );
    if ($NicToolServerAPI::debug_soap_setup) {
        warn "URI: " . $soap->uri . ", proxy: " . $url . '/soap' . "\n";
        warn "Calling soap function \"$func\" with params:\n" . Dumper( \%vars ) . "\n";
    };

    #make soap call and evaluate response.
    my $som = $soap->call( $func => \%vars );

    #result should be SOAP::SOM object if success or fault,
    # or scalar for transport error
    if ( !ref $som ) {

        #scalar means transport error
        warn "SOAP result SCALAR: " . Dumper($som) . "\n"
            if $NicToolServerAPI::debug_soap_response;
        return {
            error_code => $soap->transport->code,
            error_msg  => 'SOAP: transport error: ' 
                . $url . '/soap' . ': '
                . $soap->transport->status
        };
    }
    elsif ( $som->isa('SOAP::SOM') && !$som->fault ) {
        warn "SOAP result: " . Dumper( $som->result ) . "\n"
            if $NicToolServerAPI::debug_soap_response;
        return $som->result;
    }
    elsif ( $som->isa('SOAP::SOM') && $som->fault ) {
        warn "SOAP result: " . Dumper( $som->result ) . "\n"
            if $NicToolServerAPI::debug_soap_response;
        return {
            'error_code' => $som->faultcode,
            'error_msg'  => 'SOAP: fault: ' . $som->faultstring
        };
    }
    else {
        warn "SOAP result: Unknown: " . Dumper($som) . "\n"
            if $NicToolServerAPI::debug_soap_response;
        return {
            'error_code' => '??',
            'error_msg'  => 'SOAP: Unknown response type:' . ref $som
        };
    }
}

sub send_xml_rpc_request {
    my $self = shift;
    my $url  = shift;
    my %vars = @_;

    my $com = $vars{action};
    delete $vars{action};
    $vars{'nt_protocol_version'} = $NicToolServerAPI::protocol_version;

    #encode data into xml-rpc request obj and get xml string
    my $xmlreq
        = RPC::XML::request->new( $com, RPC::XML::smart_encode( \%vars ) );
    my $command = $xmlreq->as_string;

    my $ua = new LWP::UserAgent;
    my $req = HTTP::Request->new( 'POST', $url );

    $ua->agent("NicToolClient v$NicToolServerAPI::VERSION");
    $req->content_type('text/xml');
    $req->content($command);

    #$req->header("NicTool-protocol_version" => "$NicToolServerAPI::protocol_version");

    #send request, evaluate response
    my $response = $ua->request($req);
    my $res      = $response->content;

    if ( !$response->is_success ) {
        return (
            {   error_code => 508,
                error_msg  => "XML-RPC: $url: "
                    . $response->code . " "
                    . $response->message
            }
        );
    }

    my $restype = $response->header('Content-Type');

    if ( $restype =~ /^text\/xml$/ ) {
        return $self->parse_xml($res);
    }
    else {
        return {
            error_code => '501',
            error_msg  => 'XML-RPC: Content-Type not text/xml: ' . $restype
        };
    }
}

sub parse_xml {
    my ( $self, $string ) = @_;

    # try to parse the xml -- handle xml-rpc faults as well as parsing errors
    #
    my $resp = RPC::XML::Parser->new()->parse($string);

    # $resp will be ref if a real response, otherwise scalar error string
    if ( ref($resp) && !$resp->is_fault ) {

        # get data-type value of response, and get perl value of that
        return $resp->value->value;
    }
    elsif ( ref($resp) && $resp->is_fault ) {
        return {
            error_code => $resp->value->code,
            error_msg  => 'XML-RPC: fault: ' . $resp->value->string
        };
    }
    else {

        # parsing error
        return {
            error_code => '501',
            error_msg  => 'XML-RPC: parse error:' . $resp
        };
    }
}

1;

__END__

=head1 SYNOPSIS

=cut

