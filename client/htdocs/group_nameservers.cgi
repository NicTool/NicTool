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

    if ($user) {
        print $q->header;
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
    $nt_obj->display_nameserver_options( $user, $q->param('nt_group_id'), $level, 1 );

    if ( $q->param('new') ) {
        if ( $q->param('Create') ) {
            my @fields = qw/ nt_group_id name ttl description address
                            export_format logdir datadir export_interval /;
            my %data;
            foreach my $x (@fields) {
                $data{$x} = $q->param($x);
            }
            my $error = $nt_obj->new_nameserver(%data);
            if ( $error->{'error_code'} != 200 ) {
                display_edit_nameserver( $nt_obj, $user, $q, $error, 'new' );
            }
        }
        elsif ( $q->param('Cancel') ) { } # do nothing
        else {
            display_edit_nameserver( $nt_obj, $user, $q, '', 'new' );
        }
    }
    if ( $q->param('edit') ) {
        if ( $q->param('Save') ) {
            my @fields
                = qw(nt_group_id nt_nameserver_id name ttl description address export_format logdir datadir export_interval);
            my %data;
            foreach my $x (@fields) {
                $data{$x} = $q->param($x);
            }
            my $error = $nt_obj->edit_nameserver(%data);
            if ( $error->{'error_code'} != 200 ) {
                display_edit_nameserver( $nt_obj, $user, $q, $error, 'edit' );
            }
        }
        elsif ( $q->param('Cancel') ) {

            # do nothing
        }
        else {
            display_edit_nameserver( $nt_obj, $user, $q, '', 'edit' );
        }
    }

    if ( $q->param('delete') ) {
        my $error = $nt_obj->delete_nameserver(
            nt_group_id      => $q->param('nt_group_id'),
            nt_nameserver_id => $q->param('nt_nameserver_id')
        );
        if ( $error->{'error_code'} != 200 ) {
            $nt_obj->display_nice_error( $error, "Delete Nameserver" );
        }
    }

    my $group = $nt_obj->get_group( nt_group_id => $q->param('nt_group_id') );

    display_list( $nt_obj, $q, $group, $user );

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub display_list {
    my ( $nt_obj, $q, $group, $user ) = @_;

    my $cgi = 'group_nameservers.cgi';

    my $user_group = $nt_obj->get_group( nt_group_id => $user->{'nt_group_id'} );

    my @columns = qw(name description address status);
    my %labels = (
        name        => 'Name',
        description => 'Description',
        address     => 'Address',
       #export_format=> 'Export Format',
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
        print $q->endform;
        return;
    };

    $nt_obj->display_move_javascript( 'move_nameservers.cgi', 'nameserver' );

    print qq[
<form method="post" action="move_users.cgi" target="move_win" name="list_form">];
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
    $q->endform;
}

sub display_list_actions {
    my ( $q, $user, $user_group, $state, $list ) = @_;

    print qq[
<div id="nameserverListActions" class="no_pad side_mar dark_grey_bg">
 <span class="bold">Nameserver List</span>
 <span class=float_r>];

    my $gid = $q->param('nt_group_id');
    if ( $user->{'nameserver_create'} ) {
        print qq[<a href="group_nameservers.cgi?nt_group_id=${gid}${state}&amp;new=1">New Nameserver</a>];
    }
    else {
        print qq[<span class=disabled>New Nameserver</span>];
    }
    if ( @$list && $user_group->{'has_children'} ) {
        print qq[ | <a href="javascript:void open_move(document.list_form.obj_list);">Move Selected Nameservers</a>];
    };
    print qq[
 </span>
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
   <td class=center> ];

        if ( $rv->{'total'} != 1 ) {
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
   <td class="dark_bg nowrap center"> $labels->{$_} &nbsp; &nbsp; $sort_fields->{$_}->{'order'}
     <img src="$NicToolClient::image_dir/$sortdir.gif" alt="$sortdir"></td>];
        }
        else {
            print qq[
   <td class="center nowrap">$labels->{$_}</td>];
        }
    }

    print qq[
   <td class=width1></td>
  </tr>
 </thead>];
};

sub display_list_move_checkbox {
    my ( $q, $user, $user_group, $obj ) = @_;

    print qq[
  <td class="width1 center">];

        if ($user->{'nameserver_write'}
            && ( !exists $obj->{'delegate_write'} || $obj->{'delegate_write'} )) {

            if ( $user_group->{'has_children'} ) {
                print $q->checkbox(
                    -name  => 'obj_list',
                    -value => $obj->{'nt_nameserver_id'},
                    -label => '',
                );
            };
        }
        else {
            if ( $user_group->{'has_children'} ) {
                print qq[<img src="$NicToolClient::image_dir/nobox.gif" alt="nobox">];
            };
        }
        print qq[
  </td>];
};

