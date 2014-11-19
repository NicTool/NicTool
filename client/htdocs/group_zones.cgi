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

    if ($user && ref $user) {
        display( $nt_obj, $q, $user );
    }
}

sub display {
    my ( $nt_obj, $q, $user ) = @_;

    my ($newzone, $nicemessage) = _display_new( $nt_obj, $q, $user );

    print $q->header (-charset=>"utf-8");
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

    $nt_obj->display_zone_list_options( $user, $q->param('nt_group_id'), $level, 1 );

    my $group = $nt_obj->get_group( nt_group_id => $q->param('nt_group_id') );

    if ( $q->param('new') ) {
        $nt_obj->display_nice_message(@$nicemessage) if $nicemessage;
        display_new_zone(@$newzone) if $newzone;
    }

    _display_edit( $nt_obj, $q );
    _display_delete( $nt_obj, $q );
    _display_delete_delegate( $nt_obj, $q );

    display_list( $nt_obj, $q, $group, $user );

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub _display_delete {
    my ($nt_obj, $q) = @_;

    return if ! $q->param('delete');
    return if ! $q->param('zone_list');

    my @zl = $q->param('zone_list');
    my $error = $nt_obj->delete_zones( zone_list => join( ',', @zl ) );

    if ( $error->{'error_code'} != 200 ) {
        $nt_obj->display_nice_error( $error, "Delete Zones" );
        return;
    };

    my $plural;
    $plural = 's' if scalar @zl > 1;
    $nt_obj->display_nice_message(
        "The " . ( $plural ? "zones were" : "zone was" )
            . " successfully removed.",
        "Zone$plural Removed"
    );
};

sub _display_delete_delegate {
    my ($nt_obj, $q) = @_;

    return if ! $q->param('deletedelegate');
    return if ! $q->param('nt_zone_id');
    return if ! $q->param('nt_group_id');

    my $error = $nt_obj->delete_zone_delegation(
        nt_zone_id  => $q->param('nt_zone_id'),
        nt_group_id => $q->param('nt_group_id')
    );
    if ( $error->{'error_code'} != 200 ) {
        $nt_obj->display_nice_error( $error, "Remove Zone Delegation" );
        return;
    };

    $nt_obj->display_nice_message(
        "The zone delegation was successfully removed.",
        "Delegation Removed" );
};

sub _display_edit {
    my ($nt_obj, $q) = @_;

    return if ! $q->param('edit');
    return if $q->param('Cancel');   # do nothing

    if ( $q->param('Save') ) {
        my @fields = qw/ nt_zone_id nt_group_id zone nameservers
            description serial refresh retry expire minimum mailaddr ttl /;

        my %data;
        foreach (@fields) { $data{$_} = $q->param($_); }
        $data{'nameservers'} = join( ',', $q->param('nameservers') );

        my $error = $nt_obj->edit_zone(%data);
        if ( $error->{'error_code'} != 200 ) {
            display_new_zone( $nt_obj, $q, $error, 'edit' );
        }
    }
    else {
        display_new_zone( $nt_obj, $q, '', 'edit' );
    }
};

sub _display_new {
    my ($nt_obj, $q, $user) = @_;

    return if ! $q->param('new');
    return if $q->param('Cancel');  # do nothing

    if ( ! $q->param('Create') ) {
        return [ $nt_obj, $q, '', 'new' ];
    };

    my $r = add_zone( $nt_obj, $q, $user ) or return;
    return ( $r->{newzone}, $r->{nicemessage} );
};

sub display_list {
    my ( $nt_obj, $q, $group, $user ) = @_;

    my $user_group = $nt_obj->get_group( nt_group_id  => $user->{'nt_group_id'} );

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
    unshift @columns, 'zone';

    my %params = ( nt_group_id => $q->param('nt_group_id') );
    my %sort_fields;
    $nt_obj->prepare_search_params( $q, \%labels, \%params, \%sort_fields, 100 );
    if ( ! %sort_fields ) {
        $sort_fields{'zone'} = { 'order' => 1, 'mod' => 'Ascending' };
    };

    my $rv = $nt_obj->get_group_zones(%params);

    if ( $q->param('edit_sortorder') ) {
        $nt_obj->display_sort_options( $q, \@columns, \%labels, 'group_zones.cgi',
            ['nt_group_id'], $include_subgroups );
    };
    if ( $q->param('edit_search') ) {
        $nt_obj->display_advanced_search( $q, \@columns, \%labels,
            'group_zones.cgi', ['nt_group_id'], $include_subgroups );
    };

    return $nt_obj->display_nice_error( $rv, "Get Group Zones" )
        if $rv->{'error_code'} != 200;

    my $zones = $rv->{'zones'};
    my $map   = $rv->{'group_map'};

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        next if ! $q->param($_);
        push @state_fields, "$_=" . $q->escape( $q->param($_) );
    }
    my $gid = $q->param('nt_group_id');
    my $state_string = join('&amp;', @state_fields, "nt_group_id=$gid");

    display_zone_actions( $nt_obj, $q, $user, $zones, $user_group );

    $nt_obj->display_search_rows( $q, $rv, \%params, 'group_zones.cgi',
        ['nt_group_id'], $include_subgroups );

    return if ! @$zones;

    $nt_obj->display_move_javascript( 'move_zones.cgi', 'zone' );
    $nt_obj->display_delegate_javascript( 'delegate_zones.cgi', 'zone' );

    print qq[
<form method="post" action="move_zones.cgi" target="move_win" name="list_form">
<table id="zoneList" class="fat">];

    display_list_header( \@columns, \%labels, \%sort_fields, $user_group, $rv );

    my $x     = 0;
    my $width = int( 100 / @columns ) . '%';
    my $bgcolor;
    my $hilite;
    foreach my $zone (@$zones) {
        $bgcolor = $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg';
        $hilite= $x % 2 == 0 ? 'light_hilite_bg' : 'dark_hilite_bg';
        $bgcolor = $hilite if $zone->{'nt_zone_id'} eq $q->param('new_zone_id');
        my $isdelegate = exists $zone->{'delegated_by_id'};

        print qq[
 <tr class="$bgcolor" id="zoneID$zone->{nt_zone_id}">];
        display_list_move_checkbox( $zone, $user, $user_group );
        display_list_zone_name( $zone, $width, $bgcolor, $gid );
        display_list_group_name( $zone, $width, $map ) if $include_subgroups;
        print qq[
  <td style="width:$width;" title="Description">$zone->{'description'}</td>];
        display_list_delegate_icon( $zone, $user, $user_group );
        display_list_delete_icon( $zone, $user, $gid, $state_string );
        print qq[
 </tr>];
    }

    print qq[
</table>
</form>
];
}

