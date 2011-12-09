#!/usr/bin/perl
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01+ Copyright 2004-2008 The Network People, Inc.
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

    if ( defined $q->param('nt_zone_record_id') ) {

 # I'm not crazy about running off and doing DB queries this early, especially
 # since we'll be doing them again later, but in order to display the dynamic
 # form with the proper fields, we really must use onLoad which is only
 # avalaible in the body tag. --mps (2/24/2007)
        my $zone_record = $nt_obj->get_zone_record(
            nt_zone_record_id => $q->param('nt_zone_record_id') );

        #       warn Data::Dumper::Dumper $zone_record;
        my $rr_type = $zone_record->{'type'};
        $nt_obj->parse_template( $NicToolClient::start_html_template,
            ONLOAD_JS => "showFieldsForRRtype(\'$rr_type\')" );
    }
    else {
        $nt_obj->parse_template($NicToolClient::start_html_template);
    }
    $nt_obj->parse_template(
        $NicToolClient::body_frame_start_template,
        username  => $user->{'username'},
        groupname => $user->{'groupname'},
        userid    => $user->{'nt_user_id'},
    );

    my $zone = $nt_obj->get_zone( nt_zone_id => $q->param('nt_zone_id') );

    my $level = $nt_obj->display_group_tree(
        $user,
        $user->{'nt_group_id'},
        $zone->{'delegated_by_id'} ? '' : $q->param('nt_group_id'), 0
    );

    if ( $zone->{'error_code'} ne 200 ) {
        $nt_obj->display_nice_error( $zone, "Get Zone" );
        return;
    }

    $nt_obj->display_zone_list_options( $user, $q->param('nt_group_id'),
        $level, 0 );
    $nt_obj->display_zone_options( $user, $zone, $level + 1, 0 );    #1);

    $zone = &display_properties( $nt_obj, $user, $q, $zone );
    &display_nameservers( $nt_obj, $user, $q, $zone );
    &display_zone_records( $nt_obj, $user, $q, $zone );

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub display_properties {
    my ( $nt_obj, $user, $q, $zone ) = @_;
    my $isdelegate = exists $zone->{'delegated_by_id'};
    if ( $q->param('edit_zone') ) {
        if ( $q->param('Save') ) {
            my @fields
                = qw(nt_zone_id nt_group_id zone nameservers description mailaddr serial refresh retry expire ttl minimum);
            my %data;
            foreach (@fields) { $data{$_} = $q->param($_); }
            $data{'nameservers'} = join( ',', $q->param('nameservers') );
            $data{'deleted'} = 0 if $q->param('undelete');

            #warn "nameservers: ".$data{'nameservers'};
            #warn "data: ".join(":",map {$_."=".$data{$_}} keys %data);
            my $error = $nt_obj->edit_zone(%data);
            if ( $error->{'error_code'} != 200 ) {
                &display_edit_zone( $nt_obj, $user, $q, $error, $zone,
                    'edit' );
            }
            else {
                $zone = $nt_obj->get_zone(
                    nt_group_id => $q->param('nt_group_id'),
                    nt_zone_id  => $q->param('nt_zone_id')
                );
            }
        }
        elsif ( $q->param('Cancel') ) {

        }
        else {
            &display_edit_zone( $nt_obj, $user, $q, '', $zone, 'edit' );
        }
    }
    if ( $q->param('new_zone') ) {
        if ( $q->param('Create') ) {
            my @fields
                = qw(nt_group_id zone nameservers description mailaddr serial refresh retry expire ttl minimum);
            my %data;
            foreach (@fields) { $data{$_} = $q->param($_); }
            $data{'nameservers'} = join( ',', $q->param('nameservers') );

            #warn "nameservers: ".$data{'nameservers'};
            #warn "data: ".join(":",map {$_."=".$data{$_}} keys %data);
            my $error = $nt_obj->new_zone(%data);
            if ( $error->{'error_code'} != 200 ) {
                &display_edit_zone( $nt_obj, $user, $q, $error, $zone,
                    'new' );
            }
            else {
                if ($NicToolClient::edit_after_new_zone) {
                    $q->param( -name => 'object', -value => 'zone' );
                    $q->param(
                        -name  => 'obj_id',
                        -value => $error->{'nt_zone_id'}
                    );
                    return $nt_obj->redirect_from_log($q);
                }
                $zone = $nt_obj->get_zone(
                    nt_group_id => $q->param('nt_group_id'),
                    nt_zone_id  => $error->{'nt_zone_id'}
                );
                if ( $zone->{'error_code'} != 200 ) {
                    $nt_obj->display_nice_error( $zone, "Get Zone" );
                }

            }
        }
        elsif ( $q->param('Cancel') ) {

        }
        else {
            &display_edit_zone( $nt_obj, $user, $q, '', $zone, 'new' );
        }
    }

    if (   $q->param('deletedelegate')
        && $q->param('type') ne 'record'
        && $q->param('nt_zone_id')
        && $q->param('delegate_group_id') )
    {
        my $error = $nt_obj->delete_zone_delegation(
            nt_zone_id  => $q->param('nt_zone_id'),
            nt_group_id => $q->param('delegate_group_id')
        );
        if ( $error->{'error_code'} != 200 ) {
            $nt_obj->display_nice_error( $error, "Delete Zone Delegation" );
        }
        else {
            $nt_obj->display_nice_message(
                "The zone delegation was successfully removed.",
                "Delegation Removed" );
        }
    }
    elsif ($q->param('deletedelegate')
        && $q->param('type') eq 'record'
        && $q->param('nt_zone_record_id')
        && $q->param('delegate_group_id') )
    {
        my $error = $nt_obj->delete_zone_record_delegation(
            nt_zone_record_id => $q->param('nt_zone_record_id'),
            nt_group_id       => $q->param('delegate_group_id')
        );
        if ( $error->{'error_code'} != 200 ) {
            $nt_obj->display_nice_error( $error,
                "Delete Zone Record Delegation" );
        }
        else {
            $nt_obj->display_nice_message(
                "The resource record delegation was successfully removed.",
                "Delegation Removed" );
        }
    }
    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

    if ( $zone->{'deleted'} ) {
        print qq( 
        <table class="fat">
        <tr class=dark_grey_bg>
            <td>
                <table class="fat">
                <tr class=light_hilite_bg>
                    <td class="nowrap" colspan=2> This zone may not be modified because it is deleted.
                    </td></tr>
                </table>
            </td>
        </tr>
        </table>
                );

    }

    #show delegation information if has been delegated to you
    if ($isdelegate) {
        print qq[<table class="fat">
<tr class=dark_grey_bg><td><table class="no_pad fat">
<tr>
<td><b>Delegation</b></td>
</tr></table>
</td></tr></table>
<table cellspacing=0 class="fat">
<tr>
<td valign=top>
<table class="fat">];

        if ( !$zone->{'pseudo'} ) {
            print qq[
<tr class=light_grey_bg>
	<td class="nowrap"> Delegated by: </td>
	<td class="fat">
 	 <table>
		<tr><td valign=center><img src=$NicToolClient::image_dir/user.gif></td>
			<td valign=center> $zone->{'delegated_by_name'}</td>
		</tr>
	</table>
 </td>
</tr>];
        }
        else {
            print qq[
<tr class=light_hilite_bg>
 <td class="nowrap" colspan=2> This zone is visible because some of its records have been delegated to you.</td>
  </tr>];

        }

        print qq[
<tr class=light_grey_bg>
 <td class="nowrap"> Belonging to group: </td>
 <td class="fat">
	<table>
		<tr>
			<td valign=center><img src=$NicToolClient::image_dir/group.gif></td>
			<td valign=center> $zone->{'group_name'}</td>
		</tr>
	</table>
 </td>
</tr>];

        #print "</td><td width=50% valign=top>";
        if ( !$zone->{'pseudo'} ) {
            print qq(
            <tr class=light_grey_bg>
                <td class="nowrap"> With Permissions: </td>
                <td class="fat">
                    <table> <tr class=light_grey_bg>);
            my %perms = (
                'write'          => "Write",
                'delete'         => "Remove Delegation",
                'delegate'       => "Re-delegate",
                'add_records'    => "Add Records",
                'delete_records' => "Delete Records"
            );
            foreach (qw(write delete delegate add_records delete_records)) {
                print "<td>";

                print "<img src=$NicToolClient::image_dir/perm-"
                    . (
                    $zone->{"delegate_$_"} ? "checked.gif" : "unchecked.gif" )
                    . ">&nbsp;"
                    . $perms{$_};
                print "</td>";
            }
            print "</tr></table>";
            print "</td></tr>";
        }
        print "</table>";
        print "</td></tr></table>";

    }
    else {
        my $delegates = $nt_obj->get_zone_delegates(
            nt_zone_id => $zone->{nt_zone_id} );
        if ( $delegates->{error_code} ne 200 ) {
            warn "error get_zone_delegates: "
                . $delegates->{'error_code'} . " "
                . $delegates->{'error_msg'};
        }
        elsif ( @{ $delegates->{'delegates'} } gt 0 ) {
            print qq{
<table class="fat">
<tr class=dark_grey_bg>
<td>
<table class="no_pad fat">
<tr>
<td><b>Zone Delegates</b></td>
</tr>
</table>
</td>
</tr>
</table>

<table cellspacing=0 class="fat">
<tr>
<td valign=top>
<table class="fat">
<tr class=light_grey_bg>
<td class="nowrap"> Delegated To Group</td>
<td class="nowrap"> Delegated By</td>
<td class="nowrap"> Access Permissions}
. $nt_obj->help_link('delperms') . qq{</td>
<td class="nowrap" width=1%> Edit</td>
<td class="nowrap" width=1% align=center><img src=$NicToolClient::image_dir/trash-delegate.gif></td>
</tr>
            };
            foreach my $del ( @{ $delegates->{'delegates'} } ) {
                print qq[
<tr class=light_grey_bg>
 <td class="nowrap center">
  <table><tr>
   <td valign=center><a href=group.cgi?nt_group_id=$del->{'nt_group_id'}><img src=$NicToolClient::image_dir/group.gif></a></td>
   <td valign=center><a href=group.cgi?nt_group_id=$del->{'nt_group_id'}>$del->{'group_name'}</a></td>
  </tr>
  </table>
 </td>
 <td class="nowrap center">
  <table><tr>
    <td valign=center><a href=user.cgi?nt_user_id=$del->{'delegated_by_id'}><img src=$NicToolClient::image_dir/user.gif></a></td>
    <td valign=center><a href=user.cgi?nt_user_id=$del->{'delegated_by_id'}>$del->{'delegated_by_name'}</a></td>
   </tr>
  </table>
 </td>
 <td class="nowrap">
<table><tr>
	<td><img src=$NicToolClient::image_dir/perm-]
                    . (
                    $del->{delegate_write} ? "checked.gif" : "unchecked.gif" )
                    . qq(>&nbsp;Write</td><td><img src=$NicToolClient::image_dir/perm-)
                    . ( $del->{delegate_delete} ? "checked.gif" : "unchecked.gif")
                    . qq(>&nbsp;Remove</td><td><img src=$NicToolClient::image_dir/perm-)
                    . ( $del->{delegate_delegate} ? "checked.gif" : "unchecked.gif")
                    . qq(>&nbsp;Re-delegate</td> <td><img src=$NicToolClient::image_dir/perm-)
                    . ( $del->{delegate_add_records} ? "checked.gif" : "unchecked.gif")
                    . qq(>&nbsp;Add Records</td> <td><img src=$NicToolClient::image_dir/perm-)
                    . ( $del->{delegate_delete_records} ? "checked.gif" : "unchecked.gif")
                    . qq(
>&nbsp;Delete Records</td> </tr> </table> </td> <td class="nowrap" width=1%>);

                if ( $nt_obj->no_gui_hints
                    || !$zone->{'deleted'} && $user->{zone_delegate} )
                {
                    print
                        "<a href=\"javascript:void window.open('delegate_zones.cgi?obj_list=$zone->{'nt_zone_id'}&nt_group_id=$del->{'nt_group_id'}&edit=1', 'delegate_win', 'width=640,height=480,scrollbars,resizable=yes')\">Edit</a>";
                }
                else {
                    print "<span class=disabled>Edit</span>";
                }
                print qq{ </td> <td class="nowrap center" style="width:1%;"> };

                if ( $nt_obj->no_gui_hints
                    || !$zone->{'deleted'} && $user->{zone_delegate} )
                {
                    print qq[<a href="zone.cgi?nt_zone_id=$zone->{'nt_zone_id'}&nt_group_id=$q->param('nt_group_id')&delegate_group_id=$del->{'nt_group_id'}&deletedelegate=1" onClick="return confirm('Are you sure you want to remove the delegation of zone $zone->{'zone'} to group $del->{'group_name'}?');"><img src="$NicToolClient::image_dir/trash-delegate.gif" alt="Remove Delegation"></a>];
                }
                else {
                    print qq[<img src="$NicToolClient::image_dir/trash-delegate-disabled.gif">];
                }

                print qq{ </td> </tr>};
            }
            print qq{ </table> </td> </tr> </table> };
        }
    }

    print qq[<table class="fat">
    <tr class=dark_grey_bg><td><table class="no_pad fat">
    <tr>
    <td><b>Properties</b></td>];
    if ( $nt_obj->no_gui_hints
        || !$zone->{'deleted'}
        && $user->{'zone_write'}
        && ( $isdelegate ? $zone->{'delegate_write'} : 1 ) )
    {
        print "<td align=right><a href=zone.cgi?",
            join( '&', @state_fields ),
            "&nt_group_id="
            . $q->param('nt_group_id')
            . "&nt_zone_id=$zone->{'nt_zone_id'}&edit_zone=1>Edit</a></td>";
    }
    else {
        print "<td align=right><span class=disabled>Edit</span></td>";
    }
    print qq[</tr></table>
</td></tr></table>
<table cellspacing=0 class="fat">
<tr>
<td width=50%>
<table class="fat">];
    foreach (qw(zone mailaddr description serial minimum)) {
        print qq[<tr class=light_grey_bg>
<td class="nowrap">$_: </td>
<td class="fat">], ( $zone->{$_} ? $zone->{$_} : '&nbsp;' ), "</td></tr>";
    }
    print qq[</table>
    </td><td width=50% valign=top>
    <table class="fat">];
    foreach (qw(refresh retry expire ttl )) {
        print qq[<tr class=light_grey_bg>
        <td class="nowrap">$_: </td>
        <td class="fat">], ( $zone->{$_} ? $zone->{$_} : '&nbsp;' ), "</td></tr>";
    }

    print qq[</table></td></tr></table>];

    return $zone;
}