sub display_list_subgroups {
    my ( $width, $obj, $map ) = @_;

    print qq[
  <td style="width:$width">
   <table class="no_pad">
    <tr>
     <td><img src="$NicToolClient::image_dir/group.gif" alt="group"></td>
     <td>];

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
     </td>
    </tr>
   </table>
  </td>];
}

sub display_list_name {
    my ( $obj, $width ) = @_;

    print qq[
  <td style="width:$width;">
     <a href="group_nameservers.cgi?nt_nameserver_id=$obj->{'nt_nameserver_id'}&amp;nt_group_id=$obj->{'nt_group_id'}&amp;edit=1">
      <img src="$NicToolClient::image_dir/nameserver.gif" alt="nameserver"> $obj->{'name'} </a>
  </td>];
};

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

    my $nameserver;
    my @fields = qw/ name address export_format logdir datadir
                     ttl export_interval description / ;

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
        print $q->start_form(
            -action => 'group_nameservers.cgi',
            -method => 'POST'
        );
        print $q->hidden( -name => $edit ),
            $q->hidden( -name => 'nt_group_id' ),
            $q->hidden( -name => 'nt_nameserver_id' ) if $edit ne 'new';
    }

    $nt_obj->display_nice_error($message) if $message;
    my $title;
    if ($modifyperm) {
        $title = ucfirst($edit) . " Nameserver";
    }
    else {
        $title = "View Nameserver Details";
    }

    my %labels = display_edit_nameserver_fields( $q, $nameserver, $modifyperm );

    print qq[
<table class="fat">
 <tr class=dark_bg><td colspan=2 class="bold">$title</td></tr>];

    foreach ( @fields ) {
        print qq[
 <tr class=light_grey_bg>
  <td class=right>$labels{$_}{label}:</td>
  <td class="width70">$labels{$_}{value}</td>
 </tr>];
    };

    if ($modifyperm) {
        print qq[
 <tr class=dark_grey_bg>
  <td colspan=2 class=center>],
        $q->submit( $edit eq 'edit' ? 'Save' : 'Create' ),
        $q->submit('Cancel'), "</td>
 </tr>";
    }

    print qq[
</table>];
    print $q->end_form if $modifyperm;
}

sub display_edit_nameserver_fields {
    my ( $q, $nameserver, $modifyperm ) = @_;

    my $ttl = $q->param('ttl') || $NicToolClient::default_nameserver_ttl;

    # TODO: get this from SQL.
    my %export_formats = (
        'bind'    => "BIND (ISC's Berkeley Internet Named Daemon)",
        'tinydns' => 'tinydns (part of DJBDNS)',
    );
    my $export_format_values = [ sort keys %export_formats ];
    my $export_format_labels  = \%export_formats;
    my $export_format_default = $q->param('export_format');

    return (
        name            => {
            label => 'Fully qualified nameserver name',
            value => $modifyperm
                    ? $q->textfield( -name => 'name', -size => 40, -maxlength => 127 )
                    : $nameserver->{'name'},
        },
        ttl             => {
            label => 'TTL',
            value => $modifyperm
                    ? $q->textfield(
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
                        -name      => 'description',
                        -cols      => 50,
                        -rows      => 4,
                        -maxlength => 255
                        )
                    : $nameserver->{'description'},
        },
        address         => {
            label => 'IP Address',
            value => $modifyperm
                    ? $q->textfield( -name => 'address', -size => 15, -maxlength => 15)
                    : $nameserver->{'address'},
        },
        export_format   => {
            label => 'Export Format',
            value => $modifyperm
                    ? $q->popup_menu(
                        -name    => 'export_format',
                        -values  => $export_format_values,
                        -default => $export_format_default,
                        -labels  => $export_format_labels
                        )
                    : $export_format_labels->{ $nameserver->{'export_format'} },
        },
        logdir          => {
            label => 'Logfile Directory',
            value => $modifyperm
                    ? $q->textfield(
                        -name      => 'logdir',
                        -size      => 40,
                        -maxlength => 255
                        )
                    : $nameserver->{'logdir'},
        },
        datadir         => {
            label => 'Data Directory',
            value => $modifyperm
                    ? $q->textfield(
                        -name      => 'datadir',
                        -size      => 40,
                        -maxlength => 255
                        )
                    : $nameserver->{'datadir'},
        },
        export_interval => {
            label => 'Export Interval (seconds)',
            value => $modifyperm
                    ? $q->textfield(
                        -name      => 'export_interval',
                        -size      => 10,
                        -maxlength => 10,
                        -default   => 120,
                        )
                    : $nameserver->{'export_interval'},
        },
    );
};

