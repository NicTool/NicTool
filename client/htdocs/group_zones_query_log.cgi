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

    my $level = $nt_obj->display_group_tree(
        $user,
        $user->{'nt_group_id'},
        $q->param('nt_group_id'), 0
    );
    $nt_obj->display_zone_list_options( $user, $q->param('nt_group_id'), $level, 0 );

    print qq[<table class="fat">
    <tr class=light_grey_bg><td><table class="no_pad fat">
    <tr>];
    foreach ( 1 .. $level ) {
        print "<td><img src=$NicToolClient::image_dir/transparent.gif width=16 height=16></td>";
    }
    print qq[<td><img src="$NicToolClient::image_dir/dirtree_elbow.gif"></td>
    <td><img src="$NicToolClient::image_dir/transparent.gif" width=1 height=16></td>
    <td><img src="$NicToolClient::image_dir/graph.gif"></td>
    <td><img src="$NicToolClient::image_dir/transparent.gif" width=3 height=16></td>
    <td class="nowrap"><b>Nameserver Query Log</b></td>
    <td class="right fat"> &nbsp;</td>
    </tr>
    </table></td></tr>
    </table>];

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

    my $gid = $q->param('nt_group_id');
    my %params = ( nt_group_id => $gid );
    my %sort_fields;

    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields,
        20 );

    $sort_fields{'timestamp'} = { 'order' => 1, 'mod' => 'DESCENDING' }
        unless %sort_fields;

    my $rv = $nt_obj->get_group_zone_query_log(%params);

    return $nt_obj->display_error($rv) if ( $rv->{'error_code'} != '200' );

    $nt_obj->display_search_rows( $q, $rv, \%params,
        'group_zones_query_log.cgi', ['nt_group_id'] );

    print qq[<table class="fat">
    <tr class=dark_grey_bg>];
    foreach (@columns) {
        if ( $sort_fields{$_} ) {
            print qq[<td class="dark_bg center"><table class="no_tab">
            <tr>
            <td>$labels{$_}</td>
            <td>&nbsp; &nbsp; $sort_fields{$_}->{'order'} </td>
            <td><img src=$NicToolClient::image_dir/],
                (
                uc( $sort_fields{$_}->{'mod'} ) eq 'ASCENDING'
                ? 'up.gif'
                : 'down.gif' ), "></tD>";
            print "</tr></table></td>";

        }
        else {
            print "<td class=center>$labels{$_}</td>";
        }
    }
    print "</tr>";

    my $x = 0;
    foreach my $row ( @{ $rv->{'search_result'} } ) {
        print "<tr class=",
            ( $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg' ), ">";
        foreach (@columns) {
            if ( $_ eq 'timestamp' ) {
                print "<td>", ( scalar localtime $row->{$_} ), "</td>";
            }
            elsif ( $_ eq 'nameserver' ) {
                print qq[<td><table class="no_pad"><tr>
                <td>$row->{$_}</td>
                </tr></table></td>];
            }
            elsif ( $_ eq 'zone' ) {
                print qq[<td><table class="no_pad"><tr>
                <td><a href="zone.cgi?nt_group_id=$gid&amp;nt_zone_id=$row->{'nt_zone_id'}"><img src="$NicToolClient::image_dir/zone.gif"></a></td>
                <td><a href="zone.cgi?nt_group_id=$gid&amp;nt_zone_id=$row->{'nt_zone_id'}">$row->{$_}</a></td>
                </tr></table></td>];
            }
            elsif ( $_ eq 'query' ) {
                print qq[<td><table class="no_pad"><tr>
                <td><a href="zone.cgi?nt_group_id=$gid&amp;nt_zone_id=$row->{'nt_zone_id'}&amp;nt_zone_record_id=$row->{'nt_zone_record_id'}&amp;edit_record=1"><img src="$NicToolClient::image_dir/r_record.gif"></a></td>
                <td><a href="zone.cgi?nt_group_id=$gid&amp;nt_zone_id=$row->{'nt_zone_id'}&amp;nt_zone_record_id=$row->{'nt_zone_record_id'}&amp;edit_record=1">$row->{$_}</a></td>
                </tr></table></td>];
            }
            else {
                print "<td>", $row->{$_}, "</td>";
            }
        }
        print "</tr>";
    }
    print "</table>";
    print $q->end_form;
}