sub display_nameservers {
    my ( $nt_obj, $user, $q, $zone ) = @_;

    my $isdelegate = exists $zone->{'delegated_by_id'};
    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

    my @fields = qw(name address description);
    my %labels = (
        name        => 'name',
        address     => 'address',
        description => 'description'
    );

    print qq[<table cellspacing=0 class="fat">
    <tr><td>
    <table class="fat">
    <tr class=dark_grey_bg><td><table class="no_pad fat">
    <tr>
    <td><b>Nameservers</b></td>];
    if ( $nt_obj->no_gui_hints
        || !$zone->{'deleted'}
        && $user->{'zone_write'}
        && ( $isdelegate ? $zone->{'delegate_write'} : 1 ) )
    {
        print "<td align=right><a href=zone.cgi?",
            join( '&', @state_fields ),
            "&nt_group_id="
            . $q->param('nt_group_id')
            . "&nt_zone_id=$zone->{'nt_zone_id'}&edit_zone=1>Edit</a></td>";
    }
    else {
        print "<td align=right><span class=disabled>Edit</span></td>";
    }
    print qq[</tr></table>
    </td></tr></table>
    <table class="fat">
    <tr class=dark_grey_bg>];
    foreach (@fields) { print "<td align=center>$labels{$_}</td>"; }
    print "</tr>";

    my $x = 1;
    foreach my $ns ( @{ $zone->{'nameservers'} } ) {
        print "<tr class=",
            ( $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg' ), ">";
        foreach (@fields) {
            if ( $_ eq 'name' ) {
                print qq[<td><table class="no_pad"><tr>
                <td><img src=$NicToolClient::image_dir/nameserver.gif></td>
                <td>], ( $ns->{$_} ? $ns->{$_} : '&nbsp;' ), "</td>";
                print "</tr></table></td>";
            }
            else {
                print "<td>", ( $ns->{$_} ? $ns->{$_} : '&nbsp;' ), "</td>";
            }
        }
        print "</tr>";
    }

    print "</table>";
    print "</td></tr></table>";
}

sub display_zone_records {
    my ( $nt_obj, $user, $q, $zone ) = @_;
    my $group = $nt_obj->get_group( nt_group_id => $user->{'nt_group_id'} );
    my $zonedelegate = exists $zone->{'delegated_by_id'};

    # display any status messages regarding any previous actions
    #    New Zone Record 'host.example.com' Created
    display_zone_records_new( $nt_obj, $user, $q, $zone );

    #    Zone Record successfully modified
    display_zone_records_edit( $nt_obj, $user, $q, $zone );

    #    Zone Record successfully deleted.
    if ( $q->param('delete_record') ) {
        my $error = $nt_obj->delete_zone_record(
            nt_group_id       => $q->param('nt_group_id'),
            nt_zone_record_id => $q->param('nt_zone_record_id')
        );
        if ( $error->{'error_code'} != 200 ) {
            $nt_obj->display_nice_error( $error, "Delete Zone Record" );
        }
        else {
            $nt_obj->display_nice_message(
                "Zone Record successfully deleted.",
                "Delete Zone Record" );
        }
    }

    my @columns = qw(name type address ttl weight priority other description);

    my %labels = (
        name        => 'Name',
        type        => 'Type',
        address     => 'Address',
        ttl         => 'TTL',
        weight      => 'Weight',
        priority    => 'Priority',
        other       => 'Port',
        description => 'Description',
    );

    $nt_obj->display_sort_options( $q, \@columns, \%labels, 'zone.cgi',
        [ 'nt_group_id', 'nt_zone_id' ] )
        if $q->param('edit_sortorder');
    $nt_obj->display_advanced_search( $q, \@columns, \%labels, 'zone.cgi',
        [ 'nt_group_id', 'nt_zone_id' ] )
        if $q->param('edit_search');

    my %params = ( nt_zone_id => $q->param('nt_zone_id') );
    my %sort_fields;
    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields, 50 );

    $sort_fields{'name'} = { 'order' => 1, 'mod' => 'Ascending' }
        unless %sort_fields;

    my $rv = $nt_obj->get_zone_records(%params);
    return $nt_obj->display_nice_error( $rv, "Get Zone Records" )
        if ( $rv->{'error_code'} != '200' );

    my $zone_records = $rv->{'records'};

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push( @state_fields, "$_=" . $q->escape( $q->param($_) ) )
            if ( $q->param($_) );
    }

