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
        export_serials => {
            name => 'Export Zone Serial Numbers',
            description => 'Why disable serial numbers exports?',
            template => "help_export_serials.html",
        },
        timestamp => {
            name => 'Timestamps',
            description => 'Timestamps on Resource Records',
            template => "help_timestamp.html",
        },
        location => {
            name => 'Location',
            description => 'Locations on Resource Records',
            template => "help_location.html",
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

    my $message;
    my $topics = help_text;
    my $t      = $topics->{ $q->param('topic') };

    if (   $q->param("topic")
        && $q->param('topic') ne 'all'
        && !exists $topics->{ $q->param('topic') } )
    {
        $message = {
            error_msg =>
                "Sorry that help topic was not found. Please choose from the available topics.",
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

            $nt_obj->display_nice_error($message) if $message;
            $nt_obj->parse_template(
                $NicToolClient::template_dir . "/help_start.html", %$t );
            print " $t->{'text'}";
            $nt_obj->parse_template(
                $NicToolClient::template_dir . "/help_end.html" );
        }
    }
    else {

        $nt_obj->display_nice_error($message) if $message;
        print qq(
        <table style="width:100%; padding:6; border-spacing:2;">
            <tr class=dark_bg><td colspan=2>Help Topics</td></tr>
        );
        foreach my $k ( keys %$topics ) {
            my $t = $topics->{$k};
            print qq[
            <tr class=light_grey_bg>
             <td class="right">
              <table class="fat" style="border-spacing:0; padding:4;">
               <tr>
                <td style="middle left"><img src="$NicToolClient::image_dir/help.gif"></td>
                <td class="left fat nowrap middle"><a href="help.cgi?topic=$k">$t->{'name'}</a></td>
               </tr>
              </table>
             </td>
             <td class="fat left"> $t->{'description'}</td>
            </tr>];
        }
        print qq[
            <tr class=dark_grey_bg><td colspan=2 class=center><form><input type=button value="Close" onClick="window.close()"></form></td></tr> 
        </table>
        ];

    }

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

