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

    return if ! $user || ! ref $user;

    print $q->header (-charset=>"utf-8");
    display( $nt_obj, $q, $user );
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

    my @fields = qw/ user_create user_delete user_write group_create group_delete group_write zone_create zone_delegate zone_delete zone_write zonerecord_create zonerecord_delegate zonerecord_delete zonerecord_write nameserver_create nameserver_delete nameserver_write self_write /;

    my $error;
    if ( $q->param('new') && $q->param('Create') ) {
        $error = _display_new_group( $nt_obj, $q, \@fields );
    }
    elsif ( $q->param('edit') && $q->param('Save') ) {
        $error = _display_edit_group( $nt_obj, $q, \@fields );
    };

    $nt_obj->display_group_tree(
        $user,
        $user->{'nt_group_id'},
        $q->param('nt_group_id'), 1
    );

    if ( $q->param('edit') ) {
        if ( $q->param('Save') ) {
            if ( $error->{'error_code'} != 200 ) {
                $nt_obj->display_nice_error( $error, "Edit Group" );
                display_edit( $nt_obj, $user, $q, "edit" );
            }
            else {
                $nt_obj->refresh_nav();
            }
        }
        elsif ( $q->param('Cancel') ) { }
        else {
            display_edit( $nt_obj, $user, $q, "edit" );
        }
    }
    elsif ( $q->param('new') ) {
        if ( $q->param('Create') ) {
            if ( $error->{'error_code'} != 200 ) {
                $nt_obj->display_nice_error( $error, "New Group" );
                display_edit( $nt_obj, $user, $q, "new" );
            }
            else {
                $nt_obj->refresh_nav();
            }
        }
        elsif ( $q->param('Cancel') ) { }
        else {
            display_edit( $nt_obj, $user, $q, "new" );
        }
    }

    if ( $q->param('delete') ) {
        my $rv = $nt_obj->delete_group( nt_group_id => $q->param('delete') );
        $nt_obj->display_nice_error( $rv, "Delete Group" ) if $rv->{'error_code'} != 200;
        $nt_obj->refresh_nav();
    }

    my $group = $nt_obj->get_group( nt_group_id  => $q->param('nt_group_id') );

    display_group_list( $nt_obj, $q, $group, $user );

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub _display_new_group {
    my ( $nt_obj, $q, $fields ) = @_;

    my %params = (
        nt_group_id => $q->param('nt_group_id'),
        name        => $q->param('name')
    );
    my @ns = $q->param("usable_nameservers");
    $params{"usable_nameservers"} = join( ',', @ns );
    foreach (@$fields) {
        $params{$_} = $q->param($_) ? 1 : 0;
    };

    return $nt_obj->new_group(%params);
};

sub _display_edit_group {
    my ( $nt_obj, $q, $fields ) = @_;

    my %params = (
        nt_group_id => $q->param('nt_group_id'),
        name        => $q->param('name'),
    );

    my @ns = $q->param("usable_nameservers");
    $params{"usable_nameservers"} = join( ",", @ns );
    foreach (@$fields) {
        $params{$_} = $q->param($_) ? 1 : 0;
    };

    return $nt_obj->edit_group(%params);
}

sub display_zone_search {
    my ( $nt_obj, $q, $group ) = @_;

    print qq[ 
<table class="fat">
 <tr class=dark_grey_bg><td><table class="no_pad fat">
    <tr> ],
    $q->startform( -action => 'group.cgi', -method => 'POST' ),
    $q->hidden( -name => 'nt_group_id' ),
    qq[ <td> ],
    $q->textfield( -name => 'search_value', -size => 30, -override => 1 ),
    $q->hidden(
        -name     => 'quick_search',
        -value    => 'Enter',
        -override => 1
    ),
    $q->submit( -name => 'quick_search', -value => 'Search Zones' );
    if ( $group->{'has_children'} ) {
        print " &nbsp; &nbsp;",
            $q->checkbox(
            -name     => 'include_subgroups',
            -value    => 1,
            -label    => 'include sub-groups',
            -override => 1
            );
    };
    print $q->end_form,
    "</td>
    </tr>
   </table>
  </td>
 </tr>
</table>";
}

