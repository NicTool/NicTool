#!/usr/bin/perl
#
# $Id: user.cgi 635 2008-09-13 04:03:07Z matt $
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
        groupname => $user->{'groupname'},
        userid    => $user->{'nt_user_id'}
    );

    my $duser = $nt_obj->get_user( nt_user_id => $q->param('nt_user_id') );
    if ( $duser->{'error_code'} ne 200 ) {
        print $nt_obj->display_error($duser);
    }

    #warn "user info: ".Data::Dumper::Dumper($user);
    my $edit_message;
    my @fields
        = qw(user_create user_delete user_write group_create group_delete group_write zone_create zone_delegate zone_delete zone_write zonerecord_create zonerecord_delegate zonerecord_delete zonerecord_write nameserver_create nameserver_delete nameserver_write self_write);

    if ( $q->param('edit') ) {
        if ( $q->param('Save') ) {
            my %data;
            my @ns;
            foreach (
                qw(nt_user_id username first_name last_name email password password2 current_password)
                )
            {
                $data{$_} = $q->param($_);
            }

            #warn "group_defaults is ".$q->param('group_defaults');
            if ( $q->param('group_defaults') eq '0' ) {
                @ns = $q->param("usable_nameservers");
                $data{"usable_nameservers"} = join( ",", @ns )
                    if $q->param("usable_nameservers");
                foreach (@fields) {
                    $data{$_} = $q->param($_) ? 1 : 0;
                }
            }
            else {
                $data{'inherit_group_permissions'} = 1;
            }
            my $error;
            if ( @ns < 11 ) {

                #warn "editing user: ".Data::Dumper::Dumper(\%data);
                $error = $nt_obj->edit_user(%data);
            }
            else {
                $error = {
                    error_code    => 'xxx',
                    error_message => 'Please select up to 10 nameservers'
                };
            }

            #warn "error = $error\n";
            if ( $error->{'error_code'} != 200 ) {
                $edit_message = $error;
            }
            else {
                $duser = $nt_obj->get_user(
                    nt_user_id => $q->param('nt_user_id') );
            }
        }
    }
    if ( $q->param('new') ) {
        if ( $q->param('Create') ) {
            my %data;
            my @ns;
            foreach (
                qw(nt_group_id username first_name last_name email password password2 )
                )
            {
                $data{$_} = $q->param($_);
            }
            if ( $q->param('group_defaults') eq '0' ) {
                @ns = $q->param("usable_nameservers");
                $data{"usable_nameservers"} = join( ",", @ns )
                    if $q->param("usable_nameservers");
                foreach (@fields) {
                    $data{$_} = $q->param($_) ? 1 : 0;
                }
            }
            else {
                $data{'inherit_group_permissions'} = 1;
            }
            my $error;
            if ( @ns or @ns < 11 ) {
                $error = $nt_obj->new_user(%data);
            }
            else {
                $error = {
                    error_code    => 'xxx',
                    error_message => 'Please select up to 10 nameservers'
                };
            }

            #warn "error = ".Data::Dumper::Dumper($error);
            if ( $error->{'error_code'} != 200 ) {
                $edit_message = $error;
            }
            else {

#$duser = $nt_obj->get_user( nt_group_id => $q->param('nt_group_id'), nt_user_id => $q->param('nt_user_id') );
            }
        }
    }

    $q->param( 'nt_group_id', $duser->{'nt_group_id'} );

    my $level = $nt_obj->display_group_tree(
        $user,
        $user->{'nt_group_id'},
        $q->param('nt_group_id'), 0
    );
    $nt_obj->display_user_list_options( $user, $q->param('nt_group_id'),
        $level, 0 );

    $level++;

    my $group = $nt_obj->get_group(
        nt_group_id  => $user->{'nt_group_id'},
        summary_data => 1
    );

    my @options;
    if ( $user->{'user_delete'}
        && ( $user->{'nt_user_id'} ne $duser->{'nt_user_id'} ) )
    {
        push( @options,
                  "<a href=group_users.cgi?nt_group_id="
                . $q->param('nt_group_id')
                . "&delete=1&obj_list=$duser->{'nt_user_id'} onClick=\"return confirm('Delete user $duser->{'username'}?');\">Delete</a>"
        );
    }
    else {
        push( @options,
            "<font color=$NicToolClient::disabled_color>Delete</font>" );
    }
    if (   $user->{'user_write'}
        && $user->{'nt_user_id'} ne $duser->{'nt_user_id'} )
    {
        push( @options,
            "<a href=\"javascript:void window.open('move_users.cgi?obj_list=$duser->{'nt_user_id'}', 'move_win', 'width=640,height=480,scrollbars,resizable=yes')\">Move</a>"
        ) if ( $group->{'has_children'} );
    }
    else {
        push( @options,
            "<font color=$NicToolClient::disabled_color>Move</font>" )
            if ( $group->{'has_children'} );
    }

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

    print "<td><img src=$NicToolClient::image_dir/user.gif></td>";
    print "<td nowrap><b>$duser->{'username'}</b></td>";
    print "<td align=right width=100%>", join( ' | ', @options ), "</td>";
    print "</tr></table>";
    print "</td></tr></table>";

    &display_properties( $nt_obj, $q, $user, $duser, $edit_message );
    &display_global_log( $nt_obj, $q, $user, $duser, $message );

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub display_properties {
    my ( $nt_obj, $q, $user, $duser, $message ) = @_;

    my $modifyperm
        = ( $user->{'user_write'}
            && ( $duser->{'nt_user_id'} ne $user->{'nt_user_id'} ) )
        || ( $user->{'self_write'}
        && ( $duser->{'nt_user_id'} eq $user->{'nt_user_id'} ) );
    if ( $q->param('new') ) {
        if ( $q->param('Create') ) {
            if ($message) {
                &display_edit( $nt_obj, $q, $message, $user, $duser, 'new' );
            }
        }
        elsif ( $q->param('Cancel') ) {

        }
        else {
            &display_edit( $nt_obj, $q, '', $user, $duser, 'new' );
        }
    }
    elsif ( $q->param('edit') ) {
        if ( $q->param('Save') ) {
            if ($message) {
                &display_edit( $nt_obj, $q, $message, $user, $duser, 'edit' );
            }
        }
        elsif ( $q->param('Cancel') ) {

        }
        else {
            &display_edit( $nt_obj, $q, '', $user, $duser, 'edit' );
        }
    }

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print
        "<tr bgcolor=$NicToolClient::dark_grey><td><table cellpadding=0 cellspacing=0 border=0 width=100%>";
    print "<tr>";
    print "<td><b>Properties</b></td>";
    my $modname;
    if ($modifyperm) {
        $modname = "Edit";
    }
    else {
        $modname = 'View Details';
    }
    print "<td align=right><a href=user.cgi?", join( '&', @state_fields ),
          "&nt_group_id="
        . $q->param('nt_group_id')
        . "&nt_user_id=$duser->{'nt_user_id'}&edit=1>$modname</a></td>";
    print "</tr></table>";
    print "</td></tr></table>";

    print "<table cellpadding=2 cellspacing=0 border=0 width=100%>";
    print "<tr>";
    print "<td width=50%>";
    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td nowrap>", "Username: </td>";
    print "<td width=100%>",
        ( $duser->{'username'} ? $duser->{'username'} : '&nbsp;' ), "</td>";
    print "</tr>";
    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td nowrap>", "Email: </td>";
    print "<td width=100%>",
        ( $duser->{'email'} ? $duser->{'email'} : '&nbsp;' ), "</td>";
    print "</tr>";
    print "</table>";
    print "</td><td width=50%>";
    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td nowrap>", "First Name: </td>";
    print "<td width=100%>",
        ( $duser->{'first_name'} ? $duser->{'first_name'} : '&nbsp;' ),
        "</td>";
    print "</tr>";
    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td nowrap>", "Last Name: </td>";
    print "<td width=100%>",
        ( $duser->{'last_name'} ? $duser->{'last_name'} : '&nbsp;' ), "</td>";
    print "</tr>";

    print "</table>";
    print "</td></tr></table>";

    return $duser;
}

