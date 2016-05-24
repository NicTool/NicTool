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
    $nt_obj->parse_template(
        $NicToolClient::body_frame_start_template,
        username  => $user->{username},
        groupname => $user->{groupname},
        userid    => $user->{nt_user_id},
    );

    my $level = $nt_obj->display_group_tree(
        $user,
        $user->{'nt_group_id'},
        $q->param('nt_group_id'), 0
    );
    display_list_options( $user, $q->param('nt_group_id'), $level, 1 );

    do_new( $nt_obj, $q, $user );
    do_edit( $nt_obj, $q, $user );
    do_delete( $nt_obj, $q );

    my $group = $nt_obj->get_group( nt_group_id => $q->param('nt_group_id') );

    display_list( $nt_obj, $q, $group, $user );

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub do_new {
    my ( $nt_obj, $q, $user ) = @_;

    return if ! $q->param('new');
    return if $q->param('Cancel');

    if ( ! $q->param('Create') ) {
        display_edit_nameserver( $nt_obj, $user, $q, '', 'new' );
        return;
    };

    my @fields = qw/ nt_group_id name ttl description address address6 logdir
                datadir remote_login export_format export_interval export_serials /;
    my %data;
    foreach my $x (@fields) {
        $data{$x} = $q->param($x);
    }
    my $error = $nt_obj->new_nameserver(%data);
    if ( $error->{'error_code'} != 200 ) {
        display_edit_nameserver( $nt_obj, $user, $q, $error, 'new' );
    }
};

sub do_delete {
    my ( $nt_obj, $q ) = @_;

    return if ! $q->param('delete');

    my $error = $nt_obj->delete_nameserver(
        nt_group_id      => $q->param('nt_group_id'),
        nt_nameserver_id => $q->param('nt_nameserver_id')
    );
    if ( $error->{'error_code'} != 200 ) {
        $nt_obj->display_nice_error( $error, "Delete Nameserver" );
    }
};

sub do_edit {
    my ( $nt_obj, $q, $user ) = @_;

    return if ! $q->param('edit');  # nothing to do
    return if $q->param('Cancel');  # user clicked Cancel

    if ( ! $q->param('Save') ) {
        display_edit_nameserver( $nt_obj, $user, $q, '', 'edit' );
        return;
    };

    # user clicked the 'Save' button
    my @fields = qw/ nt_group_id nt_nameserver_id name ttl description
                     address address6 logdir datadir remote_login
                     export_format export_serials export_interval /;

    my %data;
    foreach my $x (@fields) {
        $data{$x} = $q->param($x);
    }
    my $error = $nt_obj->edit_nameserver(%data);
    if ( $error->{'error_code'} != 200 ) {
        display_edit_nameserver( $nt_obj, $user, $q, $error, 'edit' );
    }
};

sub display_list {
    my ( $nt_obj, $q, $group, $user ) = @_;

    my $cgi = 'group_nameservers.cgi';

    my $user_group = $nt_obj->get_group( nt_group_id => $user->{'nt_group_id'} );

    my @columns = qw(name description address status);
    my %labels = (
        name        => 'Name',
        description => 'Description',
        address     => 'IPv4 Address',
        export_format=> 'Export Format',
        status     => 'Export Status',
        group_name => 'Group'
    );

    my $include_subgroups = $group->{'has_children'} ? 'sub-groups' : undef;
    if ($include_subgroups) {
        unshift @columns, 'group_name';
    }

    my %params = ( nt_group_id => $q->param('nt_group_id') );

    my $rv = $nt_obj->get_group_nameservers(%params);

    if ( $q->param('edit_sortorder') ) {
        $nt_obj->display_sort_options( $q, \@columns, \%labels, $cgi,
            ['nt_group_id'], $include_subgroups );
    };
    if ( $q->param('edit_search') ) {
        $nt_obj->display_advanced_search( $q, \@columns, \%labels, $cgi,
            ['nt_group_id'], $include_subgroups );
    };

    return $nt_obj->display_nice_error( $rv, "Get Group Nameservers" )
        if $rv->{'error_code'} != 200;

    my $list = $rv->{'list'};
    my $map  = $rv->{'group_map'};

    my $state;
    foreach ( @{ $nt_obj->paging_fields } ) {
        next if ! $q->param($_);
        $state .= "&amp;$_=" . $q->escape( $q->param($_) );
    }

    display_list_actions( $q, $user, $user_group, $state, $list );

    my %params = ( nt_group_id => $q->param('nt_group_id') );
    my %sort_fields;
    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields, 100 );
    if ( ! %sort_fields ) {
        $sort_fields{'name'} = { 'order' => 1, 'mod' => 'Ascending' };
    };

    $nt_obj->display_search_rows( $q, $rv, \%params, $cgi, ['nt_group_id'], $include_subgroups );

    if (! @$list ) {
        print $q->end_form;
        return;
    };

    $nt_obj->display_move_javascript( 'move_nameservers.cgi', 'nameserver' );

    print qq[
<form method="post" action="move_nameservers.cgi" target="move_win" name="list_form">];
    display_list_header( $nt_obj, $q, $rv, \@columns, \%labels, $user_group, \%sort_fields );

    print qq[\n <tbody>];

    my $x     = 0;
    my $width = int( 100 / @columns ) . '%';

    foreach my $obj (@$list) {
        my $bgcolor = $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg';
        print qq[
 <tr class="$bgcolor">];

        display_list_move_checkbox( $q, $user, $user_group, $obj );
        display_list_subgroups( $width, $obj, $map ) if $include_subgroups;
        display_list_name( $obj, $width );

        foreach ( qw/ description address status / ) {
            print qq[\n  <td style="width: $width;"> $obj->{$_} </td>];
        }

        display_list_delete( $q, $user, $obj, $state );

        print qq[
 </tr>];
    };

    print qq[
 </tbody>
</table>\n],
    $q->end_form;
}