sub display_group_list {
    my ( $nt_obj, $q, $group, $user ) = @_;

    my @columns = qw/ group /;
    my $cgi = 'group.cgi';

    my %labels = ( group => 'Group', sub_groups => '*Sub Groups' );

    my $include_subgroups = $group->{'has_children'} ? 'sub-groups' : undef;

    my %params = (
        nt_group_id    => $q->param('nt_group_id'),
        start_group_id => $q->param('nt_group_id'),
    );
    my %sort_fields;
    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields, 10 );
    $sort_fields{'group'} = { 'order' => 1, 'mod' => 'Ascending' } if ! %sort_fields;

    my $rv = $nt_obj->get_group_subgroups(%params);

    _display_group_create_link( $nt_obj, $q, $user);

    if ( $q->param('edit_sortorder') ) {
        $nt_obj->display_sort_options( $q, \@columns, \%labels, $cgi,
            ['nt_group_id'], $include_subgroups );
    };
    if ( $q->param('edit_search') ) {
        $nt_obj->display_advanced_search( $q, \@columns, \%labels, $cgi,
            ['nt_group_id'], $include_subgroups );
    };

    return $nt_obj->display_nice_error( $rv, "Get List of Groups" )
        if $rv->{'error_code'} != 200;

    my $groups = $rv->{'groups'};
    my $map    = $rv->{'group_map'};

    $nt_obj->display_search_rows( $q, $rv, \%params, $cgi, ['nt_group_id'], $include_subgroups );

    if (@$groups) {
        my $order = uc( $sort_fields{'group'}->{'mod'} ) eq 'ASCENDING' ? 'up' : 'down';
        my $sort = '';
        if ( $sort_fields{'group'} ) {
            $sort = qq[( $sort_fields{'group'}->{'order'} <img src=$NicToolClient::image_dir/$order.gif alt="$order"> )];
        };
        print qq[
<div id="groupListHeader" class="dark_bg center">Group $sort</div>
<div id="groupListDiv">];

        my $x = 0;

        foreach my $group (@$groups) {
            my $bgcolor = $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg';
            my $ggid = $group->{'nt_group_id'};
            my $gname = $group->{'name'} . "'s";
            my $dname = join( ' / ',
                map(qq[<a href="group.cgi?nt_group_id=$_->{'nt_group_id'}">$_->{'name'}</a>],
                    (   @{ $map->{ $ggid } },
                        {   nt_group_id => $ggid,
                            name        => $group->{'name'}
                        }
                        ) ) );
            print qq[
  <div class="$bgcolor"><img src=$NicToolClient::image_dir/group.gif alt="group">$dname
  <ul class="menu_r">];

            if ($user->{'group_delete'}
                && ( !exists $group->{'delegate_delete'} || $group->{'delegate_delete'} )
                ) {
                my $gid = $q->param('nt_group_id');
                my $hname = join( ' / ',
                        map( $_->{'name'},
                            (  @{ $map->{ $group->{'nt_group_id'} } },
                            {   nt_group_id => $group->{'nt_group_id'},
                                name        => $group->{'name'}
                            }
                            ) ) );
                print qq[
   <li class="center first">
    <a href="group.cgi?nt_group_id=$gid&amp;delete=$ggid" onClick="return confirm('Delete $hname and all associated data?');"><img src="$NicToolClient::image_dir/trash.gif" alt="trash"></a></li>];
            }
            else {
                print qq[
   <li class="center first"><img src="$NicToolClient::image_dir/trash-disabled.gif" alt=""></li>];
            }
            print qq[
   <li class="nowrap center side_pad2"><a href="group_log.cgi?nt_group_id=$ggid">
     <img src="$NicToolClient::image_dir/folder_closed.gif" alt="$gname log">Log</li>
   <li class="nowrap center side_pad2"><a href="group_users.cgi?nt_group_id=$ggid">
     <img src="$NicToolClient::image_dir/user.gif" alt="$gname users">Users</li>
   <li class="nowrap center side_pad2"><a href="group_nameservers.cgi?nt_group_id=$ggid">
     <img src="$NicToolClient::image_dir/nameserver.gif" alt="$gname nameservers">Nameservers</li>
   <li class="nowrap center side_pad2"><a href="group_zones.cgi?nt_group_id=$ggid">
     <img src="$NicToolClient::image_dir/zone.gif" alt="$gname zones">Zones</li>
  </ul>
 </div>];
        }

        print "
</div>";
    }
}

