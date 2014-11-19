#!/usr/bin/perl
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.05+ Copyright 2004-2008 The Network People, Inc.
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
        username  => $user->{'username'},
        groupname => $user->{'groupname'},
        userid    => $user->{'nt_user_id'}
    );

    if ( $q->param('cancel_delegate') ) {   # do nothing
        print qq[<script> window.close(); </script>];
    }
    elsif ( $q->param('Save')   ) { do_save($nt_obj, $q, $user);   }
    elsif ( $q->param('Modify') ) { do_modify($nt_obj, $q, $user); }
    elsif ( $q->param('Remove') ) { do_remove($nt_obj, $q, $user); }
    else {
        my $d = $q->param("delete") ? "delete" : '';
        my $e = $q->param("edit") ? "edit" : $d;
        delegate_zones( $nt_obj, $user, $q, '', $e );
    }

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub display_record {
    my ($title, $zone, $zr) = @_;
    print qq[
<div id="delegateRecordHeadline" class="dark_bg bold">$title</div>
<div id="delegateZoneList" class="light_grey_bg"> Record(s): 
 <a href="zone.cgi?nt_group_id=$zone->{'nt_group_id'}&amp;nt_zone_id=$zone->{'nt_zone_id'}" target=body><img src="$NicToolClient::image_dir/zone.gif" > $zone->{'zone'}</a>
</div>

<table id="delegateRecordHeader" class="fat">
 <tr class="dark_grey_bg"> <td colspan=6> Resource Record</td></tr>
 <tr class=light_grey_bg>
  <td class=center> Name</td>
  <td class=center> Type</td>
  <td class=center> Address</td>
  <td class=center> TTL</td>
  <td class=center> Weight</td>
  <td class=center> Description</td>
 </tr>
 <tr class=light_grey_bg>
  <td class="middle" style="width:25%;">
   <a href="zone.cgi?nt_group_id=$zone->{'nt_group_id'}&amp;nt_zone_id=$zone->{'nt_zone_id'}&amp;nt_zone_record_id=$zr->{'nt_zone_record_id'}&amp;edit_record=1" target=body><img src="$NicToolClient::image_dir/r_record.gif" alt="record"> $zr->{'name'} </a>
  </td>
  <td> $zr->{'type'}</td>
  <td> $zr->{'address'}</td>
  <td> $zr->{'ttl'}</td>
  <td> $zr->{'weight'}</td>
  <td class="fat"> $zr->{'description'} </td>
 </tr>
</table>
];
}