sub display_list_actions {
    my ( $q, $user, $user_group, $state, $list ) = @_;

    print qq[
<div id="nameserverListActions" class="dark_grey_bg">
 <span class="bold">Nameserver List</span>
 <ul class=menu_r>];

    my $gid = $q->param('nt_group_id');

    if ( @$list && $user_group->{'has_children'} ) {
        print qq[
  <li class="first"><a href="javascript:void open_move(document.list_form.obj_list);">Move Selected Nameservers</a></li>];
    }
    else {
        print qq[
  <li class="first disabled">Move Nameservers</li>];
    };
    if ( $user->{'nameserver_create'} ) {
        print qq[
  <li><a href="group_nameservers.cgi?nt_group_id=${gid}${state}&amp;new=1">New Nameserver</a></li>];
    }
    else {
        print qq[
  <li class=disabled>New Nameserver</li>];
    }
    print qq[
 </ul>
</div>
];
};

sub display_list_header {
    my ( $nt_obj, $q, $rv, $columns, $labels, $user_group, $sort_fields ) = @_;

    print qq[
<table id="nameserverList" class="fat">
 <thead>
  <tr class=dark_grey_bg>];

    if ( $user_group->{'has_children'} ) {
        print qq[
   <td class=center id="selectAllCheckbox"> ];

        if ( $rv->{'total'} > 1 ) {
            print $q->checkbox(
                -name  => 'select_all_or_none',
                -label => '',
                -onClick =>
                    'selectAllorNone(document.list_form.obj_list, this.checked)',
                -override => 1
            );
        };
        print qq[
   </td>];
    };

    foreach (@$columns) {
        if ( $sort_fields->{$_} ) {
            my $sortdir = uc( $sort_fields->{$_}->{'mod'} ) eq 'ASCENDING' ? 'up' : 'down';
            print qq[
   <td class="dark_bg nowrap center" id="${_}Header"> $labels->{$_} &nbsp; &nbsp; $sort_fields->{$_}->{'order'}
     <img src="$NicToolClient::image_dir/$sortdir.gif" alt="$sortdir"></td>];
        }
        else {
            print qq[
   <td class="center nowrap" id="${_}Header">$labels->{$_}</td>];
        }
    }

    print qq[
   <td class=width1 id="Trash"></td>
  </tr>
 </thead>];
};

sub display_list_move_checkbox {
    my ( $q, $user, $user_group, $obj ) = @_;

    return if ! $user_group->{'has_children'};

    print qq[
  <td class="width1 center">];

    if ($user->{'nameserver_write'}
        && ( !exists $obj->{'delegate_write'} || $obj->{'delegate_write'} )) {

        print $q->checkbox(
            -name  => 'obj_list',
            -value => $obj->{'nt_nameserver_id'},
            -label => '',
        );
    }
    else {
        print qq[<img src="$NicToolClient::image_dir/nobox.gif" alt="nobox">];
    }
    print qq[
  </td>];
};

