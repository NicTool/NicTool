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
    my $q      = CGI->new();
    my $nt_obj = NicToolClient->new($q);

    return if $nt_obj->check_setup ne 'OK';

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

    my $duser = $nt_obj->get_user( nt_user_id => $q->param('nt_user_id') );
    if ( $duser->{'error_code'} ne 200 ) {
        print $nt_obj->display_error($duser);
    }

    #warn "user info: ".Data::Dumper::Dumper($user);
    my $edit_message;

# send the request to NicToolServer and parse result
    if (   ( $q->param('edit') && $q->param('Save') )
        || ( $q->param('new') && $q->param('Create') )   ) {

        my ( $error, %data );
        my @fields = qw/ user_create user_delete user_write group_create group_delete group_write zone_create zone_delegate zone_delete zone_write zonerecord_create zonerecord_delegate zonerecord_delete zonerecord_write nameserver_create nameserver_delete nameserver_write self_write /;
        my @new_fields  = qw/ nt_group_id username first_name last_name email password password2 /;
        my @edit_fields = qw/ nt_user_id username first_name last_name email password password2 current_password/;

        #warn "group_defaults is ".$q->param('group_defaults');
        if ( $q->param('group_defaults') eq '0' ) {
            foreach (@fields) {
                $data{$_} = $q->param($_) ? 1 : 0;
            }
        }
        else {
            $data{'inherit_group_permissions'} = 1;
        }

        if ( $q->param('edit') ) {
            foreach ( @edit_fields ) { $data{$_} = $q->param($_); }
            $error = $nt_obj->edit_user(%data);
        }
        elsif ( $q->param('new') ) {
            foreach ( @new_fields ) { $data{$_} = $q->param($_); }
            $error = $nt_obj->new_user(%data);
        }

        if ( $error->{'error_code'} != 200 ) {
            $edit_message = $error;
            #warn "error = ".Data::Dumper::Dumper($error);
        }

        # refresh the user info displayed in form
        if ( $q->param('nt_user_id') ) {
            $duser = $nt_obj->get_user( nt_user_id => $q->param('nt_user_id') );
        };
    };

    $q->param( 'nt_group_id', $duser->{'nt_group_id'} );

    my $level = $nt_obj->display_group_tree(
        $user,
        $user->{'nt_group_id'},
        $q->param('nt_group_id'), 0
    );
    $nt_obj->display_user_list_options( $user, $q->param('nt_group_id'), $level, 0 );

    $level++;

    my $group = $nt_obj->get_group( nt_group_id => $user->{'nt_group_id'} );

    my @options;
    if ( $user->{'user_delete'}
        && ( $user->{'nt_user_id'} ne $duser->{'nt_user_id'} ) )
    {
        push @options, qq[<a href="group_users.cgi?nt_group_id=].$q->param('nt_group_id').qq[&amp;delete=1&amp;obj_list=$duser->{'nt_user_id'}" onClick="return confirm('Delete user $duser->{'username'}?');">Delete</a>];
    }
    else {
        push @options, "<span class=disabled>Delete</span>";
    }

    if (   $user->{'user_write'}
        && $user->{'nt_user_id'} ne $duser->{'nt_user_id'} )
    {
        push @options, qq[<a href="javascript:void window.open('move_users.cgi?obj_list=$duser->{'nt_user_id'}', 'move_win', 'width=640,height=480,scrollbars,resizable=yes')">Move</a>] if $group->{'has_children'};
    }
    else {
        push @options, '<span class="disabled">Move</span>' if $group->{'has_children'};
    }

    print qq[<table class="fat">
<tr class="light_grey_bg">
<td>
<table class="no_pad fat">
<tr>];

    for my $x ( 1 .. $level ) {
        print qq[<td><img src="$NicToolClient::image_dir/]
            . ( $x == $level ? 'dirtree_elbow' : 'transparent' )
            . qq[.gif" class="tee" alt=""></td>];
    }

    print qq[<td><img src="$NicToolClient::image_dir/user.gif"></td>
<td class="nowrap"><b>$duser->{'username'}</b></td>
<td class="right fat">], join( ' | ', @options ), qq[</td>
</tr></table>
</td></tr></table>];

    display_properties( $nt_obj, $q, $user, $duser, $edit_message );
    display_global_log( $nt_obj, $q, $user, $duser, $message );

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
                display_edit( $nt_obj, $q, $message, $user, $duser, 'new' );
            }
        }
        elsif ( $q->param('Cancel') ) { }
        else {
            display_edit( $nt_obj, $q, '', $user, $duser, 'new' );
        }
    }
    elsif ( $q->param('edit') ) {
        if ( $q->param('Save') ) {
            if ($message) {
                display_edit( $nt_obj, $q, $message, $user, $duser, 'edit' );
            }
        }
        elsif ( $q->param('Cancel') ) { }
        else {
            display_edit( $nt_obj, $q, '', $user, $duser, 'edit' );
        }
    }

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

    print qq[<table class="fat">
    <tr class="dark_grey_bg">
     <td>
      <table class="no_pad fat">
       <tr>
        <td><b>Properties</b></td>];
    my $modname = 'View Details';
    $modname = "Edit" if $modifyperm;
    my $gid = $q->param('nt_group_id');
    my $uid = $duser->{'nt_user_id'};

    print qq[
        <td class=right><a href="user.cgi?], join( '&amp;', @state_fields ),
qq[&amp;nt_group_id=$gid&amp;nt_user_id=$uid&amp;edit=1">$modname</a></td>
       </tr>
      </table>
     </td>
    </tr>
   </table>];

    print qq[
<table class="fat" cellspacing=0>
 <tr>
  <td class="width50">
   <table class="fat">
    <tr class="light_grey_bg">
     <td class="nowrap">Username: </td> <td class="fat">$duser->{'username'}</td>
    </tr>
    <tr class="light_grey_bg">
     <td class="nowrap">Email: </td> <td class="fat">$duser->{'email'}</td>
    </tr>
   </table>
  </td>
  <td class="width50">
   <table class="fat">
    <tr class="light_grey_bg">
     <td class="nowrap">First Name: </td> <td class="fat">$duser->{'first_name'}</td>
    </tr>
    <tr class="light_grey_bg">
     <td class="nowrap">Last Name: </td> <td class="fat">$duser->{'last_name'}</td>
    </tr>
   </table>
  </td>
 </tr>
</table>];

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

    print qq[<table class="fat"><tr><td><hr></td></tr>];

    $nt_obj->display_nice_error($message) if $message;
    print qq[
 <tr class="dark_grey_bg"><td>
   <table class="no_pad fat">
    <tr><td class="bold">Global Application Log</td></tr>
   </table>
  </td></tr>
</table>];

    $nt_obj->display_search_rows( $q, $rv, \%params, $cgi, \@req_fields );

    if (!@$list) {
        print "<center>No log data available</center>";
        return;
    };

    print qq[<table class="fat"> <tr class=dark_grey_bg>];
    foreach (@columns) {
        if ( $sort_fields{$_} ) {
            my $direc = uc( $sort_fields{$_}->{'mod'} ) eq 'ASCENDING' ? 'up' : 'down';
            print qq[
 <td class="dark_bg center"><table class="no_pad">
  <tr>
   <td>$labels{$_}</td>
   <td>&nbsp; &nbsp; $sort_fields{$_}->{'order'}</td>
   <td><img src=$NicToolClient::image_dir/$direc.gif></td>
  </tr>
 </table>
</td>];
        }
        else {
            print qq[<td class="center">$labels{$_}</td>];
        }
    }
    print "</tr>";

    my $map = $nt_obj->obj_to_cgi_map();

    my $x = 0;
    my $range;
    foreach my $row (@$list) {

        my $bgcolor = ( $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg' );
        print qq[<tr class="bgcolor">];
        foreach (@columns) {
            my $state_string = @state_fields ? join( '&amp;', @state_fields ) : 'not_empty=1';
            if ( $_ eq 'timestamp' ) {
                print '<td>', scalar localtime( $row->{$_} ), '</td>';
            }
            elsif ( $_ eq 'object' ) {
                my $txt = $row->{'object'};
                $txt = join( ' ', map( ucfirst, split( /_/, $txt ) ) );
                print qq[<td>$txt</td>];
            }
            elsif ( $_ eq 'title' ) {
                my $obj = $q->escape( $row->{'object'} );
                my $obj_id = $q->escape( $row->{'object_id'} );
                my $url = "user.cgi?$state_string&amp;redirect=1&amp;nt_group_id=$duser->{'nt_group_id'}&amp;nt_user_id=$duser->{'nt_user_id'}&amp;object=$obj&amp;obj_id=$obj_id";
                my $img = "$NicToolClient::image_dir/$map->{ $row->{'object'} }->{'image'}";
                print qq[
<td>
 <table class="no_pad"><tr>
    <td><a href="$url"><img src="$img" alt="image"></a></td>
    <td><a href="$url">$row->{'title'}</a></td>
 </tr></table></td>];
            }
            elsif ( $_ eq 'target' && $row->{'target_id'} ) {
                my $target    = $q->escape( $row->{'target'} );
                my $target_id = $q->escape( $row->{'target_id'} );
                my $url = "user.cgi?$state_string&amp;redirect=1&amp;nt_group_id=$duser->{'nt_group_id'}&amp;nt_user_id=$duser->{'nt_user_id'}&amp;object=$target&amp;obj_id=$target_id";
                my $img = "$NicToolClient::image_dir/$map->{ $row->{'target'} }->{'image'}";
                print qq[
<td>
 <table class="no_pad">
  <tr>
   <td><a href="$url"><img src="$img"></a></td>
   <td><a href="$url">$row->{'target_name'}</a></td>
  </tr>
 </table>
</td>];
            }
            else {
                print "<td>", ( $row->{$_} ? $row->{$_} : '&nbsp;' ), "</td>";
            }
        }
        print "</tr>";
    }

    print "</table>";
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

    $nt_obj->display_nice_error( $message, ucfirst($edit) . " User" )
        if $message;

    print qq[<a name='ZONE'></a>
<table class="fat">
 <tr class="dark_bg"><td colspan=2><b>$modname</b></td></tr>
 <tr class="light_grey_bg">
  <td class="right nowrap">Username:</td>
  <td class="fat">],
        ( $modifyperm ? $q->textfield( -name  => 'username', -value => $duser->{'username'}, -size  => 30) : $duser->{'username'} ),
        qq[</td>
</tr>
<tr class="light_grey_bg">
<td class="nowrap right">First Name:</td>
<td class="fat">],
        ( $modifyperm ? $q->textfield( -name  => 'first_name', -value => $duser->{'first_name'}, -size  => 30) : $duser->{'first_name'} ),
        qq[</td>
</tr>
<tr class="light_grey_bg">
<td class="right nowrap">Last Name:</td>
<td class="fat">],
        ( $modifyperm ? $q->textfield( -name => 'last_name', -value => $duser->{'last_name'}, -size  => 40) : $duser->{'last_name'} ),
        qq[</td>
</tr>
<tr class="light_grey_bg">
<td class="right nowrap">Email:</td>
<td class="fat">],
        ( $modifyperm ? $q->textfield( -name  => 'email', -value => $duser->{'email'}, -size  => 60) : $duser->{'email'} ),
        "</td>
    </tr>";

    if ($modifyperm) {
        if ( ! $user->{is_admin} ) {    # note that is_admin is global
        print qq[<tr class="dark_grey_bg"><td colspan="2">Change Password</td></tr>
<tr class="light_grey_bg">
<td class="right nowrap">Current Password:</td>
<td class="fat">],
            $q->password_field( -name => 'current_password', -override => 1 ),
            qq[</td>
</tr>];
        };

        print qq[<tr class="light_grey_bg"><td colspan="2">&nbsp;</td></tr>
<tr class="light_grey_bg">
<td class="right nowrap">New Password:</td>
<td class="fat">],
            $q->password_field( -name => 'password', -size=>15, -maxlength => 30, -override  => 1),
            qq[</td>
</tr>
<tr class="light_grey_bg">
<td class="right nowrap">Confirm New Password:</td>
<td class="fat">],
            $q->password_field( -name => 'password2', -size=>15, -maxlength => 30, -override  => 1),
            qq[</td>
        </tr>];
    }

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
            my $group = $nt_obj->get_group( nt_group_id => $duser->{'nt_group_id'} );

            #show nameservers
            my %nsmap;
            my $ns_tree;
            if ($showusablens) {
                %nsmap = map { $_ => 1 } split(',', $duser->{'usable_ns'});
                $ns_tree = $nt_obj->get_nameserver_list(
                    nameserver_list => join( ",", keys %nsmap ) );
            }

            #warn "user is ".Data::Dumper::Dumper($duser);
            print qq[<tr class="dark_grey_bg"><td colspan="2">]
                . (
                $permmodify
                ? qq[<input type="radio" value="1" name="group_defaults" ]
                    . ( $duser->{'inherit_group_permissions'} ? 'CHECKED' : '')
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
                    <tr class="light_grey_bg">
                        <td class="light_grey_bg top"> Usable Nameservers: </td>
                        <td class="light_grey_bg top"> Permissions: </td>
                    </tr>

                );
                print qq( <tr class="light_grey_bg"> <td class="light_grey_bg top">);
                my %order = map { $_->{'nt_nameserver_id'} => $_ }
                    @{ $ns_tree->{'list'} };
                foreach ( sort keys %order ) {
                    my $ns = $order{$_};
                    print qq[<img src="$NicToolClient::image_dir/perm-checked.gif">&nbsp;$ns->{'description'} ($ns->{'name'})<br>];
                }
                if ( @{ $ns_tree->{'list'} } == 0 ) {
                    print "No available nameservers."
                        . $nt_obj->help_link('nonsavail');
                }
                print qq[</td>];
            }
            else {
                print qq[<tr class="light_grey_bg" colspan="2">];
            }

            print qq{
<td class="light_grey_bg" colspan="2">
 <table class="center" style="padding:6; border-spacing:1;">
};

            my $x = 1;
            my $color;
            foreach my $type (@order) {
                $color = ( $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg' );
                print qq[
  <tr> <td class="right bold">] . ucfirst($type) . qq[:</td>];
                foreach my $perm ( @{ $perms{$type} } ) {
                    if ( $perm eq '.' ) {
                        print qq[
   <td class=$color></td>];
                        next;
                    }
                    my $pc = $group->{ $type . "_" . $perm } ? 'checked' : 'unchecked';
                    my $permc = $labels{$type}{$perm} || ucfirst $perm;
                    print qq[
    <td class="$color left middle">
     <img src="$NicToolClient::image_dir/perm-$pc.gif">$permc </td>];
                }
                print qq[
   </tr>];
            }
            print qq[
  </table>
 </td>
</tr> ];
        }

        if (   !$editself && $modifyperm
            || !$duser->{'inherit_group_permissions'} )
        {

            my %nsmap;
            my $ns_tree;
            if ($showusablens) {
                %nsmap = map { $_ => 1 } split(',', $duser->{'usable_ns'});
                $ns_tree = $nt_obj->get_usable_nameservers
                    ;    #(nt_group_id=>$user->{'nt_group_id'});
            }

            print '<tr class="dark_grey_bg"><td colspan="2">'

                #.($modifyperm && !$editself
                . (
                $permmodify
                ? '<input type="radio" value="0" name="group_defaults" '
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
                     <tr class="light_grey_bg">
                        <td class="light_grey_bg top"> Usable Nameservers: </td>
                        <td class="light_grey_bg top"> Permissions: </td>
                    </tr>
                                  );

                print qq(
                     <tr class="light_grey_bg">
                      <td class="light_grey_bg top">
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
                print qq( </td>);
            }
            else {
                print qq(<tr class="light_grey_bg" colspan="2">);
            }

            print qq[
<td colspan="2" class="light_grey_bg">
 <table class="center" style="padding:6; border-spacing:1;"> ];
            my $x = 1;
            my $color;
            @order = qw(group user zone zonerecord nameserver self header);
            foreach my $type (@order) {
                if ( $type eq 'header' ) {
                    next if $editself;
                    print qq( <tr><td></td>);
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
                    print qq( </tr>);
                }
                else {
                    $color = ( $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg' );
                    print qq{ <tr> <td class="right"><b>}
                        . ( ucfirst($type) ) . qq{:</b></td>
                                    };
                    foreach my $perm ( @{ $perms{$type} } ) {
                        if ( $perm eq '.' ) {
                            print qq( <td>&nbsp;</td>);
                            next;
                        }
                        if (   $modifyperm
                            && $user->{ $type . "_" . $perm }
                            && !$editself )
                        {
                            print qq{ <td class="center left $color"> };
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
                                <td class="$color center left"><img src="$NicToolClient::image_dir/perm-}
                                . ( $duser->{ $type . "_" . $perm } ? 'checked.gif' : 'unchecked.gif' ) . qq{">}
                                . ( $modifyperm && !$editself ? qq{<span class=disabled>} : '' )
                                . (
                                exists $labels{$type}->{$perm}
                                ? $labels{$type}->{$perm}
                                : ucfirst($perm) )
                                . ( $modifyperm
                                    && !$editself ? '</span>' : '' )
                                . qq{</td>};
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
        print qq[<tr class="dark_grey_bg"><td colspan="2" class="center">],
            $q->submit( $edit eq 'edit' ? 'Save' : 'Create' ),
            $q->submit('Cancel'), "</td></tr>";
    }
    print "</table>",
    $q->end_form;
}