# Display the RR header: Resource Records  New Resource Record | View Resource Record Log
    my @options;
    if ($nt_obj->no_gui_hints
        || !$zone->{'deleted'} 
        && $user->{'zonerecord_create'}
        && (  $zonedelegate
            ? $zone->{'delegate_write'} && $zone->{'delegate_add_records'}
            : 1
        )
        )
    {
        push( @options,
                  "<a href=zone.cgi?"
                . join( '&', @state_fields )
                . "&nt_group_id="
                . $q->param('nt_group_id')
                . "&nt_zone_id="
                . $q->param('nt_zone_id')
                . "&new_record=1#RECORD>New Resource Record</a>" );
    }
    else {
        push( @options, "<span class=disabled>New Resource Record</span>"
        );
    }
    push( @options,
              "<a href=zone_record_log.cgi?"
            . "nt_group_id="
            . $q->param('nt_group_id')
            . "&nt_zone_id="
            . $q->param('nt_zone_id')
            . ">View Resource Record Log</a>" );

    print qq[<table class="fat">
    <tr><td><hr></td></tr>];

    #show delegation information if delegated down

    print qq[<tr class=dark_grey_bg><td>
    <table class="no_pad fat">
    <tr>
    <td><b>Resource Records</b></td>
    <td align=right>], join( ' | ', @options ), "</td>";
    print "</tr></table></td></tr>";
    print "</table>";

    $nt_obj->display_search_rows( $q, $rv, \%params, 'zone.cgi',
        [ 'nt_group_id', 'nt_zone_id' ] );

    if (@$zone_records) {

        # only show columns applicable to the records in the zone
        @columns = qw(name type address ttl );

        my %has_type;
        foreach my $r_record (@$zone_records) {
            $has_type{ $r_record->{'type'} }++;
        }
        if ( $has_type{'MX'} || $has_type{'SRV'} ) {
            push @columns, 'weight';
        }
        if ( $has_type{'SRV'} ) {
            push @columns, 'priority', 'other';
        }
        push @columns, 'description';

        print qq[<table class="fat">
        <tr class=dark_grey_bg>];
        foreach (@columns) {
            if ( $sort_fields{$_} ) {
                print qq[<td class="dark_bg center">
								<table class="no_pad"><tr>
                <td>$labels{$_}</td>
                <td>&nbsp; &nbsp; $sort_fields{$_}->{'order'}</td>
                <td><img src=$NicToolClient::image_dir/],
                    (
                    uc( $sort_fields{$_}->{'mod'} ) eq 'ASCENDING'
                    ? 'up.gif'
                    : 'down.gif'
                    ),
                    "></tD>";
                print "</tr></table></td>";

            }
            else {
                print "<td align=center>", "$labels{$_}</td>";
            }
        }
        print
            "<td align=center width=1%><img src=$NicToolClient::image_dir/delegate.gif></td>";
        print
            "<td align=center width=1%><img src=$NicToolClient::image_dir/trash.gif></td>";
        print "</tr>";

        my $x = 0;
        my $range;
        my $isdelegate;
        my $img;
        my $hilite;
        my $bgclass;
        foreach my $r_record (@$zone_records) {
            $range      = $r_record->{'period'};
            $isdelegate = exists $r_record->{'delegated_by_id'};
            $img        = $isdelegate ? '-delegated' : '';
            $bgclass = ( $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg' );
            $hilite = ( $x % 2 == 0 ? 'light_hilite_bg' : 'dark_hilite_bg');
            $bgclass = $hilite
                if (
                $r_record->{'nt_zone_record_id'} eq $q->param('new_record_id')
                and $NicToolClient::hilite_new_zone_records );
            print "<tr class=$bgclass>";
            $r_record->{name} = "@ ($zone->{'zone'})"
                if ( $r_record->{name} eq "@" );

            if (   uc( $r_record->{type} ) ne "MX"
                && uc( $r_record->{'type'} ) ne "SRV" )
            {
                $r_record->{weight}
                    = "";    # showing n/a just cluttered the screen
            }

            # shorten theh max width of the address field (workaround for
            # display formatting problem with DomainKey entries.
            if ( length $r_record->{address} > 48 ) {
                my $max = 0;
                my @lines;
                while ( $max < length $r_record->{address} ) {
                    push @lines, substr( $r_record->{address}, $max, 48 );
                    $max += 48;
                }
                $r_record->{address} = join "<br>", @lines;
            }
            foreach (@columns) {
                if ( $_ eq 'name' ) {
                    print qq[<td><table class="no_pad">
                    <tr>
                    <td>];
                    if ( !$zone->{'deleted'} ) {
                        print "<a href=zone.cgi?", join( '&', @state_fields ),
                            "&nt_zone_record_id=$r_record->{'nt_zone_record_id'}&nt_zone_id=$zone->{'nt_zone_id'}&nt_group_id="
                            . $q->param('nt_group_id')
                            . "&edit_record=1#RECORD><img src=$NicToolClient::image_dir/r_record$img.gif></a>";
                    }
                    else {
                        print
                            "<img src=$NicToolClient::image_dir/r_record$img.gif>";
                    }
                    print "</td>";
                    print "<td>";
                    if ( !$zone->{'deleted'} ) {
                        print "<a href=zone.cgi?",
                            join( '&', @state_fields ),
                            "&nt_zone_record_id=$r_record->{'nt_zone_record_id'}&nt_zone_id=$zone->{'nt_zone_id'}&nt_group_id="
                            . $q->param('nt_group_id')
                            . "&edit_record=1#RECORD>", $r_record->{$_},
                            "</a>";
                    }
                    else {
                        print $r_record->{$_};
                    }
                    if ( $r_record->{'delegated_by_id'} ) {
                        print
                            "&nbsp;&nbsp;<img src=$NicToolClient::image_dir/perm-"
                            . (
                            $r_record->{'delegate_write'}
                            ? 'write.gif'
                            : 'nowrite.gif'
                            ) . " >";
                    }
                    print "</td>";
                    print "</tr></table></td>";
                }
                elsif ( $_ =~ /address|ttl|weight|priority|other/i ) {
                    print '<td align="right">',
                        ( $r_record->{$_} ? $r_record->{$_} : '&nbsp;' ),
                        "</td>";
                }
                else {
                    print '<td align="center">',
                        ( $r_record->{$_} ? $r_record->{$_} : '&nbsp;' ),
                        "</td>";
                }
            }
            if ($nt_obj->no_gui_hints
                || !$zone->{'deleted'}
                && $group->{'has_children'}
                && $user->{'zonerecord_delegate'}
                && (  $isdelegate
                    ? $r_record->{'delegate_delegate'}
                    : ( $zonedelegate ? $zone->{'delegate_delegate'} : 1 )
                )
                )
            {
                print
                    "<td align=center><a href=\"javascript:void window.open('delegate_zones.cgi?type=record&obj_list=$r_record->{'nt_zone_record_id'}&nt_zone_id=$r_record->{'nt_zone_id'}', 'delegate_win', 'width=640,height=480,scrollbars,resizable=yes')\"><img src=$NicToolClient::image_dir/delegate.gif alt='Delegate Resource Record'></a></td>";
            }
            else {
                print
                    "<td align=center><img src=$NicToolClient::image_dir/delegate-disabled.gif></td>";
            }
            $img =~ s/.$//g;
            if ( $nt_obj->no_gui_hints
                || !$zone->{'deleted'}
                && $user->{'zonerecord_delete'}
                && !$isdelegate
                && ( $zonedelegate ? $zone->{'delegate_delete_records'} : 1 )
                )
            {
                print "<td align=center><a href=\"zone.cgi?",
                    join( '&', @state_fields ),
                    "&nt_zone_id=$zone->{'nt_zone_id'}&nt_group_id="
                    . $q->param('nt_group_id')
                    . "&nt_zone_record_id=$r_record->{'nt_zone_record_id'}&delete_record=$r_record->{'nt_zone_record_id'}\" onClick=\"return confirm('Are you sure you want to delete $zone->{'zone'} $r_record->{'type'} record $r_record->{'name'} that points to $r_record->{'address'} ?')\"><img src=$NicToolClient::image_dir/trash.gif></a></td>";

            }
            else {
                print
                    "<td align=center><img src=$NicToolClient::image_dir/trash$img-disabled.gif></td>";
            }
            print "</tr>";
        }

        print "</table>";

    }
}

