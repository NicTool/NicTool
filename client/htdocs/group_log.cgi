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
        my $message;
        if ( $q->param('redirect') ) {
            $message = $nt_obj->redirect_from_log($q);
        }
        print $q->header (-charset=>"utf-8");
        display( $nt_obj, $q, $user, $message );
    }
}

sub display {
    my ( $nt_obj, $q, $user, $message ) = @_;

    $nt_obj->parse_template($NicToolClient::start_html_template);
    $nt_obj->parse_template(
        $NicToolClient::body_frame_start_template,
        username  => $user->{'username'},
        groupname => $user->{'groupname'},
        userid    => $user->{'nt_user_id'}        
    );

    my $level = $nt_obj->display_group_tree(
        $user, $user->{'nt_group_id'}, $q->param('nt_group_id'), 0
    );

    print qq[ 
<div class="light_grey_bg">];

    my $pad = 0;
    for my $x ( 1 .. $level ) {
        if ( $x == $level ) {
            print qq[<img src="$NicToolClient::image_dir/dirtree_elbow.gif" style="padding-left: ${pad}px" class="tee" alt="elbow">];
        };
        $pad += 21;
    }

    print qq[
 <span class="bold">Log</span>
</div>
];

    display_log( $nt_obj, $q, $message );

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
    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields, 50 );

    $sort_fields{'timestamp'} = { 'order' => 1, 'mod' => 'Descending' }
        unless %sort_fields;

    my $rv = $nt_obj->get_global_application_log(%params);
    return $nt_obj->display_nice_error( $rv, "Get NicTool Log" )
        if $rv->{'error_code'} != 200;

    my $log = $rv->{'log'};
    my $map = $rv->{'group_map'};

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        next if ! $q->param($_);
        push @state_fields, "$_=" . $q->escape( $q->param($_) );
    }
    my $state_string = @state_fields ? join('&amp;', @state_fields) : 'not_empty=1';

    $nt_obj->display_nice_error($message) if $message;

    $nt_obj->display_search_rows( $q, $rv, \%params, 'group_log.cgi',
        ['nt_group_id'], $include_subgroups );

    if (!@$log) {
        print "<div class=center>No log data available</div>";
        return;
    };

    print qq[
<table class="fat">
 <tr class=dark_grey_bg>];
    foreach (@columns) {
        if ( $sort_fields{$_} ) {
            print qq[
  <td class="dark_bg center">
   <table class="no_pad">
    <tr>
     <td>$labels{$_}</td>
     <td>&nbsp; &nbsp; $sort_fields{$_}->{'order'} </td>
     <td><img src="$NicToolClient::image_dir/],
       uc( $sort_fields{$_}->{'mod'} ) eq 'ASCENDING' ? 'up.gif' : 'down.gif', qq["></td>
    </tr>
   </table>
  </td>];
        }
        else {
            print qq[
  <td class=center>$labels{$_}</td>];
        }
    }
    print "
 </tr>";

    my $map = $nt_obj->obj_to_cgi_map();
    my $x   = 0;
    my $range;
    foreach my $row (@$log) {
        my $bgcolor = $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg';
        print "
 <tr class=$bgcolor>";
        foreach (@columns) {
            if ( $_ eq 'timestamp' ) {
                print "
  <td>", ( scalar localtime( $row->{$_} ) ), "</td>";
            }
            elsif ( $_ eq 'group_name' ) {
                print qq[
  <td>
   <table class="no_pad">
    <tr>
     <td><img src="$NicToolClient::image_dir/group.gif"></td>
     <td>],
                    join(
                    ' / ',
                    map(qq[<a href="group.cgi?nt_group_id=$_->{'nt_group_id'}">$_->{'name'}</a>],
                        (   @{ $map->{ $row->{'nt_group_id'} } },
                            {   nt_group_id => $row->{'nt_group_id'},
                                name        => $row->{'group_name'}
                            }
                            ) )
                    ),
                    qq[</td>
    </tr>
   </table>
  </td>];
            }
            elsif ( $_ eq 'user' ) {
                print qq[
  <td>
   <table class="no_pad">
    <tr>
     <td><img src="$NicToolClient::image_dir/user.gif"></td>
     <td><a href="user.cgi?nt_group_id=$row->{'nt_group_id'}&amp;nt_user_id=$row->{'nt_user_id'}">$row->{'user'}</a></td>
    </tr>
   </table>
  </td>];
            }
            elsif ( $_ eq 'title' ) {
                my $gid = $q->param('nt_group_id');
                my $url = "group_log.cgi?$state_string&amp;redirect=1&amp;nt_group_id=$gid&amp;object="
                    . $q->escape( $row->{'object'} ) . "&amp;obj_id=" . $q->escape( $row->{'object_id'} );

                print qq[
  <td>
   <table class="no_pad">
    <tr>
     <td><a href="$url"><img src="$NicToolClient::image_dir/$map->{ $row->{'object'} }->{'image'}" alt=""></a></td>
     <td><a href="$url">$row->{'title'}</a></td>
    </tr>
   </table>
  </td>];
            }
            else {
                print "\n  <td>$row->{$_}</td>";
            }
        }
        print "\n </tr>";
    }

    print "\n</table>";
}
