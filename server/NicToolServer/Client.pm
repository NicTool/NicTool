package NicToolServer::Client;

#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under
# the terms of the Affero General Public License as published by Affero,
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#

use strict;
use APR::Table();
use RPC::XML;
use RPC::XML::Parser;

@NicToolServer::Client::ISA = qw(NicToolServer);

sub new {
    my $class = shift;
    my $r     = shift;
    my %self  = ();

    my $contype = $r->headers_in->{'Content-Type'};
    my $conlen  = $r->headers_in->{'Content-Length'};
    my $content;

    # read content if it's xml.  $r->content only works if content-type
    # is 'application/x-www-form-urlencoded' :(
    if ( $contype =~ /^text\/xml$/ ) {
        $r->read( $content, $conlen ) if ( $conlen gt 0 );
    }

    $self{'data'} = {};
    $self{'data'} = decode_data( $content, $r->headers_in->{'Content-Type'} );
    $self{'protocol_version'} = $self{'data'}->{'nt_protocol_version'};

    bless \%self, $class;
}

sub decode_data {
    my ( $data, $type ) = @_;
    if ( $type =~ /^text\/xml$/ ) {
        return decode_xml_rpc_data($data);
    }
    else {
        return NicToolServer::error_response( 501, $type );
    }
}

# Use XML-RPC parser to convert xml to xml-rpc objects.
# A request object has method 'args' which returns
# an array ref of data-type args.
# Each data-type has a value method to convert
# to perl data format.
# The 'name' method returns the function being invoked.
# The parser will return a ref to a data-type obj if successful
# otherwise a scalar error string
#

sub decode_xml_rpc_data {

    my $P   = new RPC::XML::Parser;
    my $req = $P->parse(shift);

    if ( ref($req) ) {

        # TODO if you want multiple arguments, map $req->args and return array
        my $href = $req->args->[0]->value;
        $href->{'action'} = $req->name;
        return $href;
    }

    return NicToolServer::error_response( 502, $req );

}

sub protocol_version { $_[0]->{'protocol_version'} }
sub data             { $_[0]->{'data'} }

1;
