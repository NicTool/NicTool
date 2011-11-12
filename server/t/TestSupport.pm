##########
# TestSupport.pm
# Functions for testing nictool
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

package TestSupport;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(diffhtok noerrok nowarn yeswarn errtext);
use Test;

our $warn = 1;
sub nowarn  { $warn = 0 }
sub yeswarn { $warn = 1 }

sub noerrok {
    my $obj  = shift;
    my $code = shift;
    my $msg  = shift;
    $msg  ||= '';
    $code ||= 200;
    my ( $ec, $em, $ed );
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

    #stop undef concat warns
    $ec = '' unless $ec;
    $em = '' unless $em;
    $ed = '' unless $ed;
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
