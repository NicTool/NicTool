#!/usr/bin/perl
#
# $Id: group_zones_query_log.cgi 635 2008-09-13 04:03:07Z matt $
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

    my $level = $nt_obj->display_group_tree(
        $user,
        $user->{'nt_group_id'},
        $q->param('nt_group_id'), 0
    );
    $nt_obj->display_zone_list_options( $user, $q->param('nt_group_id'),
        $level, 0 );

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print
        "<tr bgcolor=$NicToolClient::light_grey><td><table cellpadding=0 cellspacing=0 border=0 width=100%>";
    print "<tr>";
    foreach ( 1 .. $level ) {
        print
            "<td><img src=$NicToolClient::image_dir/transparent.gif width=16 height=16></td>";
    }
    print "<td><img src=$NicToolClient::image_dir/dirtree_elbow.gif></td>";
    print
        "<td><img src=$NicToolClient::image_dir/transparent.gif width=1 height=16></td>";
    print "<td><img src=$NicToolClient::image_dir/graph.gif></td>";
    print
        "<td><img src=$NicToolClient::image_dir/transparent.gif width=3 height=16></td>";
    print "<td nowrap>",                 " <b>Nameserver Query Log</b></td>";
    print "<td align=right width=100%>", "&nbsp;</td>";
    print "</tr>";
    print "</table></td></tr>";
    print "</table>";

    my @columns = qw(timestamp nameserver zone query qtype flag ip port);
    my %labels  = (
        timestamp  => 'Time',
        nameserver => 'NameServer',
        zone       => 'Zone',
        query      => 'Query',
        qtype      => 'Query Type',
        flag       => 'Flag',
        ip         => 'IP Address',
        port       => 'Port'
    );

    $nt_obj->display_sort_options( $q, \@columns, \%labels,
        'group_zones_query_log.cgi', ['nt_group_id'] )
        if $q->param('edit_sortorder');
    $nt_obj->display_advanced_search( $q, \@columns, \%labels,
        'group_zones_query_log.cgi', ['nt_group_id'] )
        if $q->param('edit_search');

    my %params = ( nt_group_id => $q->param('nt_group_id') );
    my %sort_fields;

    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields,
        20 );

    $sort_fields{'timestamp'} = { 'order' => 1, 'mod' => 'DESCENDING' }
        unless %sort_fields;

    my $rv = $nt_obj->get_group_zone_query_log(%params);

    return $nt_obj->display_error($rv) if ( $rv->{'error_code'} != '200' );

    $nt_obj->display_search_rows( $q, $rv, \%params,
        'group_zones_query_log.cgi', ['nt_group_id'] );

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

    my $x = 0;
    foreach my $row ( @{ $rv->{'search_result'} } ) {
        print "<tr bgcolor=",
            ( $x++ % 2 == 0 ? $NicToolClient::light_grey : 'white' ), ">";
        foreach (@columns) {
            if ( $_ eq 'timestamp' ) {
                print "<td>", ( scalar localtime $row->{$_} ), "</td>";
            }
            elsif ( $_ eq 'nameserver' ) {
                print "<td><table cellpadding=0 cellspacing=0 border=0><tr>";

#print "<td><img src=$NicToolClient::image_dir/nameserver.gif border=0></td>";
                print "<td>$row->{$_}</td>";
                print "</tr></table></td>";
            }
            elsif ( $_ eq 'zone' ) {
                print "<td><table cellpadding=0 cellspacing=0 border=0><tr>";
                print "<td><a href=zone.cgi?nt_group_id="
                    . $q->param('nt_group_id')
                    . "&nt_zone_id=$row->{'nt_zone_id'}><img src=$NicToolClient::image_dir/zone.gif border=0></a></td>";
                print "<td><a href=zone.cgi?nt_group_id="
                    . $q->param('nt_group_id')
                    . "&nt_zone_id=$row->{'nt_zone_id'}>$row->{$_}</a></td>";
                print "</tr></table></td>";
            }
            elsif ( $_ eq 'query' ) {
                print "<td><table cellpadding=0 cellspacing=0 border=0><tr>";
                print "<td><a href=zone.cgi?nt_group_id="
                    . $q->param('nt_group_id')
                    . "&nt_zone_id=$row->{'nt_zone_id'}&nt_zone_record_id=$row->{'nt_zone_record_id'}&edit_record=1><img src=$NicToolClient::image_dir/r_record.gif border=0></a></td>";
                print "<td><a href=zone.cgi?nt_group_id="
                    . $q->param('nt_group_id')
                    . "&nt_zone_id=$row->{'nt_zone_id'}&nt_zone_record_id=$row->{'nt_zone_record_id'}&edit_record=1>$row->{$_}</a></td>";
                print "</tr></table></td>";
            }
            else {
                print "<td>", $row->{$_}, "</td>";
            }
        }
        print "</tr>";
    }
    print "</table>";
    print $q->endform;
}
