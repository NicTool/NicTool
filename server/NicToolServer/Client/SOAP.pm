package NicToolServer::Client::SOAP;

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

@NicToolServer::Client::SOAP::ISA = qw(NicToolServer::Client);

sub new {
    my ( $class, $data ) = @_;
    my $self = {};
    $self->{'data'}             = $data;
    $self->{'protocol_version'} = $data->{'nt_protocol_version'};
    return bless $self, $class;
}

sub data { $_[0]->{'data'} }

1;