sub delegate_zones {
    my ( $nt_obj, $user, $q, $message, $edit ) = @_;
    my $modifyperm = $user->{'group_modify'} && $user->{'zone_delegate'} && $edit eq 'edit';
    $q->param( 'obj_list', join( ',', $q->param('obj_list') ) );
    my $type  = $q->param('type');
    my $obj   = $type eq 'record' ? 'resource record' : 'zone';
    my $ucobj = $type eq 'record' ? 'Resource Record' : 'Zone';
    my $title = "Delegate ${ucobj}s";
    $title = "Edit $ucobj Delegation"   if $edit eq 'edit';
    $title = "Delete $ucobj Delegation" if $edit eq 'delete';
    my $moreparams;

    if ($type) {
        $moreparams = { type => $type, nt_zone_id => $q->param('nt_zone_id') };
    }
    my $del;    #delegation object
    if ( $type ne 'record' ) {
        my $rv = $nt_obj->get_zone_list( zone_list => $q->param('obj_list') );

        return $nt_obj->display_nice_error( $rv, "Get Zone Details" )
            if $rv->{'error_code'} != 200;

        my $zones = $rv->{'zones'};

        $nt_obj->display_nice_error( $message, "Delegate Zones" ) if $message;

        #TODO handle 600 error where object is already delegated
        my $dzone = join( ', ',
            map( qq[<a href="zone.cgi?nt_group_id=$_->{'nt_group_id'}&amp;nt_zone_id=$_->{'nt_zone_id'}" target=body> <img src="$NicToolClient::image_dir/zone.gif" alt="zone"> $_->{'zone'} </a>], @$zones )
            );

        print qq[
<div id="delegateZoneHeadline" class="dark_bg bold">$title</div>
<div id="delegateZoneList" class="light_grey_bg">Zone: $dzone</div>];
    }
    elsif ( $type eq 'record' ) {
        my $zr = $nt_obj->get_zone_record( nt_zone_record_id => $q->param('obj_list') );
        my $zone = $nt_obj->get_zone( nt_zone_id => $q->param('nt_zone_id') );

        return $nt_obj->display_nice_error( $zr, "Get Zone Record Details" )
            if $zr->{'error_code'} != 200;
        return $nt_obj->display_nice_error( $zone, "Get Zone Details" )
            if $zone->{'error_code'} != 200;

        $nt_obj->display_nice_error( $message, "Delegate Zone Records" ) if $message;
        display_record( $title, $zone, $zr);
    };

    if ( !$edit ) {
        $nt_obj->display_group_list( $q, $user, 'delegate_zones.cgi',
            'delegate', $user->{'nt_group_id'}, $moreparams );
    }
    elsif ( $edit eq 'edit' || $edit eq 'delete' ) {
        my $delegates;
        if ( $type ne 'record' ) {
            $delegates = $nt_obj->get_zone_delegates(
                nt_zone_id => $q->param('obj_list') );
        }
        elsif ( $type eq 'record' ) {
            $delegates = $nt_obj->get_zone_record_delegates(
                nt_zone_record_id => $q->param('obj_list') );
        }
        return $nt_obj->display_nice_error( $delegates,
            "Get Zone " . ucfirst($type) . " Delegates List" )
            if $delegates->{'error_code'} != 200;

        foreach my $d ( @{ $delegates->{'delegates'} } ) {
            if ( $d->{'nt_group_id'} eq $q->param('nt_group_id') ) {
                $del = $d and last;
            }
        }

        print $q->start_form(
            -action => 'delegate_zones.cgi',
            -method => 'POST',
            -name   => $edit
        ),
        "\n",
        $q->hidden(
        -name     => 'obj_list',
        -value    => join( ',', $q->param('obj_list') ),
        -override => 1
        ),
        "\n", $q->hidden( -name => $edit, -value => 1 ),
        "\n", $q->hidden( -name => 'type', -value => $q->param('type') ),
        "\n", $q->hidden( -name  => 'nt_zone_id',
            -value => $edit eq 'record' ? $q->param('nt_zone_id') : $q->param('obj_list')
            ),
        "\n", $q->hidden( -name=>'nt_group_id', -value=>$q->param('nt_group_id')),
        "\n";

        if ( ref $del ) {
            print qq[
<div id="delegateRecordHeadline" class="dark_grey_bg dark">Delegation</div>
<table class="fat">
 <tr class="light_grey_bg"><td>Group</td><td>Delegated By</td></tr>
 <tr class="light_grey_bg">
  <td class="nowrap middle">
     <a href="group.cgi?nt_group_id=$del->{'nt_group_id'}"><img src="$NicToolClient::image_dir/group.gif">$del->{'group_name'}</a>
  </td>
  <td class="nowrap middle">
   <a href="user.cgi?nt_user_id=$del->{'delegated_by_id'}"><img src="$NicToolClient::image_dir/user.gif"> $del->{'delegated_by_name'}</a>
  </td>
 </tr>
</table>
];
        }
        else {
            return $nt_obj->display_nice_error(
                {   error_code => 700,
                    error_msg  => "No delegation found for the chosen $obj"
                },
                "Get Delegation Details"
            );
        }

    }

    print qq[
<table class="fat">
 <tr class="dark_grey_bg">
  <td>],
        (
        $modifyperm
        ? "Allow users in the selected group to have these permissions"
        : "This group has these permissions"
        ),
        $nt_obj->help_link('delperms'), "\n", 
        $q->hidden( -name => 'type' ), "\n";
    print ":</td>
 </tr>";

    my %perms = (
        'perm_write' => "Edit this $obj"
            . ( $type ne 'record' ? " and its records" : '' ),
        'perm_delete'   => "Remove the delegation of this $obj",
        'perm_delegate' => "Re-delegate this $obj"
            . ( $type ne 'record' ? " and its records" : '' ),
    );
    if ( $type ne 'record' ) {
        $perms{'zone_perm_add_records'} = "Add records inside this zone";
        $perms{'zone_perm_delete_records'} = "Delete records inside this zone";
    };

    my %hasperms = (
        perm_write               => $user->{'zone_write'},
        zone_perm_add_records    => $user->{'zonerecord_create'},
        zone_perm_delete_records => $user->{'zonerecord_delete'},
        perm_delete              => $user->{'zone_delegate'},
        perm_delegate            => $user->{'zone_delegate'}
    );

    my @order = qw(perm_write perm_delete perm_delegate);
    push @order, 'zone_perm_add_records'    if $type ne 'record';
    push @order, 'zone_perm_delete_records' if $type ne 'record';
    my $x = 1;
    my $color;
    foreach my $perm (@order) {
        $color = ( $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg' );
        print qq[
 <tr class="light_grey_bg">
  <td class="$color left">];

        my $hasprop = 0;
        if ( $edit eq 'edit' ) {
            if ( $perm =~ /perm_(.+)/ ) {
                $hasprop = $del->{"delegate_$1"};
            }
        }
        unless ( $edit eq 'delete' or !$hasperms{$perm} ) {
            print $q->checkbox(
                -name    => "$perm",
                -value   => '1',
                -checked => $hasprop,
                -label   => $perms{$perm}
                )
                . qq[</td>
 </tr>];
        }
        else {
            print qq[<img src=$NicToolClient::image_dir/perm-]
                . ( $hasprop ? 'checked' : 'unchecked' )
                . qq[.gif alt="checkbox">&nbsp; $perms{$perm}</td>
 </tr>];
        }
    }

    print qq[
</table>
<div class="dark_grey_bg center side_pad"> ],
    $q->submit( $edit eq 'edit' ? 'Modify' : ( $edit eq 'delete' ? 'Remove' : 'Save' ) ),
    $q->submit(
        -name    => 'cancel_delegate',
        -value   => 'Cancel',
        -onClick => 'window.close(); return false;'
        ),
        qq[
</div>],
    $q->end_form;
}

sub do_save {
    my ($nt_obj, $q, $user) = @_;

    my $plist    = 'zone_list';
    my $function = 'delegate_zones';
    my $message  = 'Zones Delegated';

    if ( $q->param('type') eq 'record' ) {
        $plist    = 'zonerecord_list';
        $function = 'delegate_zone_records';
        $message  = 'Zone Records Delegated';
    };

    my %params = (
        nt_group_id => $q->param('group_list'),
        $plist      => $q->param('obj_list'),
    );

    foreach ( qw/ perm_write perm_delete perm_delegate 
                  zone_perm_add_records zone_perm_delete_records / ) { 
        $params{$_} = $q->param($_) ? 1 : 0;
    };

    my $rv = $nt_obj->$function(%params);

    if ( $rv->{'error_code'} != 200 ) {
        delegate_zones( $nt_obj, $user, $q, $rv );
    }
    else {
        print qq[<script> window.close(); </script>
        <span class="center bold">$message</span>];
    }
}

sub do_modify {
    my ($nt_obj, $q, $user) = @_;

    my $list_id  = 'nt_zone_id';
    my $function = 'edit_zone_delegation';
    my $message  = 'Zones Delegated';

    if ( $q->param('type') eq 'record' ) {
        $list_id  = 'nt_zone_record_id';
        $function = 'edit_zone_record_delegation';
        $message  = 'Zone Records Delegated';
    };

    my %params = (
        nt_group_id => $q->param('nt_group_id'),
        $list_id    => $q->param('obj_list')
    );

    foreach ( qw/ perm_write perm_delete perm_delegate  
                zone_perm_add_records zone_perm_delete_records / ) {
        $params{$_} = $q->param($_) ? 1 : 0;
    }

    my $rv = $nt_obj->$function(%params);

    if ( $rv->{'error_code'} != 200 ) {
        delegate_zones( $nt_obj, $user, $q, $rv, 'edit' );
    }
    else {
        print qq[<script> window.close(); </script>
        <span class="center bold">$message</span>];
    }
};

sub do_remove {
    my ($nt_obj, $q, $user) = @_;

    my $rv = $nt_obj->delete_zone_delegation(
                nt_group_id => $q->param('nt_group_id'),
                nt_zone_id  => $q->param('nt_zone_id'),
            );

    if ( $rv->{'error_code'} != 200 ) {
        delegate_zones( $nt_obj, $user, $q, $rv );
    }
    else {
        print qq[<script> window.close(); </script>
        <span class="center bold">Zone Delegation Deleted</span>];
    }
}

