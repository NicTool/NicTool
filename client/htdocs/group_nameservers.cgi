#!/usr/bin/perl
#
# $Id: group_nameservers.cgi 635 2008-09-13 04:03:07Z matt $
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

#use strict;

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

    my $level = $nt_obj->display_group_tree(
        $user,
        $user->{'nt_group_id'},
        $q->param('nt_group_id'), 0
    );
    $nt_obj->display_nameserver_options( $user, $q->param('nt_group_id'),
        $level, 1 );

    if ( $q->param('new') ) {
        if ( $q->param('Create') ) {
            my @fields
                = qw(nt_group_id name ttl description address service_type output_format logdir datadir export_interval);
            my %data;
            foreach my $x (@fields) {
                $data{$x} = $q->param($x);
            }
            my $error = $nt_obj->new_nameserver(%data);
            if ( $error->{'error_code'} != 200 ) {
                &display_edit_nameserver( $nt_obj, $user, $q, $error, 'new' );
            }
        }
        elsif ( $q->param('Cancel') ) {

            # do nothing
        }
        else {
            &display_edit_nameserver( $nt_obj, $user, $q, '', 'new' );
        }
    }
    if ( $q->param('edit') ) {
        if ( $q->param('Save') ) {
            my @fields
                = qw(nt_group_id nt_nameserver_id name ttl description address service_type output_format logdir datadir export_interval);
            my %data;
            foreach my $x (@fields) {
                $data{$x} = $q->param($x);
            }
            my $error = $nt_obj->edit_nameserver(%data);
            if ( $error->{'error_code'} != 200 ) {
                &display_edit_nameserver( $nt_obj, $user, $q, $error,
                    'edit' );
            }
        }
        elsif ( $q->param('Cancel') ) {

            # do nothing
        }
        else {
            &display_edit_nameserver( $nt_obj, $user, $q, '', 'edit' );
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

    &display_list( $nt_obj, $q, $group, $user );

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

        #        service_type    => 'Service Type',
        #        output_format   => 'Output Format',
        status     => 'Export Status',
        group_name => 'Group'
    );

    my $include_subgroups = $group->{'has_children'} ? 'sub-groups' : undef;
    if ($include_subgroups) {
        unshift( @columns, 'group_name' );
    }

    my %params = ( nt_group_id => $q->param('nt_group_id') );
    my %sort_fields;
    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields,
        100 );

    $sort_fields{'name'} = { 'order' => 1, 'mod' => 'Ascending' }
        unless %sort_fields;

    my $rv = $nt_obj->get_group_nameservers(%params);

    $nt_obj->display_sort_options( $q, \@columns, \%labels, $cgi,
        ['nt_group_id'], $include_subgroups )
        if $q->param('edit_sortorder');
    $nt_obj->display_advanced_search( $q, \@columns, \%labels, $cgi,
        ['nt_group_id'], $include_subgroups )
        if $q->param('edit_search');

    return $nt_obj->display_nice_error( $rv, "Get Group Nameservers" )
        if ( $rv->{'error_code'} != 200 );

    my $list = $rv->{'list'};
    my $map  = $rv->{'group_map'};

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print "<tr bgcolor=$NicToolClient::dark_grey><td>";
    print "<table cellpadding=0 cellspacing=0 border=0 width=100%>";
    print "<tr>";
    print "<td><b>Nameserver List</b></td>";
    print "<td align=right>";
    if ( $user->{'nameserver_create'} ) {
        print "<a href=$cgi?"
            . join( '&', @state_fields )
            . "&nt_group_id="
            . $q->param('nt_group_id')
            . "&new=1>New Nameserver</a>";
    }
    else {
        print
            "<font color=$NicToolClient::disabled_color>New Nameserver</font>";
    }
    print
        " | <a href=\"javascript:void open_move(document.list_form.obj_list);\">Move Selected Nameservers</a>"
        if ( @$list && $user_group->{'has_children'} );
    print "</td>";
    print "</tr></table></td></tr>";
    print "</table>";

    $nt_obj->display_search_rows( $q, $rv, \%params, $cgi, ['nt_group_id'],
        $include_subgroups );

    if (@$list) {
        $nt_obj->display_move_javascript( 'move_nameservers.cgi',
            'nameserver' );

        print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
        print "<tr bgcolor=$NicToolClient::dark_grey>";

        if ( $user_group->{'has_children'} ) {
            print "<td align=center>";

            print "<table cellpadding=0 cellspacing=0 border=0>";
            print "<tr><td></td>";
            print $q->endform . "\n";
            print $q->startform(
                -action => 'move_users.cgi',
                -method => 'POST',
                -name   => 'list_form',
                -target => 'move_win'
            ) . "\n";
            print "<td></td></tr>";
            print "</table>";

            print "",
                (
                $rv->{'total'} == 1 ? '&nbsp;' : $q->checkbox(
                    -name  => 'select_all_or_none',
                    -label => '',
                    -onClick =>
                        'selectAllorNone(document.list_form.obj_list, this.checked)',
                    -override => 1
                )
                ),
                "</td>";
        }

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
        print
            "<td width=1%><img src=$NicToolClient::image_dir/trash.gif></td>";
        print "</tr>";

        my $x     = 0;
        my $width = int( 100 / @columns ) . '%';

        foreach my $obj (@$list) {
            print "<tr bgcolor="
                . ( $x++ % 2 == 0 ? $NicToolClient::light_grey : 'white' )
                . ">";
            if ($user->{'nameserver_write'}
                && ( !exists $obj->{'delegate_write'}
                    || $obj->{'delegate_write'} )
                )
            {
                print "<td width=1% align=center>",
                    $q->checkbox(
                    -name  => 'obj_list',
                    -value => $obj->{'nt_nameserver_id'},
                    -label => ''
                    ),
                    "</td>"
                    if ( $user_group->{'has_children'} );
            }
            else {
                print
                    "<td width=1% align=center><img src=$NicToolClient::image_dir/nobox.gif></td>"
                    if ( $user_group->{'has_children'} );
            }

            if ($include_subgroups) {
                print
                    "<td width=$width><table cellpadding=0 cellspacing=0 border=0><tr>";
                print
                    "<td><img src=$NicToolClient::image_dir/group.gif></td>";
                if ($map) {
                    print "<td>",
                        join(
                        ' / ',
                        map("<a href=group.cgi?nt_group_id=$_->{'nt_group_id'}>$_->{'name'}</a>",
                            (   @{ $map->{ $obj->{'nt_group_id'} } },
                                {   nt_group_id => $obj->{'nt_group_id'},
                                    name        => $obj->{'group_name'}
                                }
                                ) )
                        ),
                        "</td>";
                }
                else {
                    print "<td>",
                        join(
                        ' / ',
                        map("<a href=group.cgi?nt_group_id=$_->{'nt_group_id'}>$_->{'name'}</a>",
                            (   {   nt_group_id => $obj->{'nt_group_id'},
                                    name        => $obj->{'group_name'}
                                }
                                ) )
                        ),
                        "</td>";
                }
                print "</tr></table></td>";
            }

            print
                "<td width=$width><table cellpadding=0 cellspacing=0 border=0>";
            print "<tr>";
            print
                "<td><a href=$cgi?nt_nameserver_id=$obj->{'nt_nameserver_id'}&nt_group_id=$obj->{'nt_group_id'}&edit=1><img src=$NicToolClient::image_dir/nameserver.gif border=0></a></td>";
            print
                "<td><a href=$cgi?nt_nameserver_id=$obj->{'nt_nameserver_id'}&nt_group_id=$obj->{'nt_group_id'}&edit=1>",
                $obj->{'name'}, "</a></td>";
            print "</tr></table></td>";

            foreach (qw(description address status)) {
                print "<td width=$width>",
                    ( $obj->{$_} ? $obj->{$_} : '&nbsp;' ), "</td>";
            }

            if ($user->{'nameserver_delete'}
                && ( !exists $obj->{'delegate_delete'}
                    || $obj->{'delegate_delete'} )
                )
            {
                print "<td width=1%><a href=$cgi?"
                    . join( '&', @state_fields )
                    . "&nt_group_id="
                    . $q->param('nt_group_id')
                    . "&delete=1&nt_nameserver_id=$obj->{'nt_nameserver_id'} onClick=\"return confirm('Delete nameserver $obj->{'name'}?');\"><img src=$NicToolClient::image_dir/trash.gif border=0></a></td>";
            }
            else {
                print
                    "<td width=1%><img src=$NicToolClient::image_dir/trash-disabled.gif border=0></td>";
            }
            print "</tr>";
        }

        print "</table>";
    }

    print $q->endform;
}

