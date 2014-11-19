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

    return if $nt_obj->check_setup ne 'OK';

    my $user = $nt_obj->verify_session();
    if ($user && ref $user) {
        print $q->header (-charset=>"utf-8");
        display( $nt_obj, $q, $user );
    }
}

sub display {
    my ( $nt_obj, $q, $user ) = @_;

    $nt_obj->parse_template($NicToolClient::start_html_template);

    my $expanded = {
        'expanded' => { map { $_, 1 } split( /,/, $q->param('expanded') ) } };

    my $group = $nt_obj->get_group( nt_group_id => $user->{'nt_group_id'} );

    return $nt_obj->display_error($group) if $group->{'error_code'} != '200';

    my $gid = $group->{nt_group_id};
    my $elbow = qq[<img src="$NicToolClient::image_dir/dirtree_elbow.gif" alt="elbow">];
    my $suffix = qq[cgi?nt_group_id=$gid" target="body];
    my $help = $nt_obj->help_link( 'all', 'Help' );

    print qq[
<div id="navTopRow" class="dark_grey_bg">
  <img src="$NicToolClient::image_dir/group.gif" alt="group icon">
  <a href="group.$suffix">$group->{'name'}</a> $help
  <span class="float_r"><a href="javascript:window.location = window.location">refresh</a></span>
</div>];

    display_group($group, '', '');

    if ( $group->{'has_children'} ) {
        recurse_groups( $nt_obj, $gid, [], $user, $expanded );
    };

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub recurse_groups {
    my ($nt_obj, $parent_group_id, $levels, $user, $expanded) = @_;

    my $data = $nt_obj->get_group_subgroups( nt_group_id => $parent_group_id, limit => 255 );
    return $nt_obj->display_error($data) if $data->{'error_code'} != '200';

    my $level_html;
    for (@$levels) {
        my $icon = $_ ? 'dirtree_vertical' : 'transparent';
        $level_html .= qq[<td><img src="$NicToolClient::image_dir/$icon.gif" class="tee" alt="$icon"></td>];
    }

    my $total = scalar( @{ $data->{'groups'} } ) - 1;

    foreach ( 0 .. $total ) {

        my $group = $data->{'groups'}->[$_];
        my $gid = $group->{nt_group_id};
        my $suffix = qq[cgi?nt_group_id=$gid" target="body];

        my $icon = $_ == $total ? 'transparent' : 'dirtree_vertical';
        my $img2 = qq[<td><img src="$NicToolClient::image_dir/$icon.gif" class="tee" alt="$icon"></td>];
        my $porm = $expanded->{'expanded'}->{ $gid } ? 'minus' : 'plus';
        my $eort = $_ == $total ? 'elbow' : 'tee';
        my $img = qq[<img src="$NicToolClient::image_dir/dirtree_${porm}_$eort.gif" alt="dirtree $eort">];

        print qq[
<table id="navGroupLevel$gid" class='no_pad fat'>
 <tr class="dark_grey_bg">
  $level_html
  <td class="left"><a href="nav.cgi?] . expand_url( $expanded, 'expanded', $gid ) . qq[">$img</a></td>
  <td class="left nowrap fat" style="padding-right: 4px;"><a href="group.$suffix"> 
  <img src="$NicToolClient::image_dir/group.gif" alt="group">$group->{'name'}</a></td>
 </tr>
</table>];

        next if ! $expanded->{'expanded'}->{ $gid };

        display_group($group, $level_html, $img2);

        next if ! $group->{'has_children'};
        next if ! $expanded->{'expanded'}->{ $gid };

        my $thislevels = [ ( @$levels, ( $_ == $total ? 0 : 1 ) ) ];
        recurse_groups( $nt_obj, $gid, $thislevels, $user, $expanded );
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

    return join( '&amp;', @url );
}

sub display_group {
    my ($group, $level_html, $img2) = @_;

    my $gid = $group->{nt_group_id};
    my $suffix = qq[.cgi?nt_group_id=$gid" target="body];
    my $tee    = qq[<img src="$NicToolClient::image_dir/dirtree_tee.gif" alt="tee">];
    my $elbow  = qq[<img src="$NicToolClient::image_dir/dirtree_elbow.gif" alt="elbow">];

    my $suffix = qq[cgi?nt_group_id=$gid" target="body];
    print qq[
<table class='no_pad'>
 <tr>$level_html
  $img2
  <td>$tee</td>
  <td><a href="group_zones.$suffix">Zones</a></td>
 </tr>
</table>

<table class='no_pad'>
 <tr>$level_html
  $img2
  <td>$tee</td>
  <td><a href="group_nameservers.$suffix">Nameservers</a></td>
 </tr>
</table>

<table class='no_pad'>
 <tr>$level_html
  $img2
  <td>$tee</td>
  <td><a href="group_users.$suffix">Users</a></td>
 </tr>
</table>

<table class='no_pad'>
 <tr>$level_html
  $img2
  <td>], $group->{'has_children'} ? $tee : $elbow, qq[</td>
  <td><a href="group_log.$suffix">Log</a></td>
 </tr>
</table>];
};

