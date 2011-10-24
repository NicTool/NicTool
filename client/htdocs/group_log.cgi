#!/usr/bin/perl
#
# $Id: group_log.cgi 635 2008-09-13 04:03:07Z matt $
#
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
        my $message;
        if ( $q->param('redirect') ) {
            $message = $nt_obj->redirect_from_log($q);
        }
        print $q->header;
        &display( $nt_obj, $q, $user, $message );
    }
}

sub display {
    my ( $nt_obj, $q, $user, $message ) = @_;

    $nt_obj->parse_template($NicToolClient::start_html_template);
    $nt_obj->parse_template(
        $NicToolClient::body_frame_start_template,
        username  => $user->{'username'},
        groupname => $user->{'groupname'}
    );

    my $level = $nt_obj->display_group_tree(
        $user,
        $user->{'nt_group_id'},
        $q->param('nt_group_id'), 0
    );

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td>";
    print "<table cellpadding=0 cellspacing=0 border=0 width=100%>";
    print "<tr>";
    for my $x ( 1 .. $level ) {
        print "<td><img src=$NicToolClient::image_dir/"
            . ( $x == $level ? 'dirtree_elbow' : 'transparent' )
            . ".gif width=17 height=17></td>";
    }

    print "<td nowrap> <b>Log</b></td>";
    print "<td align=right width=100%>", "&nbsp;</td>";
    print "</tr></table>";
    print "</td></tr></table>";

    &display_log( $nt_obj, $q, $message );

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub display_log {
    my ( $nt_obj, $q, $message ) = @_;

    my @columns
        = qw(timestamp group_name user action object title description);

    my %labels = (
        timestamp   => 'Date',
        user        => 'User',
        group_name  => 'User Group',
        action      => 'Action',
        object      => 'Object',
        title       => 'Name',
        description => 'Description',
    );

    my $group = $nt_obj->get_group( nt_group_id  => $q->param('nt_group_id') );
    my $include_subgroups = $group->{'has_children'} ? 'sub-groups' : undef;

    $nt_obj->display_sort_options( $q, \@columns, \%labels, 'group_log.cgi',
        ['nt_group_id'], $include_subgroups )
        if $q->param('edit_sortorder');
    $nt_obj->display_advanced_search( $q, \@columns, \%labels,
        'group_log.cgi', ['nt_group_id'], $include_subgroups )
        if $q->param('edit_search');

    my %params = ( nt_group_id => $q->param('nt_group_id') );
    my %sort_fields;
    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields,
        50 );

    $sort_fields{'timestamp'} = { 'order' => 1, 'mod' => 'Descending' }
        unless %sort_fields;

    my $rv = $nt_obj->get_global_application_log(%params);
    return $nt_obj->display_nice_error( $rv, "Get NicTool Log" )
        if ( $rv->{'error_code'} != 200 );

    my $log = $rv->{'log'};
    my $map = $rv->{'group_map'};

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

    #print "<center><font color=red>$message</font></center>" if( $message );
    $nt_obj->display_nice_error($message) if $message;

    $nt_obj->display_search_rows( $q, $rv, \%params, 'group_log.cgi',
        ['nt_group_id'], $include_subgroups );

    if (@$log) {
        print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
        print "<tr bgcolor=$NicToolClient::dark_grey>";
        foreach (@columns) {
            if ( $sort_fields{$_} ) {
                print
                    "<td bgcolor=$NicToolClient::dark_color align=center><table cellpadding=0 cellspacing=0 border=0>";
                print "<tr>";
                print "<td><font color=white>$labels{$_}</font></td>";
                print "<td>&nbsp; &nbsp; <font color=white>",
                    $sort_fields{$_}->{'order'}, "</font></td>";
                print "<td><img src=$NicToolClient::image_dir/",
                    (
                    uc( $sort_fields{$_}->{'mod'} ) eq 'ASCENDING'
                    ? 'up.gif'
                    : 'down.gif' ), "></tD>";
                print "</tr></table></td>";
            }
            else {
                print "<td align=center>", "$labels{$_}</td>";
            }
        }
        print "</tr>";

        my $map = $nt_obj->obj_to_cgi_map();
        my $x   = 0;
        my $range;
        foreach my $row (@$log) {

            print "<tr bgcolor="
                . ( $x++ % 2 == 0 ? $NicToolClient::light_grey : 'white' )
                . ">";
            foreach (@columns) {
                if ( $_ eq 'timestamp' ) {
                    print "<td>", ( scalar localtime( $row->{$_} ) ), "</td>";
                }
                elsif ( $_ eq 'group_name' ) {
                    print
                        "<td><table cellpadding=0 cellspacing=0 border=0><tr>";
                    print
                        "<td><img src=$NicToolClient::image_dir/group.gif></td>";
                    print "<td>",
                        join(
                        ' / ',
                        map("<a href=group.cgi?nt_group_id=$_->{'nt_group_id'}>$_->{'name'}</a>",
                            (   @{ $map->{ $row->{'nt_group_id'} } },
                                {   nt_group_id => $row->{'nt_group_id'},
                                    name        => $row->{'group_name'}
                                }
                                ) )
                        ),
                        "</td>";
                    print "</tr></table></td>";
                }
                elsif ( $_ eq 'user' ) {
                    print
                        "<td><table cellpadding=0 cellspacing=0 border=0><tr>";
                    print
                        "<td><img src=$NicToolClient::image_dir/user.gif></td>";
                    print
                        "<td><a href=user.cgi?nt_group_id=$row->{'nt_group_id'}&nt_user_id=$row->{'nt_user_id'}>$row->{'user'}</a></td>";
                    print "</tr></table></td>";
                }
                elsif ( $_ eq 'title' ) {
                    print
                        "<td><table cellpadding=0 cellspacing=0 border=0><tr>";
                    print "<td><a href=group_log.cgi?"
                        . join( '&', @state_fields )
                        . "&redirect=1&nt_group_id="
                        . $q->param('nt_group_id')
                        . "&object="
                        . $q->escape( $row->{'object'} )
                        . "&obj_id="
                        . $q->escape( $row->{'object_id'} )
                        . "><img src=$NicToolClient::image_dir/$map->{ $row->{'object'} }->{'image'} border=0></a></td>";
                    print "<td><a href=group_log.cgi?"
                        . join( '&', @state_fields )
                        . "&redirect=1&nt_group_id="
                        . $q->param('nt_group_id')
                        . "&object="
                        . $q->escape( $row->{'object'} )
                        . "&obj_id="
                        . $q->escape( $row->{'object_id'} )
                        . ">$row->{'title'}</a></td>";
                    print "</tr></table></td>";
                }
                else {
                    print "<td>", ( $row->{$_} ? $row->{$_} : '&nbsp;' ),
                        "</td>";
                }
            }
            print "</tr>";
        }

        print "</table>";
    }
    else {
        print "<center>", "No log data available</center>";
    }
}
