#!/usr/bin/perl
#
# $Id: help.cgi 635 2008-09-13 04:03:07Z matt $
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

sub help_text {
    {   perms => {
            name     => 'User and Group Permissions',
            template => "help_perms.html",
            description =>
                'What do the user and group permissions settings mean?',
        },
        delperms => {
            name => 'Delegation Permissions',
            description =>
                'What do the delegation permissions settings mean?',
            template => "help_delperms.html",
        },

        #nonsavail=>{
        #name=>'Usable Nameservers',
        #description=>'Why does it say "No available nameservers"?',
        #template=>"help_nonsavail.html",
        #},
        undeletezone => {
            name        => 'Undelete a Zone',
            description => 'How do I get back the zone I deleted?',
            template    => "help_undeletezone.html",
        },
        undeleterecord => {
            name        => 'Undelete a Resource Record',
            description => 'How do I get back the resource record I deleted?',
            template    => "help_undeleterecord.html",
        },
        rraddress => {
            name => 'Resouce Record Address Field',
            description =>
                'What can I put in the Address field of a Resource Record?',
            template => "help_rraddress.html",
        },

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

    my $message;    #={error_msg=>$q->param('message'),error_desc=>'Message'};
    my $topics = &help_text;
    my $t      = $topics->{ $q->param('topic') };

    if (   $q->param("topic")
        && $q->param('topic') ne 'all'
        && !exists $topics->{ $q->param('topic') } )
    {
        $message = {
            error_msg =>
                "Sorry that help topic was not found.  Please choose from the available topics.",
            error_desc => 'No Such Topic'
        };
    }

    if ( $q->param("topic") && exists $topics->{ $q->param('topic') } ) {
        if ( $t->{'template'} ) {
            $nt_obj->parse_template(
                $NicToolClient::template_dir . "/help_start.html", %$t );
            $nt_obj->parse_template(
                $NicToolClient::template_dir . "/" . $t->{'template'}, %$t );
            $nt_obj->parse_template(
                $NicToolClient::template_dir . "/help_end.html" );
        }
        else {

 #print "<center><font color=red><b>$message</b></font></center>" if $message;
            $nt_obj->display_nice_error($message) if $message;
            $nt_obj->parse_template(
                $NicToolClient::template_dir . "/help_start.html", %$t );
            print " $t->{'text'}";
            $nt_obj->parse_template(
                $NicToolClient::template_dir . "/help_end.html" );
        }

    }
    else {

 #print "<center><font color=red><b>$message</b></font></center>" if $message;
        $nt_obj->display_nice_error($message) if $message;
        print qq(
        <Table width=100% cellpadding=6 cellspacing=2>
            <tr bgcolor=$NicToolClient::dark_color><td colspan=2><font color=white>Help Topics</font></td></tr>
        );
        foreach my $k ( keys %$topics ) {
            my $t = $topics->{$k};
            print qq(
            <tr bgcolor=$NicToolClient::light_grey>
                <td align=right>
                    <table width=100% border=0 cellspacing=0 cellpadding=4>
                        <tr>
                            <td valign=center align=left><img src=$NicToolClient::image_dir/help.gif></td>
                            <td valign=center align=left width=100% nowrap><a href="help.cgi?topic=$k">$t->{'name'}</a></td>
                        </tr>
                    </table>
                </td>
                <td width=100% align=left> $t->{'description'}</td>
            </tr>);
        }
        print qq(
            <tr bgcolor=$NicToolClient::dark_grey><td colspan=2 align=center><form><input type=button value="Close" onClick="window.close()"></form></td></tr> 
        </table>
        );

    }

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

