#!/usr/bin/perl
###
# XMLRPC transport module
###
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
###
package NicTool::Transport::XMLRPC;

use RPC::XML;
use RPC::XML::Parser;
use LWP;

use parent 'NicTool::Transport';

sub send_request {
    my $self = shift;
    my $url  = shift;
    my %vars = @_;

    my $com = $vars{action};
    delete $vars{action};

    #encode data into xml-rpc request obj and get xml string
    my $xmlreq
        = RPC::XML::request->new( $com, RPC::XML::smart_encode( \%vars ) );
    my $command = $xmlreq->as_string;

    my $ua = new LWP::UserAgent;
    my $req = HTTP::Request->new( 'POST', $url );

    $ua->agent("NicTool Client Framework v$NicTool::VERSION");
    $req->content_type('text/xml');
    $req->content($command);
    $req->header( "NicTool-protocol_version" => "$NicTool::api_version" );

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
        return $self->_parse_xml($res);
    }
    else {
        return {
            error_code => '501',
            error_msg  => 'XML-RPC: Content-Type not text/xml: ' . $restype
        };
    }

}

# try to parse the xml -- handle xml-rpc faults as well as parsing errors
sub _parse_xml {
    my ( $self, $string ) = @_;

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

=pod

=encoding UTF-8

=head1 NAME

NicTool::Transport::XMLRPC

=head1 VERSION

version 1.02

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
