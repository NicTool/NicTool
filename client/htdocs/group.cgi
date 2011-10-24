#!/usr/bin/perl
#
# $Id: group.cgi 1043 2010-03-26 00:52:03Z matt $
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

    my $error;

    my @fields
        = qw(user_create user_delete user_write group_create group_delete group_write zone_create zone_delegate zone_delete zone_write zonerecord_create zonerecord_delegate zonerecord_delete zonerecord_write nameserver_create nameserver_delete nameserver_write self_write);
    if ( $q->param('new') && $q->param('Create') ) {
        my %params = (
            nt_group_id => $q->param('nt_group_id'),
            name        => $q->param('name')
        );
        my @ns = $q->param("usable_nameservers");
        if ( @ns < 11 ) {
            $params{"usable_nameservers"} = join( ",", @ns );
            foreach (@fields) {
                $params{$_} = $q->param($_) ? 1 : 0;
            }

#$error = $nt_obj->new_group( nt_group_id => $q->param('parent_group_id'), name => $q->param('name')  );
            $error = $nt_obj->new_group(%params);
        }
        else {
            $error = {
                error_code => 'xxx',
                error_msg  => 'Please select up to 10 nameservers.'
            };
        }

    }
    elsif ( $q->param('edit') && $q->param('Save') ) {
        my %params = (
            nt_group_id => $q->param('nt_group_id'),
            name        => $q->param('name')
        );
        my @ns = $q->param("usable_nameservers");
        if ( @ns < 11 ) {
            $params{"usable_nameservers"} = join( ",", @ns );
            foreach (@fields) {
                $params{$_} = $q->param($_) ? 1 : 0;

                #warn "$_ = '".$params{$_}."'";
            }

#$error = $nt_obj->edit_group( nt_group_id => $q->param('edit'), name => $q->param('name')  );
            $error = $nt_obj->edit_group(%params);
        }
        else {
            $error = {
                error_code => 'xxx',
                error_msg  => 'Please select up to 10 nameservers.'
            };
        }
    }

    $nt_obj->display_group_tree(
        $user,
        $user->{'nt_group_id'},
        $q->param('nt_group_id'), 1
    );

    if ( $q->param('edit') ) {
        if ( $q->param('Save') ) {
            if ( $error->{'error_code'} != 200 ) {
                $nt_obj->display_nice_error( $error, "Edit Group" );
                &display_edit( $nt_obj, $user, $q, "edit" );
            }
            else {
                $nt_obj->refresh_nav();
            }
        }
        elsif ( $q->param('Cancel') ) {

        }
        else {
            &display_edit( $nt_obj, $user, $q, "edit" );
        }
    }
    elsif ( $q->param('new') ) {
        if ( $q->param('Create') ) {
            if ( $error->{'error_code'} != 200 ) {
                $nt_obj->display_nice_error( $error, "New Group" );
                &display_edit( $nt_obj, $user, $q, "new" );
            }
            else {
                $nt_obj->refresh_nav();
            }
        }
        elsif ( $q->param('Cancel') ) {

        }
        else {
            &display_edit( $nt_obj, $user, $q, "new" );
        }
    }

    if ( $q->param('delete') ) {
        my $rv = $nt_obj->delete_group( nt_group_id => $q->param('delete') );
        $nt_obj->display_nice_error( $rv, "Delete Group" )
            if ( $rv->{'error_code'} != 200 );
        $nt_obj->refresh_nav();
    }

    my $group = $nt_obj->get_group( nt_group_id  => $q->param('nt_group_id') );

    #&display_zone_search($nt_obj, $q, $group);
    #$nt_obj->display_hr();

    &display_group_list( $nt_obj, $q, $group, $user );

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub display_zone_search {
    my ( $nt_obj, $q, $group ) = @_;

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print
        "<tr bgcolor=$NicToolClient::dark_grey><td><table cellpadding=0 cellspacing=0 border=0 width=100%>";
    print "<tr>";
    print $q->startform( -action => 'group.cgi', -method => 'POST' );
    print $q->hidden( -name => 'nt_group_id' );
    print "<td>";
    print $q->textfield( -name => 'search_value', -size => 30,
        -override => 1 );
    print $q->hidden(
        -name     => 'quick_search',
        -value    => 'Enter',
        -override => 1
    );
    print $q->submit( -name => 'quick_search', -value => 'Search Zones' );
    print " &nbsp; &nbsp;",
        $q->checkbox(
        -name     => 'include_subgroups',
        -value    => 1,
        -label    => 'include sub-groups',
        -override => 1
        ) if $group->{'has_children'};
    print "</td>";
    print $q->endform;
    print "</tr>"
        . "</table></td></tr>"
        . "</table>";
}