sub display_list_header {
    my ( $columns, $labels, $sort_fields, $user_group, $rv) = @_;
    print qq[
 <tr id="zoneListHeading" class=dark_grey_bg>];

    if ( $user_group->{'has_children'} ) {
        print qq[
  <td class="center no_pad" title="Move Zone">];
        if ( $rv->{'total'} != 1 ) {
            print qq[<input type="checkbox" name="select_all_or_none" value="on" onclick="selectAllorNone(document.list_form.obj_list, this.checked);" />],
        };
        print qq[</td>];
    }

    foreach my $col (@$columns) {
        if ( $sort_fields->{$col} ) {
            my $dir = uc( $sort_fields->{$col}->{'mod'} ) eq 'ASCENDING' ? 'up' : 'down';
            print qq[
  <td class="dark_bg center no_pad">
      $labels->{$col} &nbsp; &nbsp; (sort $sort_fields->{$col}->{'order'} <img src="$NicToolClient::image_dir/$dir.gif" alt="$dir">)</td>];
        }
        else {
            print qq[
  <td class=center> $labels->{$col} </td>];
        }
    }
    print qq[
  <td class="center width1" title="Delegate"></td>
  <td class="width1" title="Trash"></td>
 </tr>];
};

sub display_list_move_checkbox {
    my ( $zone, $user, $user_group ) = @_;
    my $isdelegate = exists $zone->{'delegated_by_id'};

    if ( $user->{'zone_create'} && !$isdelegate ) {
        if ( $user_group->{'has_children'} ) {
            print qq[
<td class="width1 center">
<input type="checkbox" name="obj_list" value="$zone->{nt_zone_id}" /></td>];
        };
    }
    elsif ( $user_group->{'has_children'} ) {
        print qq[
<td class="center width1">
<img src="$NicToolClient::image_dir/nobox.gif" alt="no box">
</td>];
    }
};