sub _display_group_create_link {
    my ($nt_obj, $q, $user) = @_;

    print qq[
<div class="dark_grey_bg margint4"><b>Sub-Group List</b><span class="float_r">];

    if ( ! $user->{'group_create'} ) {
        print qq[<span class=disabled>New Sub-Group</span></span></div>];
        return;
    };

    my $state = 'nt_group_id=' . $q->param('nt_group_id')
                . '&amp;parent_group_id=' . $q->param('nt_group_id');

    foreach ( @{ $nt_obj->paging_fields } ) {
        next if ! $q->param($_);
        $state .= "&amp;$_=" . $q->escape( $q->param($_) );
    }
    print qq[<a href="group.cgi?$state&amp;new=1">New Sub-Group</a></span></div>];
};

sub display_edit {
    my ( $nt_obj, $user, $q, $edit ) = @_;
    my $showpermissions = 1;
    my $data            = {};
    my %param = ();

    if ( $edit eq 'edit' ) {
        my $rv = $nt_obj->get_group( nt_group_id => $q->param('nt_group_id') );

        return $nt_obj->display_nice_error( $rv, "Get Group Details" )
            if $rv->{'error_code'} != 200;
        $data = $rv;

        if ( $q->param('nt_group_id') eq $user->{'nt_group_id'} ) {
            %param = ( nt_group_id => $data->{'parent_group_id'} );
        };
    }
    else {
        if ( $q->param('nt_group_id') eq $user->{'nt_group_id'} ) {
            %param = ( nt_group_id => $q->param('nt_group_id') );
        };
    }

    my $modifyperm = $user->{ 'group_' . ( $edit eq 'edit' ? 'write' : 'create' ) };

    if ($modifyperm) {
        print $q->start_form(
            -action => 'group.cgi',
            -method => 'POST',
            -name   => 'perms_form'
        ),
        $q->hidden( -name => $edit );
        if ( $edit eq 'new' ) {
            $q->hidden( -name => 'parent_group_id' );
        };
        print $q->hidden( -name => 'nt_group_id' );
        foreach ( @{ $nt_obj->paging_fields } ) {
            next if ! $q->param($_);
            print $q->hidden( -name => $_ );
        }
    }

    my $action = 'View';
    my $name = qq[<b>$data->{'name'}</b>];

    if ( $modifyperm ) {
        $action = ucfirst($edit);
        $name = $q->textfield( -name => 'name', -size => '40', -default => $data->{'name'} );
    };

    print qq[
<table class="fat">
 <tr class=dark_bg><td colspan=2 class="bold">$action Sub-Group</td></tr>
 <tr class="light_grey_bg">
  <td class="right">Name:</td>
  <td class="fat">$name </td>
 </tr>];

    my $ns_tree = $nt_obj->get_usable_nameservers(%param);
    my %nsmap = map { $_ => 1 } split(',', $data->{'usable_ns'});

    #show nameservers
    print qq[
 <tr class=dark_grey_bg>
  <td colspan=2> Allow users of this group to publish zones changes to the following nameservers: </td>
 </tr>
 <tr class=light_grey_bg>
  <td class="light_grey_bg top"> Nameservers: </td>
  <td class="light_grey_bg top"> ];

    foreach ( 1 .. scalar( @{ $ns_tree->{'nameservers'} } ) ) {

        my $ns = $ns_tree->{'nameservers'}->[ $_ - 1 ];
        print $q->checkbox(
            -name    => "usable_nameservers",
            -checked => $nsmap{ $ns->{'nt_nameserver_id'} } ? 1 : 0,
            -value   => $ns->{'nt_nameserver_id'},
            -label   => "$ns->{'description'} ($ns->{'name'})"
            ),
            "<BR>";
        delete $nsmap{ $ns->{'nt_nameserver_id'} };
    }
    if ( @{ $ns_tree->{'nameservers'} } == 0 ) {
        print "No available nameservers." . $nt_obj->help_link('nonsavail');
    }

    foreach ( keys %nsmap ) {
        my $ns = $nt_obj->get_nameserver( nt_nameserver_id => $_ );
        print "<li>$ns->{'description'} ($ns->{'name'})<BR>";
    }

    print qq[
  </td>
 </tr>];

    if ($showpermissions) {

        my %perms = (
            group      => [qw(write create delete . )],
            user       => [qw(write create delete .)],
            zone       => [qw(write create delete delegate )],
            zonerecord => [qw(write create delete delegate)],
            nameserver => [qw(write create delete .)],
            self       => [qw(write . . .)]
        );
        my %labels = (
            group      => { 'write' => 'Edit' },
            user       => { 'write' => 'Edit' },
            zone       => { 'write' => 'Edit' },
            zonerecord => { 'write' => 'Edit' },
            nameserver => { 'write' => 'Edit' },
            self       => { 'write' => 'Edit' },
        );

        print "
 <tr class=dark_grey_bg>
  <td colspan=2>"
            . (
            $modifyperm
            ? "By default, allow users of this group to have these permissions"
            : "Users of this group have these permissions"
            )
            . $nt_obj->help_link('perms')
            . ":</td>
 </tr>";

        print qq[
 <tr class=light_grey_bg>
  <td colspan=2 class=light_grey_bg>
   <table class="center" style="padding:6; border-spacing:1;"> ];

        my @order = qw/ group user zone zonerecord nameserver self header /;
        my $x     = 1;
        my $color;
        foreach my $type (@order) {
            if ( $type eq 'header' ) {
                print qq[
    <tr>
     <td></td>
                ];
                foreach (qw(Edit Create Delete Delegate All)) {
                    print qq[
     <td>];
                    print $q->checkbox(
                        -name  => "select_all_$_",
                        -label => '',
                        -onClick => "selectAll$_(document.perms_form, this.checked);",
                        -override => 1
                    );
                    print qq[</td>];
                }
                print qq[
    </tr>];
            }
            else {
                $color = ( $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg' );
                print qq{
    <tr>
     <td class=right><b>} . ( ucfirst($type) ) . qq[:</b></td> ];
                foreach my $perm ( @{ $perms{$type} } ) {
                    if ( $perm eq '.' ) {
                        print qq[
     <td></td>];
                    }
                    elsif ( $user->{ $type . "_" . $perm } ) {
                        print qq[
     <td class="middle left $color">];

                        print $q->checkbox(
                            -name    => $type . "_" . $perm,
                            -value   => '1',
                            -checked => $data->{ $type . "_" . $perm },
                            -label   => ''
                            ),
                            (
                            exists $labels{$type}->{$perm}
                            ? $labels{$type}->{$perm}
                            : ucfirst($perm) ),
                            qq[</td> ];
                    }
                    else {
                        print qq[
     <td class="middle left $color"><img src="$NicToolClient::image_dir/perm-]
                            . ( $data->{ $type . "_" . $perm } ? 'checked' : 'unchecked' )
                            . qq{.gif" alt="">}
                            . ( $modifyperm ? "<span class=disabled>" : '') 
                            . ( exists $labels{$type}->{$perm} ? $labels{$type}->{$perm} : ucfirst($perm) )
                            . ( $modifyperm ? '</span>' : '' )
                            . qq{</td> };
                    }
                }
                print qq[<td>],
                    $q->checkbox(
                            -name    => "select_all_$type",
                            -label   => '',
                            -onClick => "selectAll"
                            . ucfirst($type)
                            . "(document.perms_form, this.checked);",
                            -override => 1
                        ),
                        qq[</td>
    </tr> ];
            }
        }
        print qq[
   </table>
  </td>
 </tr>];
    }

    if ($modifyperm) {
        print qq[
 <tr class=dark_grey_bg>
  <td class=center colspan=2>],
            $q->submit( $edit eq 'edit' ? 'Save' : 'Create' ),
            $q->submit('Cancel'), "
  </td>
 </tr>";
    }
    print qq[
</table>];

    print $q->end_form;
}

