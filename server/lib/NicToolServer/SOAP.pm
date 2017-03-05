package NicToolServer::SOAP;
# ABSTRACT: SOAP implementation for NicToolServer 

use strict;
use NicToolServer::Client::SOAP;
use vars qw/ $AUTOLOAD /;

@NicToolServer::SOAP::ISA = 'NicToolServer';

sub _dispatch {
    my ( $class, $action, $data ) = @_;

    $data->{action} = $action;

    my $dbh    = &NicToolServer::dbh;
    my $client = NicToolServer::Client::SOAP->new($data);
    my $self   = NicToolServer->new( undef, $client, $dbh, {} );

    $self->{data} = $data;

    my $error = NicToolServer::Session->new( undef, $client, $dbh )->verify();

    return $error if $error;

    #warn "action is ".uc($action);
    if (   uc($action) eq 'LOGIN'
        or uc($action) eq 'VERIFY_SESSION'
        or uc($action) eq 'LOGOUT' )
    {
        my $h = $data->{user};
        $h->{password} = '' if exists $h->{password};

        #warn "result of session verify: ".Data::Dumper::Dumper($h);
        return $h;
    }

    $self->{user} = $client->data()->{user};
    warn "request: " . Data::Dumper::Dumper( $client->data )
        if $self->debug_result;

    if ( my $cmd = $self->api_commands->{$action} ) {

        #warn "data is: ".Data::Dumper::Dumper($data);

        #$error = $self->verify_required($cmd->{required},$data);
        #return $error if $error;
        eval { $error = $self->verify_obj_usage( $cmd, $data, $action ); };
        return $self->error_response( 508, $@ ) if $@;
        return $error if $error;

        #$@=undef;
        my $class = 'NicToolServer::' . $cmd->{class};
        my $obj   = $class->new( undef, undef, $dbh, $self->{meta},
            $self->{user} );
        my $method = $cmd->{method};
        warn
            "calling NicToolServer action: $cmd->{class}::$cmd->{method} ("
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

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::SOAP - SOAP implementation for NicToolServer 

=head1 VERSION

version 2.33

=head1 SYNOPSIS

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