sub display_global_log {
    my ( $nt_obj, $q, $user, $duser, $message ) = @_;

    my @columns = qw(timestamp action object title target description);

    my %labels = (
        timestamp   => 'Date',
        action      => 'Action',
        object      => 'Object',
        title       => 'Name',
        target      => 'Target',
        description => 'Description',
    );

    my $cgi        = 'user.cgi';
    my @req_fields = qw(nt_group_id nt_user_id);

    $nt_obj->display_sort_options( $q, \@columns, \%labels, $cgi,
        \@req_fields )
        if $q->param('edit_sortorder');
    $nt_obj->display_advanced_search( $q, \@columns, \%labels, $cgi,
        \@req_fields )
        if $q->param('edit_search');

    my %params = ( map { $_ => $q->param($_) } @req_fields );
    my %sort_fields;
    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields,
        20 );

    $sort_fields{'timestamp'} = { 'order' => 1, 'mod' => 'Descending' }
        unless %sort_fields;

    my $rv = $nt_obj->get_user_global_log(%params);
    return $nt_obj->display_error($rv) if ( $rv->{'error_code'} != '200' );

    my $list = $rv->{'list'};

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print "<tr><td><hr></td></tr>";

#print "<tr><td align=center><font color=red>$message</font></td></tr>" if( $message );
    $nt_obj->display_nice_error($message) if $message;
    print "<tr bgcolor=$NicToolClient::dark_grey><td>";
    print "<table cellpadding=0 cellspacing=0 border=0 width=100%>";
    print "<tr>";
    print "<td><b>Global Application Log</b></td>";
    print "</tr></table></td></tr>";
    print "</table>";

    $nt_obj->display_search_rows( $q, $rv, \%params, $cgi, \@req_fields );

    if (@$list) {
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

        my $x = 0;
        my $range;
        foreach my $row (@$list) {

            print "<tr bgcolor="
                . ( $x++ % 2 == 0 ? $NicToolClient::light_grey : 'white' )
                . ">";
            foreach (@columns) {
                if ( $_ eq 'timestamp' ) {
                    print "<td>", ( scalar localtime( $row->{$_} ) ), "</td>";
                }
                elsif ( $_ eq 'object' ) {
                    my $txt = $row->{'object'};
                    $txt = join( " ", map( ucfirst, split( /_/, $txt ) ) );
                    print "<td>", ( $txt ? $txt : '&nbsp;' ), "</td>";

                }
                elsif ( $_ eq 'title' ) {
                    print
                        "<td><table cellpadding=0 cellspacing=0 border=0><tr>";
                    print "<td><a href=user.cgi?"
                        . join( '&', @state_fields )
                        . "&redirect=1&nt_group_id=$duser->{'nt_group_id'}&nt_user_id=$duser->{'nt_user_id'}&object="
                        . $q->escape( $row->{'object'} )
                        . "&obj_id="
                        . $q->escape( $row->{'object_id'} )
                        . "><img src=$NicToolClient::image_dir/$map->{ $row->{'object'} }->{'image'} border=0></a></td>";
                    print "<td><a href=user.cgi?"
                        . join( '&', @state_fields )
                        . "&redirect=1&nt_group_id=$duser->{'nt_group_id'}&nt_user_id=$duser->{'nt_user_id'}&object="
                        . $q->escape( $row->{'object'} )
                        . "&obj_id="
                        . $q->escape( $row->{'object_id'} )
                        . ">$row->{'title'}</a></td>";
                    print "</tr></table></td>";
                }
                elsif ( $_ eq 'target' && $row->{'target_id'} ) {
                    print
                        "<td><table cellpadding=0 cellspacing=0 border=0><tr>";
                    print "<td><a href=user.cgi?"
                        . join( '&', @state_fields )
                        . "&redirect=1&nt_group_id=$duser->{'nt_group_id'}&nt_user_id=$duser->{'nt_user_id'}&object="
                        . $q->escape( $row->{'target'} )
                        . "&obj_id="
                        . $q->escape( $row->{'target_id'} )
                        . "><img src=$NicToolClient::image_dir/$map->{ $row->{'target'} }->{'image'} border=0></a></td>";
                    print "<td><a href=user.cgi?"
                        . join( '&', @state_fields )
                        . "&redirect=1&nt_group_id=$duser->{'nt_group_id'}&nt_user_id=$duser->{'nt_user_id'}&object="
                        . $q->escape( $row->{'target'} )
                        . "&obj_id="
                        . $q->escape( $row->{'target_id'} )
                        . ">$row->{'target_name'}</a></td>";
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

sub display_edit {
    my ( $nt_obj, $q, $message, $user, $duser, $edit ) = @_;

    my $showpermissions = 1;
    my $showusablens    = 0;
    my $modifyperm;
    my $editself = $user->{'nt_user_id'} eq $duser->{'nt_user_id'};
    if ( $edit eq 'new' ) {
        $modifyperm = $user->{'user_create'};
    }
    else {
        $modifyperm = ( $user->{'user_write'} && !$editself )
            || ( $user->{'self_write'} && $editself );
    }
    my $permmodify = !$editself && $user->{'user_write'};

    #warn "user hash: ".Data::Dumper::Dumper($duser);
    if ($modifyperm) {
        $nt_obj->display_perms_javascript;
        print $q->start_form(
            -action => 'user.cgi',
            -method => 'POST',
            -name   => 'perms_form'
        );
        print $q->hidden( -name => 'nt_group_id' );
        print $q->hidden( -name => 'nt_user_id' ) if $edit eq 'edit';
        print $q->hidden( -name => $edit );

        foreach ( @{ $nt_obj->paging_fields() } ) {
            print $q->hidden( -name => $_ ) if ( $q->param($_) );
        }
    }
    my $modname = $modifyperm ? 'Edit Properties' : 'View Details';

 #print "<center><font color=red><b>$message</b></font></center>" if $message;
    $nt_obj->display_nice_error( $message, ucfirst($edit) . " User" )
        if $message;

    print "<a name='ZONE'>";
    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print
        "<tr bgcolor=$NicToolClient::dark_color><td colspan=2><font color=white><b>$modname</b></font></td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right nowrap>", "Username:</td>";
    print "<td width=100%>",
        (
        $modifyperm
        ? $q->textfield(
            -name  => 'username',
            -value => $duser->{'username'},
            -size  => 30
            )
        : $duser->{'username'}
        ),
        "</td>";
    print "</tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right nowrap>", "First Name:</td>";
    print "<td width=100%>",
        (
        $modifyperm
        ? $q->textfield(
            -name  => 'first_name',
            -value => $duser->{'first_name'},
            -size  => 30
            )
        : $duser->{'first_name'}
        ),
        "</td>";
    print "</tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right nowrap>", "Last Name:</td>";
    print "<td width=100%>",
        (
        $modifyperm
        ? $q->textfield(
            -name  => 'last_name',
            -value => $duser->{'last_name'},
            -size  => 40
            )
        : $duser->{'last_name'}
        ),
        "</td>";
    print "</tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right nowrap>", "Email:</td>";
    print "<td width=100%>",
        (
        $modifyperm
        ? $q->textfield(
            -name  => 'email',
            -value => $duser->{'email'},
            -size  => 60
            )
        : $duser->{'email'}
        ),
        "</td>";
    print "</tr>";

    if ($modifyperm) {
        print "<tr bgcolor=$NicToolClient::dark_grey><td colspan=2>",
            "Change Password</td></tr>";

        print "<tr bgcolor=$NicToolClient::light_grey>";
        print "<td align=right nowrap>", "Current Password:</td>";
        print "<td width=100%>",
            $q->password_field( -name => 'current_password', -override => 1 ),
            "</td>";
        print "</tr>";

        print
            "<tr bgcolor=$NicToolClient::light_grey><td colspan=2>&nbsp;</td></tr>";

        print "<tr bgcolor=$NicToolClient::light_grey>";
        print "<td align=right nowrap>", "New Password:</td>";
        print "<td width=100%>",
            $q->password_field(
            -name      => 'password',
            -maxlength => 15,
            -override  => 1
            ),
            "</td>";
        print "</tr>";
        print "<tr bgcolor=$NicToolClient::light_grey>";
        print "<td align=right nowrap>", "Confirm New Password:</td>";
        print "<td width=100%>",
            $q->password_field(
            -name      => 'password2',
            -maxlength => 15,
            -override  => 1
            ),
            "</td>";
        print "</tr>";

    }

#my $ns_tree = $nt_obj->get_nameserver_tree( nt_group_id =>$user->{'nt_group_id'});
#my %nsmap = map {$data->{"usable_ns$_"}=>1} grep {$data->{"usable_ns$_"} != 0} (0..9);
#warn "nsmap: ".Data::Dumper::Dumper($data);

    if ($showpermissions) {
        my %perms = (
            group      => [qw(write create delete .)],
            user       => [qw(write create delete . )],
            zone       => [qw(write create delete delegate )],
            zonerecord => [qw(write create delete delegate)],
            nameserver => [qw(write create delete . )],
            self       => [qw(write . . . )]
        );
        my %labels = (
            group      => { 'write' => 'Edit' },
            user       => { 'write' => 'Edit' },
            zone       => { 'write' => 'Edit' },
            zonerecord => { 'write' => 'Edit' },
            nameserver => { 'write' => 'Edit' },
            self       => { 'write' => 'Edit' },
        );

        my @order = qw(group user zone zonerecord nameserver self);
        if (  !$editself && $modifyperm
            || $duser->{'inherit_group_permissions'} )
        {
            my $group = $nt_obj->get_group(
                'nt_group_id' => $duser->{'nt_group_id'} );

            #show nameservers
            my %nsmap;
            my $ns_tree;
            if ($showusablens) {
                %nsmap = map { $group->{"usable_ns$_"} => 1 }
                    grep { $group->{"usable_ns$_"} != 0 } ( 0 .. 9 );
                $ns_tree = $nt_obj->get_nameserver_list(
                    nameserver_list => join( ",", keys %nsmap ) );

                #warn "group: ".Data::Dumper::Dumper($ns_tree);
            }

            #warn "user is ".Data::Dumper::Dumper($duser);
            print "<tr bgcolor=$NicToolClient::dark_grey><td colspan=2>"
                . (
                $permmodify
                ? "<input type=radio value='1' name='group_defaults' "
                    . (
                    $duser->{'inherit_group_permissions'} ? 'CHECKED' : ''
                    )
                    . ">"
                : ''
                )
                . ( $editself
                ? "Your permissions"
                : "This user inherits the permissions defined for the parent group"
                )
                . $nt_obj->help_link('perms')
                . "</td></tr>";

            if ($showusablens) {
                print qq(
                    <tr bgcolor=$NicToolClient::light_grey>
                        <td  bgcolor=$NicToolClient::light_grey valign=top> Usable Nameservers: </td>
                        <td  bgcolor=$NicToolClient::light_grey valign=top> Permissions: </td>
                    </tr>

                );
                print qq(
                    <tr bgcolor=$NicToolClient::light_grey>
                        <td  bgcolor=$NicToolClient::light_grey valign=top>
                                  );
                my %order = map { $_->{'nt_nameserver_id'} => $_ }
                    @{ $ns_tree->{'list'} };
                foreach ( sort keys %order ) {
                    my $ns = $order{$_};
                    print
                        "<img src=$NicToolClient::image_dir/perm-checked.gif border=0>&nbsp;$ns->{'description'} ($ns->{'name'})<BR>";
                }
                if ( @{ $ns_tree->{'list'} } == 0 ) {
                    print "No available nameservers."
                        . $nt_obj->help_link('nonsavail');
                }
                print qq(
                        </td>
                );
            }
            else {
                print qq(
                    <tr bgcolor=$NicToolClient::light_grey colspan=2>);
            }

            print qq{
                <td bgcolor=$NicToolClient::light_grey colspan=2>
                    <table cellpadding=6 cellspacing=1 border=0 align=center>
                        };

            my $x = 1;
            my $color;
            foreach my $type (@order) {
                $color = (
                    $x++ % 2 == 0 ? $NicToolClient::light_grey : 'white' );
                print qq{
                        <tr>
                            <td align=right><b>}
                    . ( ucfirst($type) ) . qq{:</b></td>
                                };
                foreach my $perm ( @{ $perms{$type} } ) {
                    if ( $perm eq '.' ) {
                        print qq(
                                <td bgcolor=$color></td>
                            );
                        next;
                    }
                    print qq{
                            <td valign=center bgcolor=$color align=left><img src=$NicToolClient::image_dir/perm-}
                        . ( $group->{ $type . "_" . $perm }
                        ? 'checked.gif'
                        : 'unchecked.gif' )
                        . qq{>
                                }
                        . (
                        exists $labels{$type}->{$perm}
                        ? $labels{$type}->{$perm}
                        : ucfirst($perm) )

                        . qq{</td> };
                }
                print qq{
                        </tr>
                        };
            }
            print qq{
                    </table>
                </td>
            </tr>
            };
        }

        if (   !$editself && $modifyperm
            || !$duser->{'inherit_group_permissions'} )
        {

            my %nsmap;
            my $ns_tree;
            if ($showusablens) {
                %nsmap = map { $duser->{"usable_ns$_"} => 1 }
                    grep { $duser->{"usable_ns$_"} != 0 } ( 0 .. 9 );
                $ns_tree = $nt_obj->get_usable_nameservers
                    ;    #(nt_group_id=>$user->{'nt_group_id'});
            }

            print "<tr bgcolor=$NicToolClient::dark_grey><td colspan=2>"

                #.($modifyperm && !$editself
                . (
                $permmodify
                ? "<input type=radio value='0' name='group_defaults'"
                    . (
                    $duser->{'inherit_group_permissions'} ? '' : 'CHECKED'
                    )
                    . ">"
                : ''
                )
                . ( $editself
                ? "Your permissions"
                : "This user uses the permissions defined below" )
                . $nt_obj->help_link('perms')
                . "</td></tr>";

            if ($showusablens) {
                print qq(
                     <tr bgcolor=$NicToolClient::light_grey>
                        <td  bgcolor=$NicToolClient::light_grey valign=top> Usable Nameservers: </td>
                        <td  bgcolor=$NicToolClient::light_grey valign=top> Permissions: </td>
                    </tr>
                                  );

                print qq(
                     <tr bgcolor=$NicToolClient::light_grey>
                        <td  bgcolor=$NicToolClient::light_grey valign=top>
                                  );
                my %order = map { $_->{'nt_nameserver_id'} => $_ }
                    @{ $ns_tree->{'nameservers'} };
                foreach ( sort keys %order ) {
                    my $ns = $order{$_};
                    print $q->checkbox(
                        -name    => "usable_nameservers",
                        -checked => $nsmap{ $ns->{'nt_nameserver_id'} }
                        ? 1
                        : 0,
                        -value => $ns->{'nt_nameserver_id'},
                        -label => "$ns->{'description'} ($ns->{'name'})"
                        ),
                        "<BR>";
                }
                if ( @{ $ns_tree->{'nameservers'} } == 0 ) {
                    print "No available nameservers."
                        . $nt_obj->help_link('nonsavail');
                }
                print qq(
                        </td>
                );
            }
            else {
                print qq(
                <tr bgcolor=$NicToolClient::light_grey colspan=2>);
            }

            print qq{
                <td colspan=2 bgcolor=$NicToolClient::light_grey>
                    <table cellpadding=6 cellspacing=1 border=0 align=center>
                        };
            my $x = 1;
            my $color;
            @order = qw(group user zone zonerecord nameserver self header);
            foreach my $type (@order) {
                if ( $type eq 'header' ) {
                    next if $editself;
                    print qq(
                        <tr><td></td>
                    );
                    foreach (qw(Edit Create Delete Delegate All)) {
                        if ( $_ eq '.' ) {
                            print "<td></td>";
                            next;
                        }
                        print "<td>";
                        print $q->checkbox(
                            -name  => "select_all_$_",
                            -label => '',
                            -onClick =>
                                "selectAll$_(document.perms_form, this.checked);",
                            -override => 1
                        );
                        print "</td>";
                    }
                    print qq(
                        </tr>
                    );
                }
                else {
                    $color
                        = ( $x++ % 2 == 0
                        ? $NicToolClient::light_grey
                        : 'white' );
                    print qq{
                            <tr>
                                <td align=right><b>}
                        . ( ucfirst($type) ) . qq{:</b></td>
                                    };
                    foreach my $perm ( @{ $perms{$type} } ) {
                        if ( $perm eq '.' ) {
                            print qq(
                                <td>&nbsp;</td>
                            );
                            next;
                        }
                        if (   $modifyperm
                            && $user->{ $type . "_" . $perm }
                            && !$editself )
                        {
                            print qq{
                                <td valign=center align=left bgcolor=$color> };
                            print $q->checkbox(
                                -name    => $type . "_" . $perm,
                                -value   => '1',
                                -checked => $duser->{ $type . "_" . $perm }
                                ? 1
                                : 0,
                                -label => ''
                                )
                                . (
                                exists $labels{$type}->{$perm}
                                ? $labels{$type}->{$perm}
                                : ucfirst($perm) )
                                . qq{</td> };
                        }
                        else {
                            print qq{
                                <td bgcolor=$color valign=center align=left><img src=$NicToolClient::image_dir/perm-}
                                . ( $duser->{ $type . "_" . $perm }
                                ? 'checked.gif'
                                : 'unchecked.gif' )
                                . qq{>
                                    }
                                . ( $modifyperm && !$editself
                                ? qq{<font color=$NicToolClient::disabled_color>}
                                : '' )
                                . (
                                exists $labels{$type}->{$perm}
                                ? $labels{$type}->{$perm}
                                : ucfirst($perm) )
                                . ( $modifyperm
                                    && !$editself ? '</font>' : '' )
                                . qq{</td> };
                        }
                    }
                    if ( $modifyperm && !$editself ) {
                        print "<td>"
                            . $q->checkbox(
                            -name    => "select_all_$type",
                            -label   => '',
                            -onClick => "selectAll"
                                . ucfirst($type)
                                . "(document.perms_form, this.checked);",
                            -override => 1
                            ) . "</td>";
                    }
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
    }
    if ($modifyperm) {
        print
            "<tr bgcolor=$NicToolClient::dark_grey><td colspan=2 align=center>",
            $q->submit( $edit eq 'edit' ? 'Save' : 'Create' ),
            $q->submit('Cancel'), "</td></tr>";
    }
    print "</table>";
    print $q->end_form;
}
