#!/usr/bin/perl
#
# $Id: move_users.cgi 635 2008-09-13 04:03:07Z matt $
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

    my $user = $nt_obj->verify_session();

    if ($user) {
        print $q->header;
        &display( $nt_obj, $q, $user );
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
        print "<script language='JavaScript'>";
        print "window.close();";
        print "</script>";

        # do nothing
    }
    elsif ( $q->param('Save') ) {
        my $rv = $nt_obj->move_users(
            nt_group_id => $q->param('group_list'),
            user_list   => $q->param('obj_list')
        );
        if ( $rv->{'error_code'} != 200 ) {

            #$nt_obj->display_error($rv);
            &move( $nt_obj, $user, $q, $rv );
        }
        else {
            print "<script language='JavaScript'>";

            #print "window.opener.location = window.opener.location;";
            print "window.close();";
            print "</script>";

            print "<center><B>Users Moved</B></center>";
        }
    }
    else {
        &move( $nt_obj, $user, $q );
    }

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub move {
    my ( $nt_obj, $user, $q, $message ) = @_;

    $q->param( 'obj_list', join( ',', $q->param('obj_list') ) );

    #warn "obj_list = " . $q->param('obj_list') . " ..\n";

    my $rv = $nt_obj->get_user_list( user_list => $q->param('obj_list') );

    return $nt_obj->display_error($rv) if ( $rv->{'error_code'} != 200 );

    my $list = $rv->{'list'};

    #warn "list = @$list ..\n";
    foreach my $h (@$list) {
        foreach my $hk ( keys %$h ) {

            #warn "user $hk = $h->{$hk}\n";
        }

        #warn "end user\n";
    }

 #print "<center><font color=red><b>$message</b></font></center>" if $message;
    $nt_obj->display_nice_error( $message, "Move Users" ) if $message;

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print
        "<tr bgcolor=$NicToolClient::dark_color><td colspan=2>$NicToolClient::font<font color=white><b>Move Users</b></font></font></td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td nowrap valign=top>", "Users: </td>";
    print "<td width=100%>",
        join(
        ', ',
        map("<a href=user.cgi?nt_group_id=$_->{'nt_group_id'}&nt_user_id=$_->{'nt_user_id'} target=_blank>$_->{'username'}</a>",
            @$list )
        ),
        "</td>";
    print "</tr>";
    print "</table>";

    $nt_obj->display_group_list( $q, $user, 'move_users.cgi' );

    print "\n<table cellpadding=2 cellspacing=2 border=0 width=100%>\n";
    print "<tr bgcolor=$NicToolClient::dark_grey><td colspan=2 align=center>",
        $q->submit('Save'),
        $q->submit(
        -name    => 'cancel_move',
        -value   => 'Cancel',
        -onClick => 'window.close(); return false;'
        ),
        "</td></tr>";
    print "</table>\n";
    print $q->end_form;
}

