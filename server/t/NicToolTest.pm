package NicToolTest;

# ABSTRACT: Functions for testing nictool

use strict;
use warnings;

require Exporter;
our @ISA    = 'Exporter';
our @EXPORT = qw/
    noerrok errtext param_error_ok bad_id_ok sanity_error_ok new_id_ok fetched_ok
    nt_client nt_api_connect
    /;

use Test::More;
use lib 'api/lib';
use lib '../api/lib';

sub noerrok {
    my ( $obj, $code, $msg ) = @_;
    $msg  ||= '';
    $code ||= 200;
    my $ec = my $em = my $ed = '';
    if ( ref $obj and $obj->can('error_code') ) {
        $ec = $obj->error_code;
        $em = $obj->error_msg;
        $ed = $obj->error_desc;
    }
    elsif ( ref $obj and $obj->can('get') ) {
        $ec = $obj->get('error_code');
        $em = $obj->get('error_msg');
        $ed = $obj->get('error_desc');
    }
    elsif ( exists $obj->{'error_code'} ) {
        $ec = $obj->{'error_code'};
        $em = $obj->{'error_msg'};
        $ed = $obj->{'error_desc'};
    }
    elsif ( exists $obj->{'store'}->{'error_code'} ) {
        $ec = $obj->{'store'}->{'error_code'};
        $em = $obj->{'store'}->{'error_msg'};
        $ed = $obj->{'store'}->{'error_desc'};
    }
    else {
        warn "No idea! (ref " . ( ref $obj ) . ")";
        $ec = $em = $ed = '?';
    }

    $em ||= '';
    $ec ||= '';
    $ed ||= '';
    $msg .= "($ec :$em :$ed)";
    if ( $ec eq $code ) {
        return is( $ec, $code, $em );
    }
    return is( $ec, $code, $msg . " " . join( ":", caller ) );
}

sub errtext {
    my $err = shift;
    if ( ref $err and $err->isa('NicTool::Result') ) {
        return $err->error_code . ":" . $err->error_desc . ":" . $err->error_msg;
    }
    return "$err->{'error_code'}:$err->{'error_desc'}:$err->{'error_msg'}";
}

my %param_error_desc = (
    301 => qr/Required parameters missing/,
    302 => qr/Some parameters were invalid/,
);

sub param_error_ok {
    my ( $res, $code, $param, $name ) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    noerrok( $res, $code, $name );
    is( $res->get('error_msg'), $param );
    ok( $res->get('error_desc') =~ $param_error_desc{$code} );
}

# an empty id is missing (301), any other bad value is invalid (302)
sub bad_id_ok {
    my ( $param, $call, @values ) = @_;
    @values = ( '', 'abc', 0 ) if !@values;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    param_error_ok( $call->($_), length $_ ? 302 : 301, $param ) for @values;
}

sub sanity_error_ok {
    my ( $res, $msg, $name ) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    noerrok( $res, 300, $name );
    ok( $res->get('error_msg')  =~ $msg );
    ok( $res->get('error_desc') =~ qr/Sanity error/ );
}

sub new_id_ok {
    my ( $res, $field, $why ) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    noerrok($res) && ok( $res->get($field) =~ qr/^\d+$/ ) or die $why;
    return $res->get($field);
}

sub fetched_ok {
    my ( $obj, $id, $why ) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    noerrok($obj) && is( $obj->id, $id ) or die $why;
    return $obj;
}

sub import {
    my $settings;
    my $file = "test.cfg";
    -f $file or $file = "t/test.cfg";
    -f $file
        or die "could not find t/test.cfg; run dist/setup/setup-test-env.pl "
        . "or start the container with NICTOOL_TEST_ENV=1\n";

    open( F, "<", $file );
    my $c;
    {
        local $/;
        $c = <F>;
    }
    close(F);
    my $s = eval $c;
    if (   $s->{'server_host'}
        && $s->{'server_port'}
        && $s->{'data_protocol'}
        && $s->{'username'}
        && $s->{'password'} )
    {
        $settings = $s;
    }

    die "You must edit the file 'test.cfg' to specify connection parameters."
        unless $settings;

    my $conf = sub {
        my $param = shift;
        return $settings->{$param};
    };

    *main::Config = $conf;

    if ( exists $settings->{'lib'} ) {
        eval " use lib '$settings->{'lib'}' ";
    }

    eval "use NicTool";
    die "Couldn't 'use NicTool'. $@
Please install the NicTool api library or edit 'test.cfg' to specify its location."
        if $@;

    NicToolTest->export_to_level(1);
}

sub nt_client {
    return NicTool->new(
        cache_users  => 0,
        cache_groups => 0,
        server_host  => main::Config('server_host'),
        server_port  => main::Config('server_port'),
        @_
    );
}

sub nt_api_connect () {

    my $user = nt_client();

    ok( ref $user, 'NicTool API client' )
        or die "Couldn't create NicTool Object";

    $user->login(
        username => main::Config('username'),
        password => main::Config('password')
    );

    noerrok( $user->result ) or die "Couldn't log in";
    ok( !$user->result->is_error, "login no error" );
    ok( $user->nt_user_session,   "login session" );

    return $user;
}

1;

__END__

=head1 SYNOPSIS

Exports the Config settings (from test.cfg) and NicTool specific test functions

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=item *

Damon Edwards

=item *

Abraham Ingersoll

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2011 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abraham Ingersoll, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut

=cut

