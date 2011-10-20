#!/usr/bin/perl
#
# $Id: group_zones.cgi 635 2008-09-13 04:03:07Z matt $
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
        &display( $nt_obj, $q, $user );
    }
}

sub display {
    my ( $nt_obj, $q, $user ) = @_;
    my @nicemessage;
    my @newzone;

    if ( $q->param('new') ) {
        if ( $q->param('Cancel') ) {

            # do nothing
        }
        elsif ( $q->param('Create') ) {
            my @fields
                = qw(nt_group_id zone nameservers description serial refresh retry expire minimum mailaddr template ttl);
            my %data;
            foreach (@fields) { $data{$_} = $q->param($_); }
            $data{'nameservers'} = join( ',', $q->param('nameservers') );

            my $error = $nt_obj->new_zone(%data);
            if ( $error->{'error_code'} != 200 ) {
                @newzone = ( $nt_obj, $q, $error, 'new' );
            }
            else {

                # do the template stuff here
                my $nt_zone_id   = $error->{'nt_zone_id'};
                my $zone_records = $nt_obj->zone_record_template(
                    {   zone       => $q->param('zone'),
                        nt_zone_id => $nt_zone_id,
                        template   => $q->param('template'),
                        newip      => $q->param('newip'),
                        mailip     => $q->param('mailip'),
                        debug      => $q->param('debug')
                    }
                );
                add_zone_records( $nt_obj, $zone_records );

                # end template additions

                if ($NicToolClient::edit_after_new_zone) {
                    $q->param( -name => 'object', -value => 'zone' );
                    $q->param(
                        -name  => 'obj_id',
                        -value => $error->{'nt_zone_id'}
                    );
                    $nt_obj->redirect_from_log($q);
                    return;
                }

                $q->param(
                    -name  => 'new_zone_id',
                    -value => $error->{'nt_zone_id'}
                );
                @nicemessage = (
                    "The Zone '$data{'zone'}' was successfully created.",
                    "Zone Created"
                );
            }
        }
        else {
            @newzone = ( $nt_obj, $q, '', 'new' );
        }
    }

    print $q->header;
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

    $nt_obj->display_zone_list_options( $user, $q->param('nt_group_id'),
        $level, 1 );

    my $group = $nt_obj->get_group(
        nt_group_id  => $q->param('nt_group_id'),
    );

    if ( $q->param('new') ) {
        $nt_obj->nice_message(@nicemessage) if @nicemessage;
        &new_zone(@newzone) if @newzone;
    }
    if ( $q->param('edit') ) {
        if ( $q->param('Save') ) {
            my @fields
                = qw(nt_zone_id nt_group_id zone nameservers description serial refresh retry expire minimum mailaddr ttl);
            my %data;
            foreach (@fields) { $data{$_} = $q->param($_); }
            $data{'nameservers'} = join( ',', $q->param('nameservers') );

            my $error = $nt_obj->edit_zone(%data);
            if ( $error->{'error_code'} != 200 ) {
                &new_zone( $nt_obj, $q, $error, 'edit' );
            }
        }
        elsif ( $q->param('Cancel') ) {

            # do nothing
        }
        else {
            &new_zone( $nt_obj, $q, '', 'edit' );
        }
    }

    if ( $q->param('delete') && $q->param('zone_list') ) {
        my @zl = $q->param('zone_list');
        my $error = $nt_obj->delete_zones( zone_list => join( ',', @zl ) );
        my $plural;
        $plural = 's' if scalar @zl > 1;
        if ( $error->{'error_code'} != 200 ) {
            $nt_obj->display_nice_error( $error, "Delete Zones" );
        }
        else {
            $nt_obj->display_nice_message(
                "The "
                    . ( $plural ? "zones were" : "zone was" )
                    . " successfully removed.",
                "Zone$plural Removed"
            );
        }
    }
    if (   $q->param('deletedelegate')
        && $q->param('nt_zone_id')
        && $q->param('nt_group_id') )
    {
        my $error = $nt_obj->delete_zone_delegation(
            nt_zone_id  => $q->param('nt_zone_id'),
            nt_group_id => $q->param('nt_group_id')
        );
        if ( $error->{'error_code'} != 200 ) {
            $nt_obj->display_nice_error( $error, "Remove Zone Delegation" );
        }
        else {
            $nt_obj->display_nice_message(
                "The zone delegation was successfully removed.",
                "Delegation Removed" );
        }
    }

    &display_list( $nt_obj, $q, $group, $user );

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub display_list {
    my ( $nt_obj, $q, $group, $user ) = @_;

    my $user_group = $nt_obj->get_group(
        nt_group_id  => $user->{'nt_group_id'},
    );

    my @columns = qw(description);

    my %labels = (
        zone        => 'Zone',
        group_name  => 'Group',
        description => 'Description',
        records     => '*Resource Records'
    );

    my $include_subgroups = $group->{'has_children'} ? 'sub-groups' : undef;
    if ($include_subgroups) {
        unshift( @columns, 'group_name' );
    }
    unshift( @columns, 'zone' );

    my %params = ( nt_group_id => $q->param('nt_group_id') );
    my %sort_fields;
    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields,
        100 );

    $sort_fields{'zone'} = { 'order' => 1, 'mod' => 'Ascending' }
        unless %sort_fields;

    my $rv = $nt_obj->get_group_zones(%params);

    $nt_obj->display_sort_options( $q, \@columns, \%labels, 'group_zones.cgi',
        ['nt_group_id'], $include_subgroups )
        if $q->param('edit_sortorder');
    $nt_obj->display_advanced_search( $q, \@columns, \%labels,
        'group_zones.cgi', ['nt_group_id'], $include_subgroups )
        if $q->param('edit_search');

    return $nt_obj->display_nice_error( $rv, "Get Group Zones" )
        if ( $rv->{'error_code'} != 200 );

    my $zones = $rv->{'zones'};
    my $map   = $rv->{'group_map'};

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }
    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print "<tr bgcolor=$NicToolClient::dark_grey><td>";
    print "<table cellpadding=0 cellspacing=0 border=0 width=100%>";
    print "<tr>";
    print "<td><b>Zone List</b></td>";
    print "<td align=right>";
    if ( $nt_obj->no_gui_hints || $user->{"zone_create"} ) {
        print "<a href=group_zones.cgi?"
            . join( '&', @state_fields )
            . "&nt_group_id="
            . $q->param('nt_group_id')
            . "&new=1>New Zone</a>";
    }
    else {
        print "<font color=$NicToolClient::disabled_color>New Zone</font>";
    }
    print
        " | <a href=\"javascript:void open_move(document.list_form.obj_list);\">Move Selected Zones</a>"
        if ( @$zones && $user_group->{'has_children'} );
    print
        " | <a href=\"javascript:void open_delegate(document.list_form.obj_list);\">Delegate Selected Zones</a>"
        if ( @$zones
        && $user_group->{'has_children'}
        && $user->{'zone_delegate'} );