sub display_group_list {
    my ( $nt_obj, $q, $group, $user ) = @_;

    my @columns = qw(group);
    my $cgi = 'group.cgi';

    my %labels = (
        group      => 'Group',
        sub_groups => '*Sub Groups',
    );

    my $include_subgroups = $group->{'has_children'} ? 'sub-groups' : undef;

    my %params = (
        nt_group_id =>
            ( $q->param('nt_group_id') ? $q->param('nt_group_id') : '' ),
        start_group_id =>
            ( $q->param('nt_group_id') ? $q->param('nt_group_id') : '' )
    );
    my %sort_fields;
    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields,
        10 );

    $sort_fields{'group'} = { 'order' => 1, 'mod' => 'Ascending' }
        unless %sort_fields;
    my $rv = $nt_obj->get_group_subgroups(%params);

    $nt_obj->display_sort_options( $q, \@columns, \%labels, $cgi,
        ['nt_group_id'], $include_subgroups )
        if $q->param('edit_sortorder');
    $nt_obj->display_advanced_search( $q, \@columns, \%labels, $cgi,
        ['nt_group_id'], $include_subgroups )
        if $q->param('edit_search');

    return $nt_obj->display_nice_error( $rv, "Get List of Groups" )
        if ( $rv->{'error_code'} != 200 );

    my $groups = $rv->{'groups'};
    my $map    = $rv->{'group_map'};

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

    my @options;
    if ( $user->{'group_create'} ) {
        @options
            = (   "<a href=group.cgi?"
                . join( '&', @state_fields )
                . "&nt_group_id="
                . $q->param('nt_group_id')
                . "&parent_group_id="
                . $q->param('nt_group_id')
                . "&new=1>New Sub-Group</a>" );
    }
    else {

        #warn "user group_create is ".$user->{'group_create'};
        @options
            = (
            "<font color=$NicToolClient::disabled_color>New Sub-Group</font>"
            );
    }

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>"
        . "<tr bgcolor=$NicToolClient::dark_grey><td>"
        . "<table cellpadding=0 cellspacing=0 border=0 width=100%>"
        . "<tr>"
        . "<td><b>Sub-Group List</b></td>"
        . "<td align=right>", join( ' | ', @options ), "</td>"
        . "</tr></table></td></tr>"
        . "</table>";

    $nt_obj->display_search_rows( $q, $rv, \%params, $cgi, ['nt_group_id'],
        $include_subgroups );

    if (@$groups) {
        print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
        print "<tr bgcolor=$NicToolClient::dark_grey>";
        foreach (@columns) {
            if ( $sort_fields{$_} ) {
                print "<td bgcolor=$NicToolClient::dark_color align=center>"
                    . "<table cellpadding=0 cellspacing=0 border=0>"
                    . "<tr>"
                    . "<td><font color=white>$labels{$_}</font></td>"
                    . "<td>&nbsp; &nbsp; $NicToolClient::font<font color=white>",
                    $sort_fields{$_}->{'order'}, "</font></font></td>"
                    . "<td><img src=$NicToolClient::image_dir/",
                    ( uc( $sort_fields{$_}->{'mod'} ) eq 'ASCENDING'
                        ? 'up.gif'
                        : 'down.gif' ), "></tD>"
                    . "</tr></table></td>";

            }
            else {
                print "<td align=center>", "$labels{$_}</td>";
            }
        }
        for (qw(Zones Nameservers Users Log)) {
            print "<td align=center>", $_, "</td>";
        }
        print "<td align=center><img src=$NicToolClient::image_dir/trash.gif></td>"
            . "</tr>";

        my $x = 0;

        foreach my $group (@$groups) {
            print "<tr bgcolor="
                . ( $x++ % 2 == 0 ? $NicToolClient::light_grey : 'white' )
                . ">";

            print
                "<td width=100%><table cellpadding=0 cellspacing=0 border=0><tr>"
                . "<td><img src=$NicToolClient::image_dir/group.gif></td>"
                . "<td>",
                join(
                ' / ',
                map("<a href=group.cgi?nt_group_id=$_->{'nt_group_id'}>$_->{'name'}</a>",
                    (   @{ $map->{ $group->{'nt_group_id'} } },
                        {   nt_group_id => $group->{'nt_group_id'},
                            name        => $group->{'name'}
                        }
                        ) )
                ),
                "</td>"
                . "</tr></table></td>";

            for (qw(zones nameservers users log)) {
                print "<td align=center width=1%>"
                    . "<table cellpadding=0 cellspacing=0 border=0><tr>"
                    . "<td><img src=$NicToolClient::image_dir/transparent.gif width=2 height=16></td>"
                    . "<td><a href=group_$_.cgi?nt_group_id=$group->{'nt_group_id'}>"
                    . "<img src=$NicToolClient::image_dir/folder_closed.gif border=0 alt=\"$group->{'name'}'s $_\"></a></td>";
                print "<td><a href=group_$_.cgi?nt_group_id=$group->{'nt_group_id'}>"
                    . ucfirst($_)
                    . "</a></td>"
                    .  "<td><img src=$NicToolClient::image_dir/transparent.gif width=2 height=16></td>"
                    . "</tr></table></td>";
            }
            if ($user->{'group_delete'}
                && ( !exists $group->{'delegate_delete'}
                    || $group->{'delegate_delete'} )
                )
            {
                print "<td align=center><a href=\"group.cgi?nt_group_id="
                    . $q->param('nt_group_id')
                    . "&delete=$group->{'nt_group_id'}\" onClick=\"return confirm('Delete ",
                    join(
                    ' / ',
                    map( $_->{'name'},
                        (   @{ $map->{ $group->{'nt_group_id'} } },
                            {   nt_group_id => $group->{'nt_group_id'},
                                name        => $group->{'name'}
                            }
                            ) )
                    ),
                    " and all associated data?');\"><img src=$NicToolClient::image_dir/trash.gif border=0></a></td>";
            }
            else {
                print
                    "<td align=center><img src=$NicToolClient::image_dir/trash-disabled.gif border=0></td>";
            }
            print "</tr>";
        }

        print "</table>";
    }

    print $q->endform;
}