sub display_zone_records_new {
    my ( $nt_obj, $user, $q, $zone ) = @_;

    return if ! $q->param('new_record');
    return if $q->param('Cancel');   # do nothing

    if ( ! $q->param('Create') ) {
        return display_edit_record( $nt_obj, $user, $q, '', $zone, 'new' );
    };

    my @fields
        = qw(nt_group_id nt_zone_id name type address weight priority other ttl description);
    my %data;
    foreach my $x (@fields) {
        $data{$x} = $q->param($x);
    }

    my $error = $nt_obj->new_zone_record(%data);
    if ( $error->{'error_code'} != 200 ) {
        &display_edit_record( $nt_obj, $user, $q, $error, $zone, 'new' );
    }
    else {
        $q->param(
            -name  => 'new_record_id',
            -value => $error->{'nt_zone_record_id'}
        );
        $nt_obj->display_nice_message(
            "New Zone Record '$data{name}' Created",
            "New Zone Record" );
    }
};

sub display_zone_records_edit {
    my ( $nt_obj, $user, $q, $zone ) = @_;

    return if ! $q->param('edit_record');
    return if $q->param('Cancel'); # do nothing

    if ( ! $q->param('Save') ) {
        return display_edit_record( $nt_obj, $user, $q, "", $zone, 'edit' );
    };

    my @fields
        = qw(nt_group_id nt_zone_id nt_zone_record_id name type address weight priority other ttl description deleted);
    my %data;
    foreach my $x (@fields) {
        $data{$x} = $q->param($x);
    }
    my $error = $nt_obj->edit_zone_record(%data);
    if ( $error->{'error_code'} != 200 ) {
        &display_edit_record( $nt_obj, $user, $q, $error, $zone,
            'edit' );
    }
    else {
        $nt_obj->display_nice_message(
            "Zone Record successfully modified.",
            "Edit Zone Record" );
    }
};


