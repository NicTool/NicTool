package NicToolServer::Client;
# ABSTRACT: an RPC::XML implementation

use strict;
use APR::Table();
use RPC::XML;
use RPC::XML::Parser;

@NicToolServer::Client::ISA = 'NicToolServer';

sub new {
    my $class = shift;
    my $r     = shift;
    my $self  = {};

    my $contype = $r->headers_in->{'Content-Type'};
    my $conlen  = $r->headers_in->{'Content-Length'};
    my $content;

    # read content if it's xml.  $r->content only works if content-type
    # is 'application/x-www-form-urlencoded' :(
    if ( $contype =~ /^text\/xml$/ ) {
        $r->read( $content, $conlen ) if $conlen gt 0;
    }

    $self->{data} = decode_data( $content, $contype );
    $self->{protocol_version} = $self->{data}{nt_protocol_version};

    bless $self, $class;
}

sub decode_data {
    my ( $data, $type ) = @_;
    if ( $type eq 'text/xml' ) {
        return decode_xml_rpc_data($data);
    }
    return NicToolServer::error_response( 501, $type );
}

sub decode_xml_rpc_data {

    my $P   = new RPC::XML::Parser;
    my $req = $P->parse(shift);

    if ( ref $req ) {

        # TODO if you want multiple arguments, map $req->args and return array
        my $href = $req->args->[0]->value;
        $href->{action} = $req->name;
        return $href;
    }

    return NicToolServer::error_response( 502, $req );
}

sub protocol_version { $_[0]->{protocol_version} }
sub data             { $_[0]->{data} }

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Client - an RPC::XML implementation

=head1 VERSION

version 2.33

=head1 SYNOPSIS

=head1 METHODS

=head2 decode_xml_rpc_data

 Use XML-RPC parser to convert xml to xml-rpc objects.
 A request object has method 'args' which returns an array ref of data-type args.
 Each data-type has a value method to convert to perl data format.
 The 'name' method returns the function being invoked.
 The parser will return a ref to a data-type obj if successful otherwise a scalar error string

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=item *

Damon Edwards

=item *

Abe Shelton

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abe Shelton, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