sub display_list_zone_name {
    my ( $zone, $width, $bgcolor, $gid ) = @_;

    my $isdelegate = exists $zone->{'delegated_by_id'};
    print qq[
  <td style="width:$width;" class="$bgcolor" title="Zone Name">
   <div class="no_pad margin0">];
    if ( !$isdelegate ) {
        print qq[
    <a href="zone.cgi?nt_zone_id=$zone->{'nt_zone_id'}&amp;nt_group_id=$zone->{'nt_group_id'}"><img src="$NicToolClient::image_dir/zone.gif" alt="zone">$zone->{'zone'}</a>];
    }
    else {
        my $img = "zone" . ( $zone->{'pseudo'} ? '-pseudo' : '-delegated' );
        print qq[
    <a href="zone.cgi?nt_zone_id=$zone->{'nt_zone_id'}&amp;nt_group_id=$gid">
    <img src="$NicToolClient::image_dir/$img.gif" alt="">
    $zone->{'zone'}</a>];
        if ( $zone->{'pseudo'} ) {
            print qq[&nbsp; <span class=disabled>($zone->{'delegated_records'} record];
            print 's' if $zone->{'delegated_records'} gt 1;
            print ')</span>';
        }
        else {
            print qq[&nbsp; <img src="$NicToolClient::image_dir/perm-];
            print 'no' if ! $zone->{'delegate_write'};
            print qq[write.gif" alt="">];
        }
    }
    print qq[
   </div>
  </td>];
};

sub display_list_group_name {
    my ( $zone, $width, $map ) = @_;
    my $gid = $zone->{'nt_group_id'};
    print qq[
 <td style="width:$width;">
  <div class="no_pad margin0">
    <img src="$NicToolClient::image_dir/group.gif" alt="">];
    my @list = (
        {   nt_group_id => $gid,
            name        => $zone->{'group_name'}
        }
    );
    if ($map && $map->{$gid}) { unshift @list, @{ $map->{ $gid } }; };

    my $url = qq[<a href="group.cgi?nt_group_id=];
    my $group_string = join( ' / ',
        map( qq[${url}$_->{'nt_group_id'}">$_->{'name'}</a>], @list ) );

    print qq[ $group_string
  </div>
 </td>];
};

sub display_list_delegate_icon {
    my ( $zone, $user, $user_group ) = @_;

    my $isdelegate = exists $zone->{'delegated_by_id'};

    print qq[
  <td class=center title="Delegate">];

    if (   $user_group->{'has_children'}
        && $user->{'zone_delegate'}
        && ( $isdelegate ? $zone->{'delegate_delegate'} : 1 ) )
    {
        print qq[<a href="javascript:void window.open('delegate_zones.cgi?obj_list=$zone->{'nt_zone_id'}', 'delegate_win', 'width=640,height=480,scrollbars,resizable=yes')"><img src="$NicToolClient::image_dir/delegate.gif" alt="Delegate Zone"></a></td>];
    }
    else {
        print qq[<img src="$NicToolClient::image_dir/delegate-disabled.gif" alt="disabled"></td>];
    }
};

sub display_list_delete_icon {
    my ( $zone, $user, $gid, $state_string ) = @_;
    my $isdelegate = exists $zone->{'delegated_by_id'};
    print qq[
<td class="width1" title="Delete">];
    if ( $user->{'zone_delete'} && !$isdelegate ) {
        print qq[<a href="group_zones.cgi?$state_string&amp;nt_group_id=$gid&amp;delete=1&amp;zone_list=$zone->{'nt_zone_id'}" onClick="return confirm('Delete $zone->{'zone'} and associated resource records?');"><img src="$NicToolClient::image_dir/trash.gif" alt="trash"></a></td>];
    }
    elsif ( $isdelegate && ( $user->{'zone_delegate'} && $zone->{'delegate_delete'} )) {
        print qq[<a href="group_zones.cgi?$state_string&amp;nt_group_id=$gid&amp;deletedelegate=1&amp;nt_zone_id=$zone->{'nt_zone_id'}" onClick="return confirm('Remove delegation of $zone->{'zone'}?');"><img src=$NicToolClient::image_dir/trash-delegate.gif alt="Remove Zone Delegation"></a></td>];
    }
    elsif ($isdelegate) {
        print qq[<img src="$NicToolClient::image_dir/trash-delegate-disabled.gif" alt="disabled trash"></td>];
    }
    else {
        print qq[<img src="$NicToolClient::image_dir/trash-disabled.gif" alt="disabled trash"></td>];
    }
};

sub display_new_zone {
    my ( $nt_obj, $q, $message, $edit ) = @_;

    print $q->start_form(
        -action => 'group_zones.cgi',
        -method => 'POST',
        -name   => 'new_zone'
    ),
    $q->hidden( -name => 'nt_group_id' ),
    $q->hidden( -name => $edit );

    foreach ( @{ $nt_obj->paging_fields() } ) {
        next if ! defined $q->param($_);
        print $q->hidden( -name => $_ );
    };

    $nt_obj->display_nice_error( $message, ucfirst($edit) . " Zone" ) if $message;

    my $zone_input = _get_new_zone_name( $q );
    my $ns_list   = _get_available_nameservers( $nt_obj, $q );
    my $descrip   = _get_new_description( $q );
    my $ttl_input = _get_new_ttl( $q );
    my $refresh_input = _get_new_refresh( $q );

    print qq[
<table class="fat">
 <tr class=dark_bg><td colspan=2 class="bold">New Zone</td></tr>
 <tr class=light_grey_bg>
  <td class=right>Zone:</td><td class="fat"> $zone_input </td>
 </tr>
 <tr class=light_grey_bg>
  <td class="right top">Nameservers:</td><td style="width:80%;"> $ns_list </td>
 </tr>
 <tr class=light_grey_bg>
  <td class="right top">Description:</td><td style="width:80%;"> $descrip </td>
 </tr>
 <tr class=light_grey_bg>
  <td class=right>TTL:</td><td style="width:80%;"> $ttl_input </td>
 </tr>
 <tr class=light_grey_bg>
  <td class=right>Refresh:</td><td style="width:80%;"> $refresh_input </td>
 </tr>
 <tr class=light_grey_bg>
  <td class=right>Retry:</td><td style="width:80%;">],
        $q->textfield(
        -name      => 'retry',
        -size      => 8,
        -maxlength => 10,
        -default   => $NicToolClient::default_zone_retry || $q->param('retry'),
        );
    print qq[<input type="button" value="Default" onClick="this.form.retry.value=$NicToolClient::default_zone_retry"> $NicToolClient::default_zone_retry </td></tr>

    <tr class=light_grey_bg>
    <td class=right>Expire:</td>
    <td style="width:80%;">],
        $q->textfield(
        -name      => 'expire',
        -size      => 8,
        -maxlength => 10,
        -default   => $NicToolClient::default_zone_expire || $q->param('expire'),
        ),
    qq[<input type="button" value="Default" onClick="this.form.expire.value=$NicToolClient::default_zone_expire"> $NicToolClient::default_zone_expire </td></tr>

    <tr class=light_grey_bg>
    <td class=right>Minimum:</td>
    <td style="width:80%;">],
        $q->textfield(
        -name      => 'minimum',
        -size      => 8,
        -maxlength => 10,
        -default   => $NicToolClient::default_zone_minimum || $q->param('minimum'),
        ),
    qq[<input type="button" value="Default" onClick="this.form.minimum.value=$NicToolClient::default_zone_minimum"> $NicToolClient::default_zone_minimum</td></tr>

    <tr class=light_grey_bg>
    <td class=right>MailAddr:</td>
    <td style="width:80%;">],
        $q->textfield(
        -id        => 'mailaddr',
        -name      => 'mailaddr',
        -size      => 35,
        -maxlength => 255,
        -default   => $NicToolClient::default_zone_mailaddr || $q->param('mailaddr'),
        -onFocus   => qq[if(this.form.mailaddr.value=='hostmaster.ZONE.TLD.'){this.form.mailaddr.value='hostmaster.'+this.form.zone.value+'.';};],
        ),
    qq[<input type="button" value="Default" onClick="this.form.mailaddr.value='hostmaster.'+this.form.zone.value+'.'"> $NicToolClient::default_zone_mailaddr </td></tr>

<tr class=light_grey_bg>
 <td class=right>
  <a href="javascript:void window.open('templates.cgi', 'templates_win', 'width=640,height=580,scrollbars,resizable=yes')">Template:</a></td>];
    my @templates = $nt_obj->zone_record_template_list;
    print qq[<td style="width:80%;">],
        $q->popup_menu(
        -name    => 'template',
        -values  => \@templates,
        -default => 'none'
        );
    my $ip = $q->param('newip') || "IP Address";
    my $mailip = $q->param('mailip');
    print qq[
IP: <input type="text" name="newip" size="25" maxlength="39" value="$ip" onFocus="if(this.value=='IP Address')this.value='';">
Mail IP: <input type="text" name="mailip" size="25" maxlength="39" value="$mailip">
    </td></tr>

    <tr class=dark_grey_bg><td colspan=2 class=center>],
    $q->submit( $edit eq 'edit' ? 'Save' : 'Create' ),
    $q->submit('Cancel'), "</td></tr></table>",
    $q->end_form;
}

sub _get_new_zone_name {
    my ($q) = @_;

    my $gid = $q->param('nt_group_id');

    return sprintf( $q->textfield(
        -id        => 'zone',
        -name      => 'zone',
        -size      => 40,
        -maxlength => 128,
        -onChange  => 'changeNewZoneName();',
        )
    )
    . qq[<a href="zones.cgi?nt_group_id=$gid">Batch</a>];
};

sub _get_available_nameservers {
    my ($nt_obj, $q) = @_;

    my $ns_tree = $nt_obj->get_usable_nameservers(
        nt_group_id => $q->param('nt_group_id')
    );

    if ( @{ $ns_tree->{'nameservers'} } == 0 ) {
        return "No available nameservers.";
    };

    my $ns_list;
    foreach ( 1 .. scalar( @{ $ns_tree->{'nameservers'} } ) ) {
        last if ( $_ > 10 );

        my $ns = $ns_tree->{'nameservers'}->[ $_ - 1 ];

        $ns_list .= sprintf( $q->checkbox(
            -name    => "nameservers",
            -checked => ( $_ < 4 ? 1 : 0 ),
            -value   => $ns->{'nt_nameserver_id'},
            -label   => "$ns->{'description'} ($ns->{'name'})"
            )
        )
        . "<BR>";
    };
    return $ns_list;
};

sub _get_new_description {
    my ($q) = @_;
    return sprintf $q->textarea(
        -name      => 'description',
        -cols      => 50,
        -rows      => 4,
        -maxlength => 255
    ),
};

sub _get_new_ttl {
    my ($q) = @_;

    return sprintf( $q->textfield(
        -name      => 'ttl',
        -size      => 8,
        -maxlength => 10,
        -default   => $NicToolClient::default_zone_ttl || $q->param('ttl'),
        )
    )
    .
    qq[<input type="button" value="Default" onClick="this.form.ttl.value=$NicToolClient::default_zone_ttl"> $NicToolClient::default_zone_ttl];
};

sub _get_new_refresh {
    my ( $q ) = @_;

    sprintf( $q->textfield(
        -name      => 'refresh',
        -size      => 8,
        -maxlength => 10,
        -default   => $NicToolClient::default_zone_refresh || $q->param('refresh'),
        )
    ) .
    qq[<input type="button" value="Default" onClick="this.form.refresh.value=$NicToolClient::default_zone_refresh"> $NicToolClient::default_zone_refresh ];
};

sub add_zone {
    my ($nt_obj, $q, $user) = @_;

    my @fields = qw/ nt_group_id zone nameservers description serial
                refresh retry expire minimum mailaddr template ttl /;
    my %data;
    foreach (@fields) { $data{$_} = $q->param($_); }
    $data{'nameservers'} = join( ',', $q->param('nameservers') );

    my $error = $nt_obj->new_zone(%data);
    if ( $error->{'error_code'} != 200 ) {
        return { newzone => [ $nt_obj, $q, $error, 'new' ] };
    }

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

    my $nice = "The Zone '$data{'zone'}' was successfully created.";
    if ($NicToolClient::edit_after_new_zone) {
        $q->param( -name => 'object', -value => 'zone' );
        $q->param( -name => 'obj_id', -value => $error->{'nt_zone_id'} );
        $nt_obj->redirect_from_log($q);
        return;
    }

    $q->param( -name  => 'new_zone_id', -value => $error->{'nt_zone_id'} );
    return { nicemessage => [ $nice, "Zone Created" ] };
};

sub add_zone_records {
    my ( $nt, $recs, $debug ) = @_;

    return if ! $recs;
    return if ! scalar @$recs;

    for ( my $i = 0; $i < scalar @$recs; $i++ ) {
        my $r = $nt->new_zone_record(
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
        if ( $r->{'error_code'} ne "200" ) {
            print "ZONE RECORD FAILED: $r->{'error_msg'}, $r->{'error_code'}\n";
            print Data::Dumper::Dumper($r);
        }
    }
}

sub display_zone_actions {
    my ($nt_obj, $q, $user, $zones, $user_group) = @_;

    my @state_fields;
    foreach ( @{ $nt_obj->paging_fields } ) {
        push @state_fields, "$_=" . $q->escape( $q->param($_) ) if $q->param($_);
    }
    my $gid = $q->param('nt_group_id');
    my $state_string = join('&amp;', @state_fields, "nt_group_id=$gid");

    print qq[
<div id="zoneActions" class="dark_grey_bg side_mar">
 <span class="bold">Zone List</span>
 <ul class=menu_r>
  <li class="first"><a href="group_zones_log.cgi?nt_group_id=$gid">View Zone Log</a></li>];

    if ( @$zones && $user_group->{'has_children'} ) {
        if ( $user->{'zone_delegate'} ) {
            print qq[\n<li><a href="javascript:void open_delegate(document.list_form.obj_list);">Delegate Selected Zones</a></li>]
        };
        print qq[\n<li><a href="javascript:void open_move(document.list_form.obj_list);">Move Selected Zones</a></li>];
    };

    if ( $user->{'zone_create'} ) {
        print qq[\n<li><a href="group_zones.cgi?$state_string&amp;new=1">New Zone</a></li>];
    }
    else {
        print qq[\n<li class=disabled>New Zone</li>];
    }

    print qq[
 </ul>
</div>];
};

