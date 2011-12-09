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

    my $expanded = {
        'expanded' => { map { $_, 1 } split( /,/, $q->param('expanded') ) } };

    my $group = $nt_obj->get_group( nt_group_id => $user->{'nt_group_id'} );

    return $nt_obj->display_error($group) if $group->{'error_code'} != '200';

    print qq[
<table class="fat">
 <tr class="dark_grey_bg">
  <td>
   <table class="no_pad fat">
    <tr>
     <td><img src="$NicToolClient::image_dir/group.gif" alt="group icon"></td>
     <td class="nowrap"><a href="group.cgi?nt_group_id=$group->{'nt_group_id'}" target="body"> ]
        . $group->{'name'} . '</a> '
        . $nt_obj->help_link( 'all', 'Help' );
    print qq[
     </td>
     <td class="right fat"><a href="javascript:window.location = window.location">refresh</a></td>
    </tr>
   </table>
  </td>
 </tr>
</table>

<table class="no_pad">
 <tr>
  <td><img src="$NicToolClient::image_dir/dirtree_tee.gif" alt="tee icon"></td>
  <td><a href="group_zones.cgi?nt_group_id=$group->{'nt_group_id'}" target=body><img src="$NicToolClient::image_dir/folder_closed.gif" alt="closed folder icon"></a></td>
  <td><a href="group_zones.cgi?nt_group_id=$group->{'nt_group_id'}" target=body>Zones</a></td>
 </tr>
</table>

<table class='no_pad'>
 <tr>
  <td><img src="$NicToolClient::image_dir/dirtree_tee.gif" alt="tee icon"></td>
  <td><a href="group_nameservers.cgi?nt_group_id=$group->{'nt_group_id'}" target=body><img src="$NicToolClient::image_dir/folder_closed.gif" alt="closed folder icon"></a></td>
  <td><a href="group_nameservers.cgi?nt_group_id=$group->{'nt_group_id'}" target=body>Nameservers</a></td>
 </tr>
</table>

<table class='no_pad'>
 <tr>
  <td><img src="$NicToolClient::image_dir/dirtree_tee.gif" alt="tee icon"></td>
  <td><a href="group_users.cgi?nt_group_id=$group->{'nt_group_id'}" target=body><img src="$NicToolClient::image_dir/folder_closed.gif" alt="closed folder icon"></a></td>
  <td><a href="group_users.cgi?nt_group_id=$group->{'nt_group_id'}" target=body>Users</a></td>
 </tr>
</table>

<table class='no_pad'>
 <tr>
  <td><img src="$NicToolClient::image_dir/dirtree_],
    ( $group->{'has_children'} ? 'tee' : 'elbow' ), qq[.gif" alt="icon"></td>
  <td><a href="group_log.cgi?nt_group_id=$group->{'nt_group_id'}" target=body><img src="$NicToolClient::image_dir/folder_closed.gif" alt=""></a></td>
  <td><a href="group_log.cgi?nt_group_id=$group->{'nt_group_id'}" target=body>Log</a></td>
 </tr>
</table>
];

    &recurse_groups( $nt_obj, $group->{'nt_group_id'}, [], $user, $expanded )
        if ( $group->{'has_children'} );

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
                .= qq[<td><img src="$NicToolClient::image_dir/dirtree_vertical.gif" class="tee" alt=''></td>];
        }
        else {
            $level_html
                .= qq[<td><img src="$NicToolClient::image_dir/transparent.gif" class="tee" alt=''></td>];
        }
    }

    my $total = scalar( @{ $data->{'groups'} } ) - 1;

    foreach ( 0 .. $total ) {

        my $group = $data->{'groups'}->[$_];

        my $html
            = $level_html
            . qq[<td><img src="$NicToolClient::image_dir/]
            . ( $_ == $total ? 'transparent.gif' : 'dirtree_vertical.gif' )
            . qq[" class="tee" alt=""></td>];

        print "<table class='no_pad'>";
        print "<tr>$level_html";
        print qq[<td><a href="nav.cgi?]
            . &expand_url( $expanded, 'expanded', $group->{'nt_group_id'} )
            . qq["><img src="$NicToolClient::image_dir/dirtree_]
            . ( $expanded->{'expanded'}->{ $group->{'nt_group_id'} }
            ? 'minus'
            : 'plus' )
            . '_'
            . ( $_ == $total ? 'elbow' : 'tee' )
            . qq[.gif" alt="dirtree elbow or tee icon"></a></td>
        <td><img src="$NicToolClient::image_dir/transparent.gif" style="width:4; height:1;" alt=""><img src="$NicToolClient::image_dir/group.gif" alt='group icon'></td>
   <td class="nowrap"><a href="group.cgi?nt_group_id=$group->{'nt_group_id'}" target="body"> $group->{'name'} </a>
  </td>
 </tr>
</table>];

        if ( $expanded->{'expanded'}->{ $group->{'nt_group_id'} } ) {
            print qq[
<table class='no_pad'>
 <tr>$level_html
  <td><img src="$NicToolClient::image_dir/]
                . ( $_ == $total ? 'transparent' : 'dirtree_vertical' )
                . qq[.gif" class="tee" alt=""></td>
  <td><img src="$NicToolClient::image_dir/dirtree_tee.gif"></td>
  <td><a href="group_zones.cgi?nt_group_id=$group->{'nt_group_id'}" target="body"><img src="$NicToolClient::image_dir/folder_closed.gif" alt="Group Zones"></a></td>
  <td><a href="group_zones.cgi?nt_group_id=$group->{'nt_group_id'}" target=body>Zones</a></td>
 </tr>
</table>

<table class='no_pad'>
 <tr>$level_html
  <td><img src="$NicToolClient::image_dir/]
                . ( $_ == $total ? 'transparent' : 'dirtree_vertical' )
                . qq[.gif" class="tee" alt=""></td>
  <td><img src="$NicToolClient::image_dir/dirtree_tee.gif"></td>
  <td><a href="group_nameservers.cgi?nt_group_id=$group->{'nt_group_id'}" target="body">
       <img src="$NicToolClient::image_dir/folder_closed.gif" alt="Group Nameservers"></a></td>
  <td><a href="group_nameservers.cgi?nt_group_id=$group->{'nt_group_id'}" target=body>Nameservers</a></td>
 </tr>
</table>

<table class='no_pad'>
 <tr>$level_html
  <td><img src="$NicToolClient::image_dir/]
                . ( $_ == $total ? 'transparent' : 'dirtree_vertical' )
                . qq[.gif" class="tee" alt=""></td>
  <td><img src="$NicToolClient::image_dir/dirtree_tee.gif"></td>
  <td><a href="group_users.cgi?nt_group_id=$group->{'nt_group_id'}" target=body>
      <img src="$NicToolClient::image_dir/folder_closed.gif" alt="Group Users"></a></td>
  <td><a href="group_users.cgi?nt_group_id=$group->{'nt_group_id'}" target=body>Users</a></td>
 </tr>
</table>

<table class='no_pad'>
 <tr>$level_html
  <td><img src="$NicToolClient::image_dir/]
                . ( $_ == $total ? 'transparent' : 'dirtree_vertical' )
                . qq[.gif" class="tee" alt=""></td>
            <td><img src="$NicToolClient::image_dir/dirtree_],
                ( $group->{'has_children'} ? 'tee' : 'elbow' ), qq[.gif"></td>
            <td><a href="group_log.cgi?nt_group_id=$group->{'nt_group_id'}" target=body>
                 <img src="$NicToolClient::image_dir/folder_closed.gif" alt="Group Users"></a></td>
            <td><a href="group_log.cgi?nt_group_id=$group->{'nt_group_id'}" target="body">Log</a></td>
            </tr>
            </table>];

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


