package NicToolServer::Response;

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
use RPC::XML;

@NicToolServer::Response::ISA = qw(NicToolServer);

use mod_perl;
use constant MP2 => $mod_perl::VERSION >= 1.99;

sub respond {
    my ( $self, $data ) = @_;

    my $r      = $self->{'Apache'};
    my $client = $self->{'client'};

    if (MP2) {

        # use this for mod_perl 2
        $r->content_type('text/xml');
    }
    else {

        # use this for mod_perl 1
        $r->send_http_header('text/xml');
    }

    print( RPC::XML::response->new($data)->as_string );
}

sub send_error {
    my ( $self, $error ) = @_;

    my $r = $self->{'Apache'};

    #XML-RPC fault
    if (MP2) {

        # use this for mod_perl 2
        $r->content_type('text/xml');
    }
    else {

        # use this for mod_perl 1
        $r->send_http_header('text/xml');
    }
    $r->print(
        RPC::XML::response->new(
            RPC::XML::fault->new(
                $error->{error_code} => $error->{error_msg}
            )
            )->as_string
    );
}

1;
