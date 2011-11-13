package NicToolTest;
use strict;

use SOAP::Lite;
use Data::Dumper;

sub new { 
	bless &_conf,$_[0];
}
sub _conf{
	{
	'server_host' => "localhost",
	'server_port' => "8010",
	'server_https_port'=> "8043",
	'data_protocol' => "soap",
	'use_https_authentication' => 0,	
	'client_certificate_file' => "/usr/local/apache/conf/clientcert/client.crt",
	'client_key_file' => "/usr/local/apache/conf/clientcert/client.key",
 
#Note https peer authentication (of server to client) is ALPHA in Crypt::SSLeay .29 so may not work
	'use_https_peer_authentication' => 0,
	'ca_certificate_file' => "/usr/local/apache/conf/ssl.crt/ca-bundle2.crt",
	'ca_certificate_path' => "/usr/local/apache/conf/ssl.crt/",
	'nt_user_session' => undef,	
	}
}
sub set{	
	my $self = shift;
	my $var = shift;
	my $val = shift;
	$self->{$var} = $val if exists $self->{$var};
}

sub is_error{
	my $self = shift;
	my $res = shift;
	if(defined($res->{error_code})&& $res->{error_code} ne '200'){
		return $res->{error_msg}||1;
	}
	return undef;
}

sub check_setup {
    my $self = shift;

    my $message = 'OK';

    $message = "ERROR: server_host not set in NicToolTest.pm" unless( $self->{server_host} );
    $message = "ERROR: server_port not set in NicToolTest.pm" unless( $self->{server_port} );
    if($self->{use_https_authentication}){
        $message = "ERROR: client certificate not set in NicToolTest.pm" unless( $self->{client_certificate_file} );
    	$message = "ERROR: client key file not set in NicToolTest.pm" unless( $self->{client_key_file} );
    	if($self->{use_https_peer_authentication}){
    		$message = "ERROR: CA certificate or dir not set in NicToolTest.pm" unless( $self->{ca_certificate_path} || $self->{ca_certificate_file});
		}
    }
    
    return $message;
}

sub send_request{
	my $self = shift;
	my $url;
	my $msg = $self->check_setup;

	if($msg ne 'OK'){
		return {'error_code'=>'XXX','error_msg'=>$msg};
	}
	if($self->{use_https_authentication}){
		$url = 'https://'.$self->{server_host}.':'
		.$self->{server_https_port};
	}
	else{
		$url = 'http://'.$self->{server_host}.':'
		.$self->{server_port};
	}
	my $func = 'send_'.$self->{data_protocol}.'_request';
	if($self->can($func)){
		return $self->$func($url,@_);
	}
	else{
		return {'error_code'=>501,'error_msg'=>'Data protocol not supported: '.$self->{data_protocol}};
	}
}


sub send_soap_request{
	my $self = shift;
	my $url = shift;
	my %vars = @_;
    if($self->{use_https_authentication}) {
        #set up https authentication vars
        $ENV{HTTPS_CERT_FILE} = $self->{client_certificate_file};
        $ENV{HTTPS_KEY_FILE} = $self->{client_key_file};
        if ($self->{use_https_peer_authentication}){
            $ENV{HTTPS_CA_FILE} = $self->{ca_certificate_file}; 
            $ENV{HTTPS_CA_DIR} = $self->{ca_certificate_path};
        }
    }

	my $func = $vars{action};
	delete $vars{action};
	foreach (keys %vars){
		$vars{$_} = "" unless defined $vars{$_};
	}
	$vars{nt_user_session} = $self->{nt_user_session} if defined $self->{nt_user_session};
	my $soap = SOAP::Lite->new(
		#location of NicToolServer soap server
		proxy=>$url.'/soap',
		#URI is typically org name followed by module path
		uri=>"http://".$self->{server_host}."/NicToolServer/SOAP",
		#don't die on fault, just return result.
		on_fault=>sub {my ($soap,$res)=@_; return $res;}
  	);
	warn "URI: ".$soap->uri . ", proxy: ". $url.'/soap' . "\n" if $self->{debug_soap_setup};
	warn "Calling soap function \"$func\" with params:\n".Dumper(\%vars).'\n' if $self->{debug_soap_request};

	#make soap call and evaluate response.
	my $som = $soap->call($func=>\%vars);

	#result should be SOAP::SOM object if success or fault, or scalar for transport error
	if(!ref $som){
		#scalar means transport error
		warn "SOAP result SCALAR: ".Dumper($som).'\n' if $self->{debug_soap_response};
   		return {error_code=>$soap->transport->code,
    		error_msg=>'SOAP: transport error: '.$url.'/soap'.': '.$soap->transport->status
    	};
    }
	elsif($som->isa('SOAP::SOM') && !$som->fault){
		warn "SOAP result: ".Dumper($som->result).'\n' if $self->{debug_soap_response};
		warn "function $func = \n params{".Dumper(\%vars)."}\n".Dumper($som->result) if $self->{debug_soap_response};

		return $som->result;
	}elsif($som->isa('SOAP::SOM') && $som->fault){
		warn "SOAP result: ".Dumper($som->result).'\n' if $self->{debug_soap_response};
		return {'error_code'=>$som->faultcode,'error_msg'=>'SOAP: fault: '.$som->faultstring};
	}else{
		warn "SOAP result: Unknown: ".Dumper($som).'\n' if $self->{debug_soap_response};
		return {'error_code'=>'??','error_msg'=>'SOAP: Unknown response type:'.ref $som};
	}
}

sub AUTOLOAD{
	my ($self) = shift;
	$NicToolTest::AUTOLOAD =~ s/.*:://;
	if($self->can($NicToolTest::AUTOLOAD)){
		return $self->$NicToolTest::AUTOLOAD(@_);
	}
	else{
		my %args = @_;
		$args{'action'}=$NicToolTest::AUTOLOAD;
		return $self->send_request(%args);
		#print "function not available: $NicToolTest::AUTOLOAD\n";
	}
}


1;