sub display_edit_nameserver {
    my ( $nt_obj, $user, $q, $message, $edit ) = @_;

    my $nameserver;
    if ( $q->param('nt_nameserver_id') && !$q->param('Save') )
    {    # get current settings
        $nameserver = $nt_obj->get_nameserver(
            nt_group_id      => $q->param('nt_group_id'),
            nt_nameserver_id => $q->param('nt_nameserver_id')
        );
        if ( $nameserver->{'error_code'} != 200 ) {
            $message = $nameserver;
        }
        else {
            my @fields
                = qw(nt_nameserver_id name ttl description address service_type output_format logdir datadir export_interval);
            foreach (@fields) {
                $q->param( $_, $nameserver->{$_} );
            }
        }
    }
    my $modifyperm
        = $user->{'nameserver_write'}
        && ( !exists $nameserver->{'delegate_write'}
        || $nameserver->{'delegate_write'} );
    my $service_type_values  = [ sort keys %{ $nt_obj->ns_service_types() } ];
    my $service_type_labels  = $nt_obj->ns_service_types();
    my $service_type_default = $q->param('service_type');

    my $output_format_values
        = [ sort keys %{ $nt_obj->ns_output_formats() } ];
    my $output_format_labels  = $nt_obj->ns_output_formats();
    my $output_format_default = $q->param('output_format');

    my $ttl;
    $ttl = $q->param('ttl') || $NicToolClient::default_nameserver_ttl;
    if ($modifyperm) {
        print $q->start_form(
            -action => 'group_nameservers.cgi',
            -method => 'POST'
        );
        print $q->hidden( -name => $edit );
        print $q->hidden( -name => 'nt_group_id' );
        print $q->hidden( -name => 'nt_nameserver_id' ) if $edit ne 'new';
    }

 #print "<center><font color=red><b>$message</b></font></center>" if $message;
    $nt_obj->display_nice_error($message) if $message;
    my $title;
    if ($modifyperm) {
        $title = ucfirst($edit) . " Nameserver";
    }
    else {
        $title = "View Nameserver Details";
    }
    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print
        "<tr bgcolor=$NicToolClient::dark_color><td colspan=2><font color=white><b>$title</b></font></td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Fully qualfied nameserver name:</td>";
    print "<td width=80%>",
        (
          $modifyperm
        ? $q->textfield( -name => 'name', -size => 40, -maxlength => 127 )
        : $nameserver->{'name'}
        ),
        "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "IP Address:</td>";
    print "<td width=80%>",
        (
        $modifyperm
        ? $q->textfield(
            -name      => 'address',
            -size      => 15,
            -maxlength => 15
            )
        : $nameserver->{'address'}
        ),
        "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Service Type:</td>";
    print "<td width=80%>\n",
        (
        $modifyperm
        ? $q->popup_menu(
            -name    => 'service_type',
            -values  => $service_type_values,
            -default => $service_type_default,
            -labels  => $service_type_labels
            )
        : $service_type_labels->{ $nameserver->{'service_type'} }
        ),
        "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Output Format:</td>";
    print "<td width=80%>\n",
        (
        $modifyperm
        ? $q->popup_menu(
            -name    => 'output_format',
            -values  => $output_format_values,
            -default => $output_format_default,
            -labels  => $output_format_labels
            )
        : $output_format_labels->{ $nameserver->{'output_format'} }
        ),
        "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Logfile Directory:</td>";
    print "<td width=80%>",
        (
        $modifyperm
        ? $q->textfield(
            -name      => 'logdir',
            -size      => 40,
            -maxlength => 255
            )
        : $nameserver->{'logdir'}
        ),
        "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Datafile Directory:</td>";
    print "<td width=80%>",
        (
        $modifyperm
        ? $q->textfield(
            -name      => 'datadir',
            -size      => 40,
            -maxlength => 255
            )
        : $nameserver->{'datadir'}
        ),
        "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "TTL:</td>";
    print "<td width=80%>",
        (
        $modifyperm
        ? $q->textfield(
            -name      => 'ttl',
            -size      => 10,
            -maxlength => 10,
            -default   => $ttl
            )
        : $nameserver->{'ttl'}
        ),
        "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Export Interval (seconds):</td>";
    print "<td width=80%>",
        (
        $modifyperm
        ? $q->textfield(
            -name      => 'export_interval',
            -size      => 10,
            -maxlength => 10,
            -default   => $ttl
            )
        : $nameserver->{'export_interval'}
        ),
        "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Description:</td>";
    print "<td width=80%>",
        (
        $modifyperm
        ? $q->textarea(
            -name      => 'description',
            -cols      => 50,
            -rows      => 4,
            -maxlength => 255
            )
        : $nameserver->{'description'}
        ),
        "</td></tr>";

    if ($modifyperm) {
        print
            "<tr bgcolor=$NicToolClient::dark_grey><td colspan=2 align=center>",
            $q->submit( $edit eq 'edit' ? 'Save' : 'Create' ),
            $q->submit('Cancel'), "</td></tr>";
    }
    print "</table>";
    print $q->end_form if $modifyperm;
}