sub display_edit_record {
    my ( $nt_obj, $user, $q, $message, $zone, $edit ) = @_;

    my $zone_record = { 'ttl' => $NicToolClient::default_zone_record_ttl };
    my $action = 'New';
    my $message2;

    # is this a Save or Edit operation?
    if ( $q->param('nt_zone_record_id') && !$q->param('Save') )
    {    # get current settings

        if ( $q->param('nt_zone_record_log_id') ) {
            $action      = 'Recover';
            $zone_record = $nt_obj->get_zone_record_log_entry(
                nt_zone_record_id     => $q->param('nt_zone_record_id'),
                nt_zone_record_log_id => $q->param('nt_zone_record_log_id')
            );
        }
        else {
            $action      = 'Edit';
            $zone_record = $nt_obj->get_zone_record(
                nt_group_id       => $q->param('nt_group_id'),
                nt_zone_id        => $q->param('nt_zone_id'),
                nt_zone_record_id => $q->param('nt_zone_record_id')
            );
        }

        if ( $zone_record->{'error_code'} != 200 ) {
            $message2 = $zone_record;
        }
        else {
            $zone_record->{'name'} = $zone->{'zone'} . "."
                if ( $zone_record->{'name'} eq "@" && $zone->{'zone'} );
            $zone_record->{'address'} = $zone->{'zone'} . "."
                if ( $zone_record->{'address'} eq "@" && $zone->{'zone'} );
        }
    }
    my $isdelegate = exists $zone_record->{'delegated_by_id'};
    my $pseudo     = $zone_record->{'pseudo'};

    my ( $type_values, $type_labels );

    my $rr_types = $nt_obj->rr_types;
    #use Data::Dumper; warn Dumper $rr_types;
    my %forwards = map { $_->{name} => "$_->{description} ($_->{name})" } 
        grep( $_->{forward} == 1, @$rr_types);
    my %reverse  = map { $_->{name} => "$_->{description} ($_->{name})" } 
        grep( $_->{reverse} == 1, @$rr_types);

    # present RR types appropriate for the type of zone
    if ( $zone->{'zone'} =~ /(in-addr|ip6)\.arpa$/ ) {
        $type_values = [ sort keys %reverse ];
        $type_labels = \%reverse;
    }
    else {
        $type_values = [ sort keys %forwards ];
        $type_labels = \%forwards;
    }


    # does user have Edit permissions?
    my $modifyperm = !$isdelegate && $user->{'zonerecord_write'}
        || $isdelegate
        && $user->{'zonerecord_write'}
        && $zone_record->{'delegate_write'};

    if ($modifyperm) {
        print $q->start_form(
            -action => 'zone.cgi',
            -method => 'POST',
            -name   => 'rr_edit'
            ),
            $q->hidden( -name => $edit . '_record' ),
            $q->hidden( -name => 'nt_group_id' ),
            $q->hidden( -name => 'nt_zone_id' ), "\n";
        print $q->hidden( -name => 'nt_zone_record_id' ) if $edit eq 'edit';
        print $q->hidden( -name => 'nt_zone_record_log_id' );
        print $q->hidden( -name => 'deleted', -value => 0 )
            if $action eq 'Recover';

        foreach ( @{ $nt_obj->paging_fields } ) {
            print $q->hidden( -name => $_ );
        }
    }
    else {
        $action = 'View' if $action eq 'Edit';
    }

    $nt_obj->display_nice_error($message)  if $message;
    $nt_obj->display_nice_error($message2) if $message2;
    print qq[<a name="RECORD">
    <div class="dark_bg">Resource Record</div>];

    # display delegation information
    if ( !$isdelegate && $edit ne 'new' ) {
        my $delegates = $nt_obj->get_zone_record_delegates(
            nt_zone_record_id => $zone_record->{'nt_zone_record_id'} );
        if ( $delegates->{error_code} ne 200 ) {
            warn
                "error get_zone_record_delegates(nt_zone_record_id=>$zone_record->{'nt_zone_record_id'}: "
                . $delegates->{'error_code'} . " "
                . $delegates->{'error_msg'};
        }
        elsif ( @{ $delegates->{'delegates'} } gt 0 ) {
            print qq[
<table class="fat"><tr class=dark_grey_bg><td>Delegates</td></tr></table>
<table cellspacing=0 class="fat">
 <tr>
  <td valign=top>
   <table class="fat">
    <tr class=light_grey_bg>
    <td class="nowrap"> Group</td>
    <td class="nowrap"> Delegated By</td>
    <td class="nowrap"> Access Permissions $nt_obj->help_link('delperms') </td>
    <td class="nowrap" style="width:1%;"> Edit</td>
    <td class="nowrap center" style="width:1%;"><img src=$NicToolClient::image_dir/trash-delegate.gif></td>
   </tr>
];
            foreach my $del ( @{ $delegates->{'delegates'} } ) {
                print qq[
<tr class=light_grey_bg>
 <td class="nowrap center">
	<table><tr>
	 <td valign=center><a href=group.cgi?nt_group_id=$del->{'nt_group_id'}><img src=$NicToolClient::image_dir/group.gif></a></td>
	 <td valign=center><a href=group.cgi?nt_group_id=$del->{'nt_group_id'}>$del->{'group_name'}</a></td>
   </tr>
  </table>
 </td>
 <td class="nowrap center">
	<table><tr>
		<td valign=center><a href=user.cgi?nt_user_id=$del->{'delegated_by_id'}><img src=$NicToolClient::image_dir/user.gif ></a></td>
		<td valign=center><a href=user.cgi?nt_user_id=$del->{'delegated_by_id'}>$del->{'delegated_by_name'}</a></td>
	 </tr>
	</table>
 </td>
 <td class="nowrap">
	<table><tr>
   <td><img src=$NicToolClient::image_dir/perm-]
                    . (
                    $del->{delegate_write} ? "checked.gif" : "unchecked.gif" )
                    . qq(>&nbsp;Write</td><td><img src=$NicToolClient::image_dir/perm-)
                    . ( $del->{delegate_delete} ? "checked.gif" : "unchecked.gif")
                    . qq(>&nbsp;Remove</td><td><img src=$NicToolClient::image_dir/perm-)
                    . ( $del->{delegate_delegate} ? "checked.gif" : "unchecked.gif")
                    . qq(>&nbsp;Re-delegate</td>
                            </tr>
                          </table>
                        </td>
                        <td class="nowrap" style="width:1%;">
								);
                if ( $nt_obj->no_gui_hints || $user->{zonerecord_delegate} ) {
                    print qq[<a href="javascript:void window.open('delegate_zones.cgi?type=record&obj_list=$zone_record->{'nt_zone_record_id'}&nt_zone_id=$zone_record->{'nt_zone_id'}&nt_group_id=$del->{'nt_group_id'}&edit=1', 'delegate_win', 'width=640,height=480,scrollbars,resizable=yes')">Edit</a>];
                }
                else {
                    print qq[<span class=disabled>Edit</span>];
                }
                print qq[ </td> <td class="nowrap center" style="width:1%;"> ];

                if ( $nt_obj->no_gui_hints || $user->{zonerecord_delegate} ) {
                    print qq[<a href="zone.cgi?type=record&nt_zone_record_id=$zone_record->{'nt_zone_record_id'}&nt_zone_id=$zone_record->{'nt_zone_id'}&nt_group_id=$q->param('nt_group_id')&delegate_group_id=$del->{'nt_group_id'}&deletedelegate=1" onClick="return confirm('Are you sure you want to remove the delegation of resource record $zone_record->{'name'} to group $del->{'group_name'}?');"><img src="$NicToolClient::image_dir/trash-delegate.gif" alt="Remove Delegation"></a>];
                }
                else {
                    print qq[<img src="$NicToolClient::image_dir/trash-delegate-disabled.gif">];
                }

                print qq[ </td> </tr>];
            }
            print qq[ </table> </td> </tr> </table> ];
        }
    }
    elsif ( $edit ne 'new' && !$pseudo ) {
        print qq[
<table class="fat">
 <tr class=dark_grey_bg>
  <td>
   <table class="no_pad fat"> <tr> <td><b>Delegation</b></td> </tr> </table>
	</td>
 </tr></table>
<table cellspacing=0 class="fat">
 <tr> <td valign=top>
   <table class="fat">
    <tr class=light_grey_bg>
     <td class="nowrap"> Delegated by: </td>
     <td class="fat"> <table> <tr>
		    <td valign=center><img src=$NicToolClient::image_dir/user.gif></td>
        <td valign=center> $zone_record->{'delegated_by_name'}</td>
       </tr> </table> </td>
    </tr>

    <tr class=light_grey_bg>
     <td class="nowrap"> Belonging to group: </td>
     <td class="fat"> <table> <tr>
        <td valign=center><img src=$NicToolClient::image_dir/group.gif></td>
        <td valign=center> $zone_record->{'group_name'}</td>
       </tr> </table> </td>
    </tr>

    <tr class=light_grey_bg>
     <td class="nowrap"> With Permissions: </td>
     <td class="fat">
      <table>
       <tr class=light_grey_bg>];
        my %perms = (
            'write'  => "Write",
            'delete' => "Remove Delegation",
            delegate => "Re-delegate"
        );
        foreach (qw(write delete delegate)) {
            print "<td>";

#print "<img src=$NicToolClient::image_dir/perm-".($zone->{"delegate_$_"}?"$_.gif":"no$_.gif").">&nbsp;".$perms{$_};
            print "<img src=$NicToolClient::image_dir/perm-"
                . (
                $zone_record->{"delegate_$_"}
                ? "checked.gif"
                : "unchecked.gif"
                )
                . ">&nbsp;"
                . $perms{$_};
            print "</td>";
        }
        print "</tr></table>";
        print "</td></tr>";
        print "</table>";
        print "</td></tr></table>";
        print qq(
            <table class="fat">
            <tr class=dark_grey_bg>
                <td> Actions</td>
            </tr>
            </table>

            <table cellspacing=0 class="fat">
            <tr class=light_grey_bg>
                <td align=left>
        );
        if (   $nt_obj->no_gui_hints
            || $user->{'zonerecord_delegate'}
            && $zone_record->{'delegate_delete'} )
        {
            print
                "<a href='zone.cgi?type=record&nt_zone_record_id=$zone_record->{'nt_zone_record_id'}&nt_zone_id=$zone_record->{'nt_zone_id'}&nt_group_id="
                . $q->param('nt_group_id')
                . "&delegate_group_id="
                . $q->param('nt_group_id')
                . "&deletedelegate=1' onClick=\"return confirm('Are you sure you want to remove the delegation of resource record $zone_record->{'name'} to group $zone_record->{'group_name'}?');\">Remove Delegation</a>";
        }
        else {
            print "<span class=disabled>Remove Delegation</span>";
        }
        print " | ";

        if (   $nt_obj->no_gui_hints
            || $user->{zone_write}
            && $user->{'zonerecord_delegate'}
            && $zone_record->{'delegate_delegate'} )
        {
            print
                "<a href=\"javascript:void window.open('delegate_zones.cgi?type=record&obj_list=$zone_record->{'nt_zone_record_id'}&nt_zone_id=$zone_record->{'nt_zone_id'}', 'delegate_win', 'width=640,height=480,scrollbars,resizable=yes')\">Re-Delegate</a>";
        }
        else {
            print
                "<span class=disabled>Re-Delegate</span>";
        }
        print qq(
                </td>
            </tr>
            </table>
        );

    }

    print qq[
  <table class="fat">
    <tr class="dark_grey_bg"><td colspan=2> $action </td></tr>
    <tr class="light_grey_bg">
      <td align="right"> Name:</td>
        <td class="fat">], 
				$modifyperm ? $q->textfield(
        -name      => 'name',
        -size      => 40,
        -maxlength => 127,
        -default   => $zone_record->{'name'}
        ) : $zone_record->{'name'},
        ( $zone_record->{'name'} ne "$zone->{'zone'}." ? "<b>.$zone->{'zone'}.</b>" : ""),
        "</td></tr>";

    my $default_record_type = $zone_record->{'type'};
    $default_record_type = 'PTR' if ( $zone->{'zone'} =~ /(in-addr|ip6)\.arpa/ );

    print qq[
    <tr class="light_grey_bg">
      <td class=right> Type:</td><td class="fat">\n], 
			$modifyperm ? $q->popup_menu(

        -name    => 'type',
        -id      => 'rr_type',
        -values  => $type_values,
        -labels  => $type_labels,
        -default => $default_record_type,
        -onClick => "showFieldsForRRtype(value)"
        ,    # not valid for popup menus (according to CGI.pm docs, but works
        -onChange => "showFieldsForRRtype(value)",    # seems to work
        -onFocus  => "showFieldsForRRtype(value)"
        , # run, darn it, even if user doesn't change value and onClick isn't permitted
        )
        : $type_labels->{ $zone_record->{'type'} }, "</td></tr>";

    print qq{
      <tr class="light_grey_bg">
        <td align="right"> Address:</td>
        <td width="100%">}, $modifyperm
        ? $q->textfield(
        -name      => 'address',
        -size      => 50,
        -maxlength => 255,
        -default   => $zone_record->{'address'},
        )
        : $zone_record->{'address'},
        $nt_obj->help_link('rraddress') . "</td></tr>";

    print qq{
       <tr id="tr_weight" class="light_grey_bg">
         <td align="right"> Weight:</td>
         <td class="fat">}, $modifyperm
        ? $q->textfield(
        -name      => 'weight',
        -size      => 5,
        -maxlength => 10,
        -default   => '10',
        -default   => $zone_record->{'weight'}
        )
        : $zone_record->{'weight'},
        "</td></tr>";

    print qq{
       <tr id="tr_priority" class="light_grey_bg">
         <td align="right"> Priority:</td>
         <td class="fat">}, $modifyperm
        ? $q->textfield(
        -name      => 'priority',
        -size      => 5,
        -maxlength => 10,
        -default   => '10',
        -default   => $zone_record->{'priority'}
        )
        : $zone_record->{'priority'},
        "</td></tr>";

    print qq{
       <tr id="tr_other" class="light_grey_bg">
         <td class="right"> Port:</td>
         <td class="fat">}, $modifyperm
        ? $q->textfield(
        -name      => 'other',
        -size      => 5,
        -maxlength => 10,
        -default   => '10',
        -default   => $zone_record->{'other'}
        )
        : $zone_record->{'other'},
        "</td></tr>";

    print qq{
        <tr class="light_grey_bg">
          <td align="right"> TTL:</td>
          <td width="100%">}, $modifyperm
        ? $q->textfield(
        -name      => 'ttl',
        -size      => 5,
        -maxlength => 10,
        -default   => $zone_record->{'ttl'}
        )
        : $zone_record->{'ttl'},
        "</td></tr>";

    print qq{
        <tr class="light_grey_bg">
          <td align="right"> Description:</td>
          <td width="100%">}, $modifyperm
        ? $q->textfield(
        -name      => 'description',
        -size      => 60,
        -maxlength => 128,
        -default   => $zone_record->{'description'}
        )
        : $zone_record->{'description'} || "&nbsp;",
        "</td></tr>";

    print qq{ <tr class="dark_grey_bg"><td colspan="2" align="center"> },
        $modifyperm
        ? $q->submit( $edit eq 'edit' ? 'Save' : 'Create' )
        . $q->submit('Cancel')
        : '&nbsp;', "</td></tr>";

    print "</table>";

    print $q->end_form if $modifyperm;
}

