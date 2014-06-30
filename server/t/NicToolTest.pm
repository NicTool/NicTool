package NicToolTest;
# ABSTRACT: Functions for testing nictool

use strict;
use warnings;

require Exporter;
our @ISA    = 'Exporter';
our @EXPORT = qw(diffhtok noerrok errtext nowarn yeswarn);

use Test;
use lib 'api/lib';
use lib '../api/lib';

our $warn = 1;
sub nowarn  { $warn = 0 }
sub yeswarn { $warn = 1 }

sub noerrok {
    my ($obj, $code, $msg) = @_;
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
    return ok( $ec => $code, $msg . " " . join( ":", caller ) );
}

sub errtext {
    my $err = shift;
    if ( ref $err and $err->isa('NicTool::Result') ) {
        return
              $err->error_code . ":"
            . $err->error_desc . ":"
            . $err->error_msg;
    }
    else {
        return
            "$err->{'error_code'}:$err->{'error_desc'}:$err->{'error_msg'}";
    }
}

sub diffhtok {
    my $ht     = shift;
    my $expect = shift;
    my $ok     = 1;
    foreach ( keys %$expect ) {
        if ( $$expect{$_} ne $$ht{$_} ) {
            $ok = 0;
            if ($warn) {
                warn "key $_ is not $$expect{$_} : $$ht{$_} "
                    . join( ":", caller );
            }
        }
    }
    return ok($ok);
}

sub import {
    my $settings;
    my $file = "test.cfg";
    -f $file or $file = "t/test.cfg";
    -f $file or die "could not find your test.cfg file in t/test.cfg\n";

    open( F, "<$file" );
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
Please install the NicTool client library or edit 'test.cfg' to specify its location."
        if $@;

    NicToolTest->export_to_level(1, qw/diffhtok noerrok errtext nowarn yeswarn/ );
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

Abe Shelton

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2011 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abe Shelton, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut

=cut