sub display_list_subgroups {
    my ( $width, $obj, $map ) = @_;

    print qq[
  <td style="width:1" class="nowrap">
     <img src="$NicToolClient::image_dir/group.gif" alt="group">];

    my @list = (
        {   nt_group_id => $obj->{'nt_group_id'},
            name        => $obj->{'group_name'}
        }
    );
    if ($map) { unshift @list, @{ $map->{ $obj->{'nt_group_id'} } }; };

    my $url = qq[<a href="group.cgi?nt_group_id=];
    my $group_string = join( ' / ',
        map( qq[${url}$_->{'nt_group_id'}">$_->{'name'}</a>], @list ) );

    print qq[ $group_string
  </td>];
}

sub display_list_name {
    my ( $obj, $width ) = @_;

    print qq[
  <td class="nowrap side_pad" style="width:$width;">
     <a href="group_nameservers.cgi?nt_nameserver_id=$obj->{'nt_nameserver_id'}&amp;nt_group_id=$obj->{'nt_group_id'}&amp;edit=1">
      <img src="$NicToolClient::image_dir/nameserver.gif" alt="nameserver"> $obj->{'name'} </a>
  </td>];
};

sub display_list_options {
    my ( $user, $group_id, $level, $in_ns_summary ) = @_;

    print qq[
<div id="nameserverOptions" class="light_grey_bg">];

    my $pad = 0;
    for my $x ( 1 .. $level ) {
        if ( $x == $level ) {
            print qq[<img src="$NicToolClient::image_dir/dirtree_elbow.gif" class="tee" style="padding-left: ${pad}px;" alt="elbow">];
        };
        $pad += 19;
    }

    print qq[<img src="$NicToolClient::image_dir/folder_open.gif" alt="folder">];

    if ($in_ns_summary) {
        print qq[<span class="bold">Nameservers</span>];
    }
    else {
        print qq[<a href="group_nameservers.cgi?nt_group_id=$group_id">Nameservers</a>];
    }
    print qq[
 <ul class="menu_r">
  <li class=first>];

    if ( !$in_ns_summary ) {
        if ( $user->{'nameserver_create'} ) {
            print qq[<a href="group_nameservers.cgi?nt_group_id=$group_id&amp;edit=1">New Nameserver</a>];
        }
        else {
            print qq[<span class="disabled">New Nameserver</class>];
        }
    };

    print
     qq[
 </li>
</div>];
}

sub display_list_delete {
    my ($q, $user, $obj, $state) = @_;

    if ($user->{'nameserver_delete'}
        && ( !exists $obj->{'delegate_delete'} || $obj->{'delegate_delete'} )) {

        my $gid = $q->param('nt_group_id');
        print qq[
  <td class="width1">
   <a href="group_nameservers.cgi?$state&amp;nt_group_id=$gid&amp;delete=1&amp;nt_nameserver_id=$obj->{'nt_nameserver_id'}" onClick="return confirm('Delete nameserver $obj->{'name'}?');">
   <img src="$NicToolClient::image_dir/trash.gif" alt="trash"></a></td>];
    }
    else {
        print qq[
  <td class=width1>
   <img src="$NicToolClient::image_dir/trash-disabled.gif" alt="disabled trash"></td>];
    }
};

sub display_edit_nameserver {
    my ( $nt_obj, $user, $q, $message, $edit ) = @_;

# logdir
    my @fields = qw/ name address address6 export_format datadir remote_login
                     ttl export_interval export_serials description / ;

    my $nameserver;
    if ( $q->param('nt_nameserver_id') && !$q->param('Save') ) {
        # get current settings
        $nameserver = $nt_obj->get_nameserver(
            nt_group_id      => $q->param('nt_group_id'),
            nt_nameserver_id => $q->param('nt_nameserver_id')
        );
        if ( $nameserver->{'error_code'} != 200 ) {
            $message = $nameserver;
        }
        else {
            foreach ( 'nt_nameserver_id', @fields ) {
                $q->param( $_, $nameserver->{$_} );
            }
        }
    }

    my $modifyperm
        = $user->{'nameserver_write'}
        && ( !exists $nameserver->{'delegate_write'}
        || $nameserver->{'delegate_write'} );

    if ($modifyperm) {
        my $gid = $q->param('nt_group_id');
        print qq[
<form method="post" action="group_nameservers.cgi">
 <input type="hidden" name="$edit" value="]. $q->param($edit) .qq["  />
 <input type="hidden" name="nt_group_id" value="$gid"  />
 ];
        if ( $edit ne 'new' ) {
            print $q->hidden( -name => 'nt_nameserver_id' );
        };
    }

    $nt_obj->display_nice_error($message) if $message;
    my $title = 'View Nameserver Details';
    if ($modifyperm) {
        $title = ucfirst($edit) . " Nameserver";
    };

    my %labels = display_edit_nameserver_fields( $nt_obj, $q, $nameserver, $modifyperm );

    print qq[
<table class="fat">
 <tr class=dark_bg><td colspan=2 class="bold">$title</td></tr>];

    foreach my $f ( @fields ) {
        print qq[
 <tr id="${f}_row" class=light_grey_bg>
  <td class=right>$labels{$f}{label}:</td>
  <td class="width70">$labels{$f}{value}<span id="${f}_url"></span></td>
 </tr>];
    };

    if ($modifyperm) {
        print qq[
 <tr class=dark_grey_bg>
  <td colspan=2 class=center>],
        $q->submit( $edit eq 'edit' ? 'Save' : 'Create' ),
        $q->submit('Cancel'), "</td>
 </tr>
 <script>\$(document).ready(function(){ changeNSExportType(); });</script>";
    }

    print qq[
</table>];
    print $q->end_form if $modifyperm;
}

sub display_edit_nameserver_fields {
    my ( $nt_obj, $q, $nameserver, $modifyperm ) = @_;

    my $ttl = $q->param('ttl') || $NicToolClient::default_nameserver_ttl;

    my $export_formats = $nt_obj->ns_export_types();
    my %export_formats = map { $_->{name} => "$_->{name} ($_->{descr})" } @$export_formats;

    my $export_format_values = [ sort keys %export_formats ];
    my $export_format_labels  = \%export_formats;

    return (
        name            => {
            label => 'Fully qualified nameserver name',
            value => $modifyperm
                    ? $q->textfield( -name => 'name', -size => 45, -maxlength => 127 )
                    : $nameserver->{'name'},
        },
        ttl             => {
            label => 'TTL',
            value => $modifyperm
                    ? $q->textfield(
                        -id        => 'ttl',
                        -name      => 'ttl',
                        -size      => 10,
                        -maxlength => 10,
                        -default   => $ttl
                        )
                    : $nameserver->{'ttl'},
        },
        description     => {
            label => 'Description',
            value => $modifyperm
                    ? $q->textarea(
                        -id        => 'description',
                        -name      => 'description',
                        -cols      => 50,
                        -rows      => 4,
                        -maxlength => 255
                        )
                    : $nameserver->{'description'},
        },
        address         => {
            label => 'IPv4 Address',
            value => $modifyperm
                    ? $q->textfield( -id => 'address', -name => 'address', -size => 20, -maxlength => 15)
                    : $nameserver->{'address'},
        },
        address6        => {
            label => 'IPv6 Address',
            value => $modifyperm
                    ? $q->textfield( -id => 'address6', -name => 'address6', -size => 45, -maxlength => 39)
                    : $nameserver->{'address6'},
        },
        remote_login => {
            label => 'Remote Login',
            value => $modifyperm
                    ? $q->textfield(
                        -id   => 'remote_login',
                        -name => 'remote_login',
                        -size => 45,
                        -maxlength => 64,
                        )
                    : '********************',
        },
        export_format => {
            label => 'Export Format',
            value => $modifyperm
                    ? $q->popup_menu(
                        -id      => 'export_format',
                        -name    => 'export_format',
                        -values  => $export_format_values,
                        -labels  => $export_format_labels,
                        -default => $nameserver->{export_format} || $q->param('export_format') || 'bind',
                        -onChange => "changeNSExportType(value);",
                        -required  => 'required',
                        )
                    : $export_format_labels->{ $nameserver->{export_format} },
        },
        export_serials   => {
            label => $nt_obj->help_link('export_serials') . ' Export Serials',
            value => $modifyperm
                    ? $q->checkbox(
                        -id      => 'export_serials',
                        -name    => 'export_serials',
                        -checked => $nameserver->{export_serials},
                        -value   => 1,
                        -label   => '',
                    )
                    : $nameserver->{export_serials},
        },
        logdir          => {
            label => 'Logfile Directory',
            value => $modifyperm
                    ? $q->textfield(
                        -id        => 'logdir',
                        -name      => 'logdir',
                        -size      => 60,
                        -maxlength => 255
                        )
                    : $nameserver->{logdir},
        },
        datadir         => {
            label => 'Data Directory',
            value => $modifyperm
                    ? $q->textfield(
                        -id        => 'datadir',
                        -name      => 'datadir',
                        -size      => 45,
                        -maxlength => 255
                        )
                    : $nameserver->{datadir},
        },
        export_interval => {
            label => 'Export Interval (seconds)',
            value => $modifyperm
                    ? $q->textfield(
                        -id        => 'export_interval',
                        -name      => 'export_interval',
                        -size      => 10,
                        -maxlength => 10,
                        -default   => 120,
                        )
                    : $nameserver->{export_interval},
        },
    );
};

