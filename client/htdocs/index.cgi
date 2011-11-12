#!/usr/bin/perl
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

require 'nictoolclient.conf';

&main();

sub main {
    my $q      = new CGI();
    my $nt_obj = new NicToolClient($q);

    return if ( $nt_obj->check_setup ne 'OK' );

    if ( $q->param('login') ) {
        if ( $q->param('username') eq '' or $q->param('password') eq '' ) {
            $nt_obj->display_login('Please enter you username and password!');
        }
        else {
            my $data = $nt_obj->login_user();
            if ( ref($data) ) {
                if ( $data->{'error_code'} ) {
                    $nt_obj->display_login($data);
                }
                else {
                    &display_frameset( $q, $nt_obj, $data );
                }
            }
            else {
                $nt_obj->display_login($data);
            }
        }
    }
    elsif ( $q->param('logout') ) {
        my $data = $nt_obj->logout_user();
        $nt_obj->display_login($data);
    }
    else {
        $nt_obj->display_login( $q->param('message') );
    }
}

sub display_frameset {
    my ( $q, $nt_obj, $data ) = @_;

    my $cookie = $q->cookie(
        -name    => 'NicTool',
        -value   => $data->{'nt_user_session'},
        -expires => '+30d',
        -path    => '/'
    );

    print $q->header( -cookie => $cookie );
    $nt_obj->parse_template(
        $NicToolClient::frameset_template,
        nt_group_id => $data->{'nt_group_id'}
    );
}
1;