#if($user->{'zone_delegate'}&&(!exists $zone->{'delegate_delegate'} || $zone->{'delegate_delegate'})){
#print " | <a href=\"javascript:void open_delegate(document.list_form.obj_list);\">Delegate Selected Zones</a>" if( @$zones && $user_group->{'has_children'} ) ;
#}else{
#print " | <font color=$NicToolClient::disabled_color>Delegate Selected Zones</font>" if( @$zones && $user_group->{'has_children'} ) ;
#}
    print " | <a href=group_zones_log.cgi?nt_group_id=",
        $q->param('nt_group_id'), ">View Zone Log</a>";
    print "</td>";
    print "</tr></table></td></tr>";
    print "</table>";

    $nt_obj->display_search_rows( $q, $rv, \%params, 'group_zones.cgi',
        ['nt_group_id'], $include_subgroups );

    if (@$zones) {
        $nt_obj->display_move_javascript( 'move_zones.cgi', 'zone' );
        $nt_obj->display_delegate_javascript( 'delegate_zones.cgi', 'zone' );

        print qq{
        <table cellpadding=2 cellspacing=2 border=0 width=100%>
            <tr bgcolor=$NicToolClient::dark_grey>};

        if ( $user_group->{'has_children'} ) {
            print qq{
                <td align=center>
		            <table cellpadding=0 cellspacing=0 border=0>
		                <tr>
                            <td></td>
                                };
            print $q->endform . "\n";
            print $q->startform(
                -action => 'move_zones.cgi',
                -method => 'POST',
                -name   => 'list_form',
                -target => 'move_win'
            );
            print qq{
                            <td></td>
                        </tr>
                    </table>
		           }
                . (
                $rv->{'total'} == 1 ? '&nbsp;' : $q->checkbox(
                    -name  => 'select_all_or_none',
                    -label => '',
                    -onClick =>
                        'selectAllorNone(document.list_form.obj_list, this.checked);',
                    -override => 1
                )
                ) . "</td>";
        }

        foreach (@columns) {
            if ( $sort_fields{$_} ) {
                print qq{
    <td bgcolor=$NicToolClient::dark_color align=center>
        <table cellpadding=0 cellspacing=0 border=0>
            <tr>
                <td><font color=white>} . $labels{$_} . qq{</font></td>
                <td>&nbsp; &nbsp; <font color=white>}
                    . $sort_fields{$_}->{'order'}
                    . qq{</font></td>
                <td><img src=$NicToolClient::image_dir/}
                    . (
                    uc( $sort_fields{$_}->{'mod'} ) eq 'ASCENDING'
                    ? 'up.gif'
                    : 'down.gif' )
                    . qq{></tD>
            </tr>
        </table>
    </td>};

            }
            else {
                print qq{
                <td align=center>} . $labels{$_} . qq{</td>};
            }
        }
        print qq{
                <td align=center width=1%><img src=$NicToolClient::image_dir/delegate.gif></td>
                <td width=1%><img src=$NicToolClient::image_dir/trash.gif></td>
            </tr>};

        my $x     = 0;
        my $width = int( 100 / @columns ) . '%';
        my $bgcolor;
        my $hilite;
        foreach my $zone (@$zones) {
            $bgcolor
                = ( $x++ % 2 == 0 ? $NicToolClient::light_grey : 'white' );
            $hilite
                = ( $x % 2 == 0
                ? $NicToolClient::light_hilite
                : $NicToolClient::dark_hilite );
            $bgcolor = $hilite
                if ($zone->{'nt_zone_id'} eq $q->param('new_zone_id')
                and $NicToolClient::hilite_new_zones );
            my $isdelegate = exists $zone->{'delegated_by_id'};
            print qq{
            <tr bgcolor=$bgcolor>};
            if ( $user->{'zone_create'} && !$isdelegate ) {
                print qq{
                <td width=1% align=center>}
                    . $q->checkbox(
                    -name  => 'obj_list',
                    -value => $zone->{'nt_zone_id'},
                    -label => ''
                    )
                    . qq{</td>}
                    if ( $user_group->{'has_children'} );
            }
            else {

#print "<td width=1% align=center><img src=$NicToolClient::image_dir/perm-unchecked.gif></td>" if( $user_group->{'has_children'} );
                print
                    "<td width=1% align=center><img src=$NicToolClient::image_dir/nobox.gif></td>"
                    if ( $user_group->{'has_children'} );

#print qq{ <td width=1% align=center>&nbsp;</td>} if( $user_group->{'has_children'} );
            }

            #$bgcolor = $hilite if $zone->{'pseudo'};
            print qq{
                <td width=$width bgcolor=$bgcolor>
                    <table cellpadding=0 cellspacing=0 border=0>
                        <tr>};
            if ( !$isdelegate ) {
                print qq{
                            <td><a href=zone.cgi?nt_zone_id=}
                    . "$zone->{'nt_zone_id'}&nt_group_id=$zone->{'nt_group_id'}><img src=$NicToolClient::image_dir/zone.gif border=0></a></td>
                            <td><a href=zone.cgi?nt_zone_id="
                    . "$zone->{'nt_zone_id'}&nt_group_id=$zone->{'nt_group_id'}>$zone->{'zone'}</a>";
            }
            else {
                my $img = "zone"
                    . ( $zone->{'pseudo'} ? '-pseudo' : '-delegated' );
                print qq(
                            <td>
                            <a href=zone.cgi?nt_zone_id=$zone->{'nt_zone_id'}&nt_group_id=)
                    . $q->param('nt_group_id')
                    . qq(><img src=$NicToolClient::image_dir/$img.gif border=0></a></td>
                            <td><a href=zone.cgi?nt_zone_id=$zone->{'nt_zone_id'}&nt_group_id=)
                    . $q->param('nt_group_id')
                    . qq(> $zone->{'zone'}</a>);
                if ( $zone->{'pseudo'} ) {
                    print
                        "&nbsp; <font color=$NicToolClient::disabled_color>("
                        . $zone->{'delegated_records'}
                        . " record"
                        . ( $zone->{'delegated_records'} gt 1 ? 's' : '' )
                        . ")";
                }
                else {
                    print "&nbsp; <img src=$NicToolClient::image_dir/perm-"
                        . ( $zone->{'delegate_write'}
                        ? "write.gif"
                        : "nowrite.gif" )
                        . "></font>";
                }
            }
            print qq{
                            </td>
                        </tr>
                    </table>
                </td>};

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
                            (   @{ $map->{ $zone->{'nt_group_id'} } },
                                {   nt_group_id => $zone->{'nt_group_id'},
                                    name        => $zone->{'group_name'}
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
                            (   {   nt_group_id => $zone->{'nt_group_id'},
                                    name        => $zone->{'group_name'}
                                }
                                ) )
                        ),
                        "</td>";
                }
                print "</tr></table></td>";
            }

            print "<td width=$width>",
                (
                $zone->{'description'} ? $zone->{'description'} : '&nbsp;' ),
                "</td>";

            if (   $nt_obj->no_gui_hints
                || $user_group->{'has_children'}
                && $user->{'zone_delegate'}
                && ( $isdelegate ? $zone->{'delegate_delegate'} : 1 ) )
            {
                print
                    "<td align=center><a href=\"javascript:void window.open('delegate_zones.cgi?obj_list=$zone->{'nt_zone_id'}', 'delegate_win', 'width=640,height=480,scrollbars,resizable=yes')\"><img src=$NicToolClient::image_dir/delegate.gif border=0 alt='Delegate Zone'></a></td>";
            }
            else {
                print
                    "<td align=center><img src=$NicToolClient::image_dir/delegate-disabled.gif border=0></td>";
            }
            if ( ( $nt_obj->no_gui_hints || $user->{'zone_delete'} )
                && !$isdelegate )
            {
                print "<td width=1%><a href=group_zones.cgi?"
                    . join( '&', @state_fields )
                    . "&nt_group_id="
                    . $q->param('nt_group_id')
                    . "&delete=1&zone_list=$zone->{'nt_zone_id'} onClick=\"return confirm('Delete $zone->{'zone'} and associated resource records?');\"><img src=$NicToolClient::image_dir/trash.gif border=0></a></td>";
            }
            elsif (
                (      $nt_obj->no_gui_hints
                    || $user->{'zone_delegate'} && $zone->{'delegate_delete'}
                )
                && $isdelegate
                )
            {
                print "<td width=1%><a href=group_zones.cgi?"
                    . join( '&', @state_fields )
                    . "&nt_group_id="
                    . $q->param('nt_group_id')
                    . "&deletedelegate=1&nt_zone_id=$zone->{'nt_zone_id'} onClick=\"return confirm('Remove delegation of $zone->{'zone'}?');\"><img src=$NicToolClient::image_dir/trash-delegate.gif border=0 alt=\"Remove Zone Delegation\"></a></td>";
            }
            elsif ($isdelegate) {
                print
                    "<td width=1%><img src=$NicToolClient::image_dir/trash-delegate-disabled.gif border=0></td>";
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

sub new_zone {
    my ( $nt_obj, $q, $message, $edit ) = @_;

    print $q->start_form(
        -action => 'group_zones.cgi',
        -method => 'POST',
        -name   => 'new_zone'
    );
    print $q->hidden( -name => 'nt_group_id' );
    print $q->hidden( -name => $edit );

    foreach ( @{ $nt_obj->paging_fields() } ) {
        print $q->hidden( -name => $_ ) if ( $q->param($_) );
    }

    $nt_obj->display_nice_error( $message, ucfirst($edit) . " Zone" )
        if $message;

 #print "<center><font color=red><b>$message</b></font></center>" if $message;

    print "<table cellpadding=2 cellspacing=2 border=0 width=100%>";
    print
        "<tr bgcolor=$NicToolClient::dark_color><td colspan=2><font color=white><b>New Zone</b></font></td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Zone:</td>";
    print "<td width=100%>",
        $q->textfield( -name => 'zone', -size => 40, -maxlength => 128 ),
        " <a href=\"zones.cgi?nt_group_id="
        . $q->param('nt_group_id')
        . "\">Batch</a></td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right valign=top>", "Nameservers:</td>";
    print "<td width=80%>\n";

    # get list of available nameservers
    my $ns_tree = $nt_obj->get_usable_nameservers(
        nt_group_id      => $q->param('nt_group_id'),
        include_for_user => 1
    );
    foreach ( 1 .. scalar( @{ $ns_tree->{'nameservers'} } ) ) {
        last if ( $_ > 10 );

        my $ns = $ns_tree->{'nameservers'}->[ $_ - 1 ];

        print $q->checkbox(
            -name    => "nameservers",
            -checked => ( $_ < 4 ? 1 : 0 ),
            -value   => $ns->{'nt_nameserver_id'},
            -label   => "$ns->{'description'} ($ns->{'name'})"
            ),
            "<BR>";
    }
    if ( @{ $ns_tree->{'nameservers'} } == 0 ) {
        print "No available nameservers.";
    }
    print "</td></tr>\n";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right valign=top>", "Description:</td>";
    print "<td width=80%>",
        $q->textarea(
        -name      => 'description',
        -cols      => 50,
        -rows      => 4,
        -maxlength => 255
        ),
        "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "TTL:</td>";
    my $ttl = $NicToolClient::default_zone_ttl || $q->param('ttl');
    print "<td width=80%>",
        $q->textfield(
        -name      => 'ttl',
        -size      => 8,
        -maxlength => 10,
        -default   => $ttl
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.ttl.value=$NicToolClient::default_zone_ttl\">",
        " $NicToolClient::default_zone_ttl";
    print "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Refresh:</td>";
    my $refresh = $NicToolClient::default_zone_refresh
        || $q->param('refresh');
    print "<td width=80%>",
        $q->textfield(
        -name      => 'refresh',
        -size      => 8,
        -maxlength => 10,
        -default   => $refresh
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.refresh.value=$NicToolClient::default_zone_refresh\">",
        " $NicToolClient::default_zone_refresh";
    print "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Retry:</td>";
    my $retry = $NicToolClient::default_zone_retry || $q->param('retry');
    print "<td width=80%>",
        $q->textfield(
        -name      => 'retry',
        -size      => 8,
        -maxlength => 10,
        -default   => $retry
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.retry.value=$NicToolClient::default_zone_retry\">",
        " $NicToolClient::default_zone_retry";
    print "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Expire:</td>";
    my $expire = $NicToolClient::default_zone_expire || $q->param('expire');
    print "<td width=80%>",
        $q->textfield(
        -name      => 'expire',
        -size      => 8,
        -maxlength => 10,
        -default   => $expire
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.expire.value=$NicToolClient::default_zone_expire\">",
        " $NicToolClient::default_zone_expire";
    print "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "Minimum:</td>";
    my $minimum = $NicToolClient::default_zone_minimum
        || $q->param('minimum');
    print "<td width=80%>",
        $q->textfield(
        -name      => 'minimum',
        -size      => 8,
        -maxlength => 10,
        -default   => $minimum
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.minimum.value=$NicToolClient::default_zone_minimum\">",
        " $NicToolClient::default_zone_minimum";
    print "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>", "MailAddr:</td>";
    my $mailaddr = $NicToolClient::default_zone_mailaddr
        || $q->param('mailaddr');
    print "<td width=80%>",
        $q->textfield(
        -name      => 'mailaddr',
        -size      => 25,
        -maxlength => 255,
        -default   => $mailaddr
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.mailaddr.value='hostmaster.'+this.form.zone.value+'.'\">",
        " $NicToolClient::default_zone_mailaddr";
    print "</td></tr>";

    print "<tr bgcolor=$NicToolClient::light_grey>";
    print "<td align=right>",
        "<a href=\"javascript:void window.open('templates.cgi', 'templates_win', 'width=640,height=580,scrollbars,resizable=yes')\">Template:</a></td>";
    my @templates = $nt_obj->zone_record_template_list;
    print "<td width=80%>",
        $q->popup_menu(
        -name    => 'template',
        -values  => \@templates,
        -default => 'none'
        );
    my $ip = $q->param('newip') || "IP Address";
    print
        " IP: <input type=\"text\" name=\"newip\" size=\"17\" maxlength=\"15\" value=\"$ip\", onFocus=\"if(this.value=='IP Address')this.value='';\"> ";
    print
        " Mail IP: <input type=\"text\" name=\"mailip\" size=\"17\" maxlength=\"15\">";
    print "</td></tr>";

    print "<tr bgcolor=$NicToolClient::dark_grey><td colspan=2 align=center>",
        $q->submit( $edit eq 'edit' ? 'Save' : 'Create' ),
        $q->submit('Cancel'), "</td></tr>";
    print "</table>";
    print $q->end_form;
}

sub add_zone_records {
    my ( $nt, $recs, $debug ) = @_;

    if ( $recs && scalar( @{$recs} ) > 0 ) {
        for ( my $i = 0; $i < scalar( @{$recs} ); $i++ ) {
            my %zone_record = (
                nt_zone_id  => $recs->[$i]->{'nt_zone_id'},
                name        => $recs->[$i]->{'name'},
                ttl         => "3600",
                description => "batch added",
                type        => $recs->[$i]->{'type'},
                address     => $recs->[$i]->{'address'},
                weight      => $recs->[$i]->{'weight'},
                priority    => $recs->[$i]->{'priority'},
                other       => $recs->[$i]->{'other'},
            );
            if ($debug) {

#print "add_zone_records: $recs->[$i]->{'nt_zone_id'}, $recs->[$i]->{'name'}, ";
#print "$recs->[$i]->{'type'}, $recs->[$i]->{'address'}, $recs->[$i]->{'weight'}\n";
#                print Data::Dumper::Dumper(%zone_record);
            }
            my $r = $nt->new_zone_record(%zone_record);
            if ( $r->{'error_code'} ne "200" ) {
                print
                    "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n";
                print Data::Dumper::Dumper($r);
            }
        }
    }
    else {

     # don't output anything here, we haven't returned the HTML header yet!
     #       print "We didn't get any records back from the zone template!\n";
    }
}