sub display_edit_zone {
    my ( $nt_obj, $user, $q, $message, $zone, $edit ) = @_;

    my $action;

    print $q->start_form(
        -action => 'zone.cgi',
        -method => 'POST',
        -name   => 'new_zone'
    );
    print $q->hidden( -name => 'nt_group_id' );
    print $q->hidden( -name => 'nt_zone_id' ) if $edit eq 'edit';
    print $q->hidden( -name => $edit . '_zone' );

    if ( $q->param('undelete') && $zone->{'deleted'} ) {
        $action = 'Recover';
        print $q->hidden( -name => 'undelete' );

    }
    else {
        $action = 'Edit';
    }

    foreach ( @{ $nt_obj->paging_fields() } ) {
        print $q->hidden( -name => $_ ) if ( $q->param($_) );
    }

    $nt_obj->display_nice_error($message) if $message;

    print qq[<a name='ZONE'>
<table class="fat">
 <tr class=dark_bg><td colspan=2><b>$action Zone</b></td></tr>
 <tr class=light_grey_bg>
  <td align=right>Zone:</td>
  <td class="fat">$zone->{'zone'}</td></tr>
 <tr class=light_grey_bg>
  <td align=right valign=top>Nameservers:</td>
  <td width=80%>\n];

    my %zone_ns
        = map { $_->{'nt_nameserver_id'}, 1 } @{ $zone->{'nameservers'} };

    # get list of available nameservers
    my $ns_tree = $nt_obj->get_usable_nameservers(
        nt_group_id      => $q->param('nt_group_id'),
        include_for_user => 1
    );
    warn "nt_group_id is " . $q->param('nt_group_id');

    foreach ( 1 .. scalar( @{ $ns_tree->{'nameservers'} } ) ) {
        last if ( $_ > 10 );

        my $ns = $ns_tree->{'nameservers'}->[ $_ - 1 ];

        print $q->checkbox(
            -name    => "nameservers",
            -checked => ( $zone_ns{ $ns->{'nt_nameserver_id'} } ? 1 : 0 ),
            -value   => $ns->{'nt_nameserver_id'},
            -label   => "$ns->{'description'} ($ns->{'name'})"
            ),
            "<BR>";
        delete $zone_ns{ $ns->{'nt_nameserver_id'} };
    }
    if ( @{ $ns_tree->{'nameservers'} } == 0 ) {
        print "No available nameservers.";
    }
    foreach ( keys %zone_ns ) {
        my $ns = $nt_obj->get_nameserver( nt_nameserver_id => $_ );
        print "<li>$ns->{'description'} ($ns->{'name'})<BR>";
    }
    print "</td></tr>\n";

    print "<tr class=light_grey_bg>";
    print "<td align=right valign=top>", "Description:</td>";
    print "<td width=80%>",
        $q->textarea(
        -name      => 'description',
        -cols      => 50,
        -rows      => 4,
        -maxlength => 255,
        -default   => $zone->{'description'}
        ),
        "</td></tr>";

    print "<tr class=light_grey_bg>";
    print "<td align=right>", "TTL:</td>";
    print "<td width=80%>",
        $q->textfield(
        -name      => 'ttl',
        -size      => 8,
        -maxlength => 10,
        -default   => $zone->{'ttl'}
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.ttl.value=$NicToolClient::default_zone_ttl\">",
        " $NicToolClient::default_zone_ttl";
    print "</td></tr>";

    print "<tr class=light_grey_bg>";
    print "<td align=right>", "Refresh:</td>";
    print "<td width=80%>",
        $q->textfield(
        -name      => 'refresh',
        -size      => 8,
        -maxlength => 10,
        -default   => $zone->{'refresh'}
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.refresh.value=$NicToolClient::default_zone_refresh\">",
        " $NicToolClient::default_zone_refresh", "</td></tr>";

    print "<tr class=light_grey_bg>";
    print "<td align=right>", "Retry:</td>";
    print "<td width=80%>",
        $q->textfield(
        -name      => 'retry',
        -size      => 8,
        -maxlength => 10,
        -default   => $zone->{'retry'}
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.retry.value=$NicToolClient::default_zone_retry\">",
        " $NicToolClient::default_zone_retry", "</td></tr>";

    print "<tr class=light_grey_bg>";
    print "<td align=right>", "Expire:</td>";
    print "<td width=80%>",
        $q->textfield(
        -name      => 'expire',
        -size      => 8,
        -maxlength => 10,
        -default   => $zone->{'expire'}
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.expire.value=$NicToolClient::default_zone_expire\">",
        " $NicToolClient::default_zone_expire", "</td></tr>";

    print "<tr class=light_grey_bg>";
    print "<td align=right>", "Minimum:</td>";
    print "<td width=80%>",
        $q->textfield(
        -name      => 'minimum',
        -size      => 8,
        -maxlength => 10,
        -default   => $zone->{'minimum'}
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.minimum.value=$NicToolClient::default_zone_minimum\">",
        " $NicToolClient::default_zone_minimum", "</td></tr>";

    print "<tr class=light_grey_bg>";
    print "<td align=right>", "MailAddr:</td>";
    print "<td width=80%>",
        $q->textfield(
        -name      => 'mailaddr',
        -size      => 25,
        -maxlength => 255,
        -default   => $zone->{'mailaddr'}
        );
    print
        "<input type=\"button\" value=\"Default\" onClick=\"this.form.mailaddr.value='hostmaster."
        . $zone->{'zone'}
        . ".'\">", " hostmaster." . $zone->{'zone'} . ".",
        "</td></tr>";

    print "<tr class=dark_grey_bg><td colspan=2 align=center>",
        $q->submit( $edit eq 'edit' ? 'Save' : 'Create' ),
        $q->submit('Cancel'), "</td></tr>";
    print "</table>";
    print $q->end_form;
}

