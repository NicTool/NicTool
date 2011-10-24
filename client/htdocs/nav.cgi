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

    if ( $nt_obj->check_setup eq 'OK' ) {

        my $user = $nt_obj->verify_session();
        if ($user) {
            print $q->header;
            &display( $nt_obj, $q, $user );
        }
    }
}

sub display {
    my ( $nt_obj, $q, $user ) = @_;

    $nt_obj->parse_template($NicToolClient::start_html_template);
    $nt_obj->parse_template($NicToolClient::nav_start_template);

    my $expanded = {
        'expanded' => { map { $_, 1 } split( /,/, $q->param('expanded') ) } };

    my $group = $nt_obj->get_group( nt_group_id => $user->{'nt_group_id'} );

    return $nt_obj->display_error($group) if $group->{'error_code'} != '200';

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print
        "<tr bgcolor=$NicToolClient::dark_grey><td><table cellpadding=0 cellspacing=0 border=0 width=100%>";
    print "<td><img src=$NicToolClient::image_dir/group.gif border=0></td>";
    print
        "<td nowrap><a href=group.cgi?nt_group_id=$group->{'nt_group_id'} target=body>"
        . $group->{'name'} . "</a> "
        . $nt_obj->help_link( 'all', 'Help' ) . "</td>";
    print
        "<td align=right width=100%><a href=\"javascript:window.location = window.location\">refresh</a></td>";
    print "</tr>";
    print "</table></td></tr></table>";

    print "<table cellpadding=0 cellspacing=0 border=0>";
    print "<tr>";
    print "<td><img src=$NicToolClient::image_dir/dirtree_tee.gif></td>";
    print "<td><a href=group_zones.cgi?nt_group_id="
        . $group->{'nt_group_id'}
        . " target=body><img src=$NicToolClient::image_dir/folder_closed.gif border=0></a></td>";
    print "<td><a href=group_zones.cgi?nt_group_id="
        . $group->{'nt_group_id'}
        . " target=body>Zones</a></td>";
    print "</tr>";
    print "</table>";

    print "<table cellpadding=0 cellspacing=0 border=0>";
    print "<tr>";
    print "<td><img src=$NicToolClient::image_dir/dirtree_tee.gif></td>";
    print "<td><a href=group_nameservers.cgi?nt_group_id="
        . $group->{'nt_group_id'}
        . " target=body><img src=$NicToolClient::image_dir/folder_closed.gif border=0></a></td>";
    print "<td><a href=group_nameservers.cgi?nt_group_id="
        . $group->{'nt_group_id'}
        . " target=body>Nameservers</a></td>";
    print "</tr>";
    print "</table>";

    print "<table cellpadding=0 cellspacing=0 border=0>";
    print "<tr>";
    print "<td><img src=$NicToolClient::image_dir/dirtree_tee.gif></td>";
    print "<td><a href=group_users.cgi?nt_group_id="
        . $group->{'nt_group_id'}
        . " target=body><img src=$NicToolClient::image_dir/folder_closed.gif border=0></a></td>";
    print "<td><a href=group_users.cgi?nt_group_id="
        . $group->{'nt_group_id'}
        . " target=body>Users</a></td>";
    print "</tr>";
    print "</table>";

    print "<table cellpadding=0 cellspacing=0 border=0>";
    print "<tr>";
    print "<td><img src=$NicToolClient::image_dir/dirtree_",
        ( $group->{'has_children'} ? 'tee' : 'elbow' ), ".gif></td>";
    print "<td><a href=group_log.cgi?nt_group_id="
        . $group->{'nt_group_id'}
        . " target=body><img src=$NicToolClient::image_dir/folder_closed.gif border=0></a></td>";
    print "<td><a href=group_log.cgi?nt_group_id="
        . $group->{'nt_group_id'}
        . " target=body>Log</a></td>";
    print "</tr>";
    print "</table>";

    &recurse_groups( $nt_obj, $group->{'nt_group_id'}, [], $user, $expanded )
        if ( $group->{'has_children'} );

    $nt_obj->parse_template($NicToolClient::nav_end_template);
    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub recurse_groups {
    my ($nt_obj, $parent_group_id, $levels, $user, $expanded) = @_;

    my $data
        = $nt_obj->get_group_subgroups( nt_group_id => $parent_group_id, limit => 255 );
    return $nt_obj->display_error($data)
        if ( $data->{'error_code'} != '200' );

    my $level_html;
    for (@$levels) {
        if ($_) {
            $level_html
                .= "<td><img src=$NicToolClient::image_dir/dirtree_vertical.gif width=17 height=17></td>";
        }
        else {
            $level_html
                .= "<td><img src=$NicToolClient::image_dir/transparent.gif width=17 height=17></td>";
        }
    }

    my $total = scalar( @{ $data->{'groups'} } ) - 1;

    foreach ( 0 .. $total ) {

        my $group = $data->{'groups'}->[$_];

        my $html
            = $level_html
            . "<td><img src=$NicToolClient::image_dir/"
            . ( $_ == $total ? 'transparent.gif' : 'dirtree_vertical.gif' )
            . " width=17 height=17></td>";

        print "<table cellpadding=0 cellspacing=0 border=0>";
        print "<tr>$level_html";
        print "<td><a href=nav.cgi?"
            . &expand_url( $expanded, 'expanded', $group->{'nt_group_id'} )
            . "><img src=$NicToolClient::image_dir/dirtree_"
            . ( $expanded->{'expanded'}->{ $group->{'nt_group_id'} }
            ? 'minus'
            : 'plus' )
            . '_'
            . ( $_ == $total ? 'elbow' : 'tee' )
            . ".gif border=0></a></td>";
        print
            "<td><img src=$NicToolClient::image_dir/transparent.gif width=4 height=1><img src=$NicToolClient::image_dir/group.gif border=0></td>";
        print
            "<td nowrap><a href=group.cgi?nt_group_id=$group->{'nt_group_id'} target=body>"
            . $group->{'name'}
            . "</a></td>";
        print "</tr>";
        print "</table>";

        if ( $expanded->{'expanded'}->{ $group->{'nt_group_id'} } ) {
            print "<table cellpadding=0 cellspacing=0 border=0>";
            print "<tr>$level_html";
            print "<td><img src=$NicToolClient::image_dir/"
                . ( $_ == $total ? 'transparent' : 'dirtree_vertical' )
                . ".gif width=17 height=17></td>";
            print
                "<td><img src=$NicToolClient::image_dir/dirtree_tee.gif></td>";
            print "<td><a href=group_zones.cgi?nt_group_id="
                . $group->{'nt_group_id'}
                . " target=body><img src=$NicToolClient::image_dir/folder_closed.gif border=0 alt=\"Group Zones\"></a></td>";
            print "<td><a href=group_zones.cgi?nt_group_id="
                . $group->{'nt_group_id'}
                . " target=body>Zones</a></td>";
            print "</tr>";
            print "</table>";

            print "<table cellpadding=0 cellspacing=0 border=0>";
            print "<tr>$level_html";
            print "<td><img src=$NicToolClient::image_dir/"
                . ( $_ == $total ? 'transparent' : 'dirtree_vertical' )
                . ".gif width=17 height=17></td>";
            print
                "<td><img src=$NicToolClient::image_dir/dirtree_tee.gif></td>";
            print "<td><a href=group_nameservers.cgi?nt_group_id="
                . $group->{'nt_group_id'}
                . " target=body><img src=$NicToolClient::image_dir/folder_closed.gif border=0 alt=\"Group Nameservers\"></a></td>";
            print "<td><a href=group_nameservers.cgi?nt_group_id="
                . $group->{'nt_group_id'}
                . " target=body>Nameservers</a></td>";
            print "</tr>";
            print "</table>";

            print "<table cellpadding=0 cellspacing=0 border=0>";
            print "<tr>$level_html";
            print "<td><img src=$NicToolClient::image_dir/"
                . ( $_ == $total ? 'transparent' : 'dirtree_vertical' )
                . ".gif width=17 height=17></td>";
            print
                "<td><img src=$NicToolClient::image_dir/dirtree_tee.gif></td>";
            print "<td><a href=group_users.cgi?nt_group_id="
                . $group->{'nt_group_id'}
                . " target=body><img src=$NicToolClient::image_dir/folder_closed.gif border=0 alt=\"Group Users\"></a></td>";
            print "<td><a href=group_users.cgi?nt_group_id="
                . $group->{'nt_group_id'}
                . " target=body>Users</a></td>";
            print "</tr>";
            print "</table>";

            print "<table cellpadding=0 cellspacing=0 border=0>";
            print "<tr>$level_html";
            print "<td><img src=$NicToolClient::image_dir/"
                . ( $_ == $total ? 'transparent' : 'dirtree_vertical' )
                . ".gif width=17 height=17></td>";
            print "<td><img src=$NicToolClient::image_dir/dirtree_",
                ( $group->{'has_children'} ? 'tee' : 'elbow' ), ".gif></td>";
            print "<td><a href=group_log.cgi?nt_group_id="
                . $group->{'nt_group_id'}
                . " target=body><img src=$NicToolClient::image_dir/folder_closed.gif border=0 alt=\"Group Users\"></a></td>";
            print "<td><a href=group_log.cgi?nt_group_id="
                . $group->{'nt_group_id'}
                . " target=body>Log</a></td>";
            print "</tr>";
            print "</table>";

            if (    $group->{'has_children'}
                and $expanded->{'expanded'}->{ $group->{'nt_group_id'} } )
            {
                &recurse_groups(
                    $nt_obj,
                    $group->{'nt_group_id'},
                    [ ( @$levels, ( $_ == $total ? 0 : 1 ) ) ],
                    $user, $expanded
                );
            }
        }
    }
}

sub expand_url {
    my ( $expanded, $param, $gid ) = @_;

    my @url;

    foreach ( keys %$expanded ) {

        if ( $_ eq $param ) {
            my %expanded = %{ $expanded->{$_} };
            if ( $expanded{$gid} ) {
                delete( $expanded{$gid} );
            }
            else {
                $expanded{$gid} = 1;
            }
            push( @url, "$_=" . join( ',', keys %expanded ) );
        }
        else {
            push( @url, "$_=" . join( ',', keys %{ $expanded->{$_} } ) );
        }
    }

    return join( '&', @url );
}


