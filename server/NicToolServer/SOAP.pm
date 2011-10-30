package NicToolServer::SOAP;

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
use NicToolServer::Client::SOAP;
use vars qw/ $AUTOLOAD /;

@NicToolServer::SOAP::ISA = qw(NicToolServer);

sub _dispatch {
    my ( $class, $action, $data ) = @_;

    $data->{'action'} = $action;

    my $dbh    = &NicToolServer::dbh;
    my $client = NicToolServer::Client::SOAP->new($data);
    my $self   = NicToolServer->new( undef, $client, $dbh, {} );

    $self->{'data'} = $data;

    my $error = NicToolServer::Session->new( undef, $client, $dbh )->verify();

    return $error if $error;

    #warn "action is ".uc($action);
    if (   uc($action) eq 'LOGIN'
        or uc($action) eq 'VERIFY_SESSION'
        or uc($action) eq 'LOGOUT' )
    {
        my $h = $data->{'user'};
        $h->{'password'} = '' if exists $h->{'password'};

        #warn "result of session verify: ".Data::Dumper::Dumper($h);
        return $h;
    }

    $self->{'user'} = $client->data()->{'user'};
    warn "request: " . Data::Dumper::Dumper( $client->data )
        if $self->debug_result;

    if ( my $cmd = $self->api_commands->{$action} ) {

        #warn "data is: ".Data::Dumper::Dumper($data);

        #$error = $self->verify_required($cmd->{'required'},$data);
        #return $error if $error;
        eval { $error = $self->verify_obj_usage( $cmd, $data, $action ); };
        return $self->error_response( 508, $@ ) if $@;
        return $error if $error;

        #$@=undef;
        my $class = 'NicToolServer::' . $cmd->{'class'};
        my $obj   = $class->new( undef, undef, $dbh, $self->{'meta'},
            $self->{'user'} );
        my $method = $cmd->{'method'};
        warn
            "calling NicToolServer action: $cmd->{'class'}::$cmd->{'method'} ("
            . lc($action) . ")\n"
            if $self->debug;
        my $res;
        eval { $res = $obj->$method($data); };
        return $self->error_response( 508, $@ ) if $@;
        warn "result: " . Data::Dumper::Dumper($res) if $self->debug_result;
        return $res;
    }
    else {
        warn "unknown NicToolServer action: ", lc($action), "\n"
            if $self->debug;
        return $self->error_response( 500, $action );
    }
}

sub AUTOLOAD {
    my $self = shift;
    $AUTOLOAD =~ s/.*:://;
    $self->_dispatch( $AUTOLOAD, @_ );
}

1;