sub display_edit {
    my ( $nt_obj, $user, $q, $edit ) = @_;
    my $showpermissions = 1;
    my $data            = {};
    my @param;
    if ( $edit eq 'edit' ) {
        my $rv = $nt_obj->get_group( nt_group_id => $q->param('nt_group_id') );
        return $nt_obj->display_nice_error( $rv, "Get Group Details" )
            if ( $rv->{'error_code'} != 200 );
        $data = $rv;

        @param
            = $q->param('nt_group_id') eq $user->{'nt_group_id'}
            ? ()
            : (
            nt_group_id      => $data->{'parent_group_id'},
            include_for_user => 1
            );
    }
    else {
        @param
            = $q->param('nt_group_id') eq $user->{'nt_group_id'}
            ? ()
            : (
            nt_group_id      => $q->param('nt_group_id'),
            include_for_user => 1
            );

    }

    #warn "group is ".Data::Dumper::Dumper($data);
    my $modifyperm
        = $user->{ 'group_' . ( $edit eq 'edit' ? 'write' : 'create' ) };

    if ($modifyperm) {
        $nt_obj->display_perms_javascript;
        print $q->start_form(
            -action => 'group.cgi',
            -method => 'POST',
            -name   => 'perms_form'
        );

        print $q->hidden( -name => $edit );
        print $q->hidden( -name => 'parent_group_id' ) if $edit eq 'new';
        print $q->hidden( -name => 'nt_group_id' );
        foreach ( @{ $nt_obj->paging_fields } ) {
            print $q->hidden( -name => $_ ) if ( $q->param($_) );
        }
    }

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";

    print
        "<tr bgcolor=$NicToolClient::dark_color><td colspan=2>$NicToolClient::font<font color=white><b>",
        ( $modifyperm ? ucfirst($edit) : 'View' ),
        " Sub-Group</b></font></font></td></tr>";
    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Name:</td>";
    print "<td width=100%>$NicToolClient::font";
    if ($modifyperm) {
        print $q->textfield(
            -name    => 'name',
            -size    => '40',
            -default => $data->{'name'}
        );
    }
    else {
        print "<b>" . $data->{'name'} . "</b>";
    }
    print "</font></td>";
    print "</tr>";
    my $ns_tree = $nt_obj->get_usable_nameservers(@param);
    my %nsmap = map { $data->{"usable_ns$_"} => 1 }
        grep { $data->{"usable_ns$_"} != 0 } ( 0 .. 9 );

    #warn "ns_tree ".Data::Dumper::Dumper($ns_tree);
    #warn "data ".Data::Dumper::Dumper($data);
    #warn "params ".join(",",@param);

    #show nameservers
    print qq(
        <tr bgcolor=$NicToolClient::dark_grey>
            <td colspan=2> Allow users of this group to publish zones changes to the following nameservers: </td>
        </tr>
         <tr bgcolor=$NicToolClient::light_grey>
            <td  bgcolor=$NicToolClient::light_grey valign=top> Nameservers: </td>
            <td  bgcolor=$NicToolClient::light_grey valign=top>$NicToolClient::font
                      );

    foreach ( 1 .. scalar( @{ $ns_tree->{'nameservers'} } ) ) {

        #last if ($_ > 10);
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

    print qq(
                </font>
            </td>
        </tr>
    );

    if ($showpermissions) {
        print
            "<tr bgcolor=$NicToolClient::dark_grey><td colspan=2>$NicToolClient::font"
            . (
            $modifyperm
            ? "By default, allow users of this group to have these permissions"
            : "Users of this group have these permissions"
            )
            . $nt_obj->help_link('perms')
            . ":</font></td></tr>";

        print qq{
        <tr bgcolor=$NicToolClient::light_grey>
            <td colspan=2 bgcolor=$NicToolClient::light_grey>
                <table cellpadding=6 cellspacing=1 border=0 align=center>
                    };

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

        my @order = qw(group user zone zonerecord nameserver self header);
        my $x     = 1;
        my $color;
        foreach my $type (@order) {
            if ( $type eq 'header' ) {
                print qq(
                    <tr><td></td>
                );
                foreach (qw(Edit Create Delete Delegate All)) {
                    print "<td>$NicToolClient::font";
                    print $q->checkbox(
                        -name  => "select_all_$_",
                        -label => '',
                        -onClick =>
                            "selectAll$_(document.perms_form, this.checked);",
                        -override => 1
                    );
                    print "</font></td>";
                }
                print qq(
                    </tr>
                );
            }
            else {
                $color = (
                    $x++ % 2 == 0 ? $NicToolClient::light_grey : 'white' );
                print qq{
                        <tr>
                            <td align=right>$NicToolClient::font<b>}
                    . ( ucfirst($type) ) . qq{:</b></font></td>
                                };
                foreach my $perm ( @{ $perms{$type} } ) {
                    if ( $perm eq '.' ) {
                        print qq(
                            <td></td>
                        );
                    }
                    elsif ( $user->{ $type . "_" . $perm } ) {
                        print qq{
                            <td valign=center align=left bgcolor=$color>$NicToolClient::font
                            };
                        print $q->checkbox(
                            -name    => $type . "_" . $perm,
                            -value   => '1',
                            -checked => $data->{ $type . "_" . $perm },
                            -label   => ''
                            )
                            . (
                            exists $labels{$type}->{$perm}
                            ? $labels{$type}->{$perm}
                            : ucfirst($perm) )
                            . qq{</font></td> };
                    }
                    else {
                        print qq{
                            <td valign=center align=left bgcolor=$color>$NicToolClient::font<img src=$NicToolClient::image_dir/perm-}
                            . ( $data->{ $type . "_" . $perm } ? 'checked.gif'
                            : 'unchecked.gif' )
                            . qq{>}
                            . (
                            $modifyperm
                            ? "<font color=$NicToolClient::disabled_color>"
                            : ''
                            )
                            . (
                            exists $labels{$type}->{$perm}
                            ? $labels{$type}->{$perm}
                            : ucfirst($perm) )
                            . ( $modifyperm ? '</font>' : '' )
                            . qq{</font></td> };
                    }
                }
                print "<td>$NicToolClient::font"
                    . $q->checkbox(
                    -name    => "select_all_$type",
                    -label   => '',
                    -onClick => "selectAll"
                        . ucfirst($type)
                        . "(document.perms_form, this.checked);",
                    -override => 1
                    ) . "</font></td>";
                print qq{
                        </tr>
                        };
            }
        }
        print qq{
                </table>
            </td>
        </tr>
        };
    }

    if ($modifyperm) {
        print
            "<tr bgcolor=$NicToolClient::dark_grey><td align=center colspan=2>",
            $q->submit( $edit eq 'edit' ? 'Save' : 'Create' ),
            $q->submit('Cancel'), "</td></tr>";
    }
    print "</table>";

    print $q->endform;
}

