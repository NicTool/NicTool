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

main();

sub main {
    my $q      = new CGI();
    my $nt_obj = new NicToolClient($q);

    return if ( $nt_obj->check_setup ne 'OK' );

    my $user = $nt_obj->verify_session();

    if ($user && ref $user) {
        print $q->header (-charset=>"utf-8");
        display( $nt_obj, $q, $user );
    }
}

sub display {
    my ( $nt_obj, $q, $user ) = @_;

    $nt_obj->parse_template($NicToolClient::start_html_template);
    $nt_obj->parse_template(
        $NicToolClient::body_frame_start_template,
        username  => $user->{'username'},
        groupname => $user->{'groupname'},
        userid    => $user->{'nt_user_id'}
    );

    if ( $q->param('cancel_move') ) {
        print qq[<script> window.close(); </script>];

        # do nothing
    }
    elsif ( $q->param('Save') ) {
        my $rv = $nt_obj->move_nameservers(
            nt_group_id     => scalar($q->param('group_list')),
            nameserver_list => scalar($q->param('obj_list'))
        );
        if ( $rv->{'error_code'} != 200 ) {

            #$nt_obj->display_error($rv);
            move( $nt_obj, $user, $q, $rv );
        }
        else {
            print qq[<script> window.close(); </script>];
            print "<center><B>Nameservers Moved</B></center>";
        }
    }
    else {
        move( $nt_obj, $user, $q );
    }

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub move {
    my ( $nt_obj, $user, $q, $message ) = @_;

    $q->param( 'obj_list', join( ',', $q->multi_param('obj_list') ) );

    my $rv = $nt_obj->get_nameserver_list(
        nameserver_list => scalar($q->param('obj_list')) );

    return $nt_obj->display_error($rv) if ( $rv->{'error_code'} != 200 );

    my $list = $rv->{'list'};

    $nt_obj->display_nice_error($message) if $message;

    print qq[
<div class="side_pad dark_bg bold">Move Nameservers</div>
<div class="side_pad light_grey_bg top"> Nameservers: ],
        join( ', ', map(
qq[<a href="group_nameservers.cgi?nt_group_id=$_->{'nt_group_id'}&amp;nt_nameserver_id=$_->{'nt_nameserver_id'}" target="_blank">$_->{'name'}</a>], @$list )
        ),
        "
</div>";

    $nt_obj->display_group_list( $q, $user, 'move_nameservers.cgi' );

    print qq[
<div class="dark_grey_bg center side_pad">],
        $q->submit('Save'),
        $q->submit(
        -name    => 'cancel_move',
        -value   => 'Cancel',
        -onClick => 'window.close(); return false;'
        ),
        "
</div>\n",
    $q->end_form;
}

