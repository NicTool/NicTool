package NicToolServer::Group;

#
# $Id: Group.pm 639 2008-09-13 04:43:46Z matt $
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

@NicToolServer::Group::ISA = qw(NicToolServer);

sub perm_fields_select {
    qq(
    nt_perm.group_write, 
    nt_perm.group_create,
    nt_perm.group_delete,

    nt_perm.zone_write,
    nt_perm.zone_create,
    nt_perm.zone_delegate,
    nt_perm.zone_delete,

    nt_perm.zonerecord_write,
    nt_perm.zonerecord_create,
    nt_perm.zonerecord_delegate,
    nt_perm.zonerecord_delete,
    
    nt_perm.user_write,
    nt_perm.user_create,
    nt_perm.user_delete,

    nt_perm.nameserver_write,
    nt_perm.nameserver_create,
    nt_perm.nameserver_delete,

    nt_perm.self_write,

    nt_perm.usable_ns0,
    nt_perm.usable_ns1,
    nt_perm.usable_ns2,
    nt_perm.usable_ns3,
    nt_perm.usable_ns4,
    nt_perm.usable_ns5,
    nt_perm.usable_ns6,
    nt_perm.usable_ns7,
    nt_perm.usable_ns8,
    nt_perm.usable_ns9
    );
}

sub new_group {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my $sql
        = "SELECT COUNT(*) FROM nt_group WHERE deleted = '0' "
        . "AND parent_group_id = "
        . $data->{'nt_group_id'} . ' '
        . "AND name = "
        . $dbh->quote( $data->{'name'} );

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    if ( $sth->fetch->[0] > 0 ) {
        $sth->finish;
        return $self->error_response( 600,
            'A group with that name already exists.' );
    }

    my @columns = qw(parent_group_id name);
    my @values;

    $data->{'parent_group_id'} = $data->{'nt_group_id'};

    my ( $action, $prev_data );

    $sql
        = "INSERT INTO nt_group("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";
    $action = 'added';

    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {
        return $self->error_response( 505, $dbh->errstr );
    }
    else {
        $error{'nt_group_id'} = $dbh->{'mysql_insertid'};
    }

    my $insertid = $dbh->{'mysql_insertid'};
    $data->{'modified_group_id'} = $insertid;
    if ($insertid) {
        my @permcols = grep { exists $data->{$_} }
            qw(group_create group_delete group_write
            zone_create zone_delegate zone_delete zone_write
            zonerecord_create zonerecord_delegate zonerecord_delete zonerecord_write
            user_create user_delete user_write self_write
            nameserver_create nameserver_delete nameserver_write);

        my @usable = split( /,/, $data->{'usable_nameservers'} );

        my @ns = map {"usable_ns$_"} ( 0 .. 9 );
        @usable = map { $usable[$_] || 0 } ( 0 .. 9 );

        #@usable = @usable[0..9] if scalar @usable gt 10 ;

        #cannot change permissions unless you have those permissions
        foreach (@permcols) {

            #$data->{$_} = 0 unless $data->{$_};
            $data->{$_} = 0 unless $data->{'user'}->{$_};
        }

        $sql
            = "INSERT INTO nt_perm("
            . join( ',', 'nt_group_id', @permcols, @ns )
            . ") VALUES("
            . join( ',',
            $insertid, map( $dbh->quote( $data->{$_} ), @permcols ), @usable )
            . ")";

        warn "$sql\n" if $self->debug_sql;

        unless ( $dbh->do($sql) ) {
            $error{'error_code'} = 505;
            $error{'error_msg'}  = $dbh->errstr;

# now we have to undo the nt_group insert otherwise we have a group with no perms, and that's a problem
            $sql = "DELETE FROM nt_group WHERE nt_group_id=$insertid";
            warn "$sql\n" if $self->debug_sql;
            unless ( $dbh->do($sql) ) {
                $error{'error_msg'} .= " (further:) " . $dbh->errstr;
            }
            return \%error;

        }
    }

    $self->add_to_group_subgroups( $insertid, $data->{'nt_group_id'}, 1000 );

    $self->log_group( $data, $action, $prev_data );

    #warn "returning error: ".Data::Dumper::Dumper(\%error);
    return \%error;
}

sub edit_group {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );
    my $sql;

    if ( $data->{'nt_group_id'} == $data->{'user'}->{'nt_group_id'} ) {
        return $self->error_response( 600,
            'You may not edit the group you belong to' );
    }

#if( $data->{'nt_group_id'} && !($self->is_subgroup($data->{'user'}->{'nt_group_id'}, $data->{'nt_group_id'})) ) {
#$error{'error_code'} = '403';
#$error{'error_msg'} = 'You are trying access an object that is not in your group tree';

    #return \%error;
    #}

    my @columns = grep { exists $data->{$_} } qw(parent_group_id name);

    #$data->{'parent_group_id'} = $data->{'nt_group_id'};

    my ( $action, $prev_data );
    $prev_data = $self->find_group( $data->{'nt_group_id'} );
    $data->{'modified_group_id'} = $data->{'nt_group_id'};
    if (@columns) {
        $sql
            = "UPDATE nt_group SET "
            . join( ',',
            map( "$_ = " . $dbh->quote( $data->{$_} ), @columns ) )
            . " WHERE nt_group_id = "
            . $data->{'nt_group_id'};
        $action = 'modified';

        warn "$sql\n" if $self->debug_sql;

        unless ( $dbh->do($sql) ) {
            return $self->error_response( 505, $dbh->errstr );
        }
        else {
            $error{'nt_group_id'} = $data->{'nt_group_id'};
        }
    }
    my @perms = qw(group_create group_delete group_write
        zone_create zone_delegate zone_delete zone_write
        zonerecord_create zonerecord_delegate zonerecord_delete zonerecord_write
        user_create user_delete user_write self_write
        nameserver_create nameserver_delete nameserver_write
    );
    my @permcols
        = grep { exists $data->{$_} && $data->{'user'}->{$_} } @perms;

    my @usable = split( /,/, $data->{'usable_nameservers'} );

#cannot change value of permissions for other objects if you don't have those permissions
#foreach(@permcols){
#delete $data->{$_} unless $data->{'user'}->{$_};
#}
    my %ns;

    #warn "usable is @usable and ".scalar @usable;
    #merge the usable nameservers settings
    $sql
        = "SELECT * from nt_perm "
        . " WHERE nt_group_id = "
        . $data->{'nt_group_id'};

    warn "$sql\n" if $self->debug_sql;
    my $sth = $dbh->prepare($sql);
    $sth->execute || return $self->error_response( 505, $dbh->errstr );
    my $gperm = $sth->fetchrow_hashref;
    %$prev_data = ( %$prev_data, map { $_ => $gperm->{$_} } @perms );

    #foreach(keys %$prev_data){
    #$data->{$_}=$prev_data->{$_} unless exists $data->{$_};
    #}
    if ($gperm) {

        my %datans = map { $_ => 1 } @usable;
        my %userns = map { $data->{'user'}->{$_} => 1 }
            grep { $data->{'user'}->{$_} } map {"usable_ns$_"} ( 0 .. 9 );
        my @oldns = map { $gperm->{$_} }
            grep { $gperm->{$_} } map {"usable_ns$_"} ( 0 .. 9 );
        my %groupns = map { $_ => 1 } @oldns;

        #for each of the previous usable_ns settings
        foreach my $n ( keys %groupns ) {
            if (   $userns{$n}
                or $self->get_access_permission( 'NAMESERVER', $n, 'read' ) )
            {

          #if the user has access to the nameserver
          #delete it or set it to true according to presence in the data array
                delete $groupns{$n} unless $datans{$n};
                $groupns{$n} = 1 if $datans{$n};
                delete $datans{$n};
            }
        }

        #add the nameservers that weren't present before
        foreach my $n ( keys %datans ) {
            $groupns{$n} = 1;
        }

#for the nameservers the user is allowed to use, add or delete based on data hash
#foreach my $n (keys %userns){
#warn "doing for $n\n";
#delete $groupns{$n} unless $datans{$n};
#$groupns{$n} = 1 if $datans{$n};
#warn "groupns for $n is $groupns{$n}\n";
#}
#warn "groupns is ".Data::Dumper::Dumper(\%groupns);
#leave the rest
        my @newns;
        foreach (@oldns) {
            push @newns, $_ if exists $groupns{$_};
            delete $groupns{$_};
        }
        foreach ( keys %groupns ) {
            push @newns, $_;
        }

        #warn "newns is @newns and ".scalar @newns;

        #@usable = map {$usable[$_]?$usable[$_]:0} (0 .. 9);
        @newns = map { $newns[$_] ? $newns[$_] : 0 } ( 0 .. 9 );
        %ns = map { ( "usable_ns$_" => $newns[$_] ) } ( 0 .. 9 );

        #warn " new ns is ".join(",",map{"$_=>$ns{$_}"} keys %ns);
    }
    else {
        return $self->error_response( 507,
            "No permissions found for group ID $data->{'nt_group_id'}." );
    }

    if ( @permcols + keys %ns ) {
        my @s = (
            map( "$_ = " . $dbh->quote( $data->{$_} ), @permcols ),
            map( "$_ = " . $ns{$_},                    keys %ns )
        );
        $sql
            = "UPDATE nt_perm SET "
            . join( ',', @s )
            . " WHERE nt_group_id = "
            . $data->{'nt_group_id'};

        warn "$sql\n" if $self->debug_sql;
        $action = 'modified';

        #TODO rollback the nt_group changes above if error?
        unless ( $dbh->do($sql) ) {
            return $self->error_response( 505, $dbh->errstr );
        }
    }
    if ($action) {
        $self->log_group( $data, $action, $prev_data );
    }

    return \%error;
}

sub add_to_group_subgroups {
    my ( $self, $gid, $parent_group_id, $rank ) = @_;
    my $dbh = $self->{'dbh'};

    my $sql
        = "INSERT INTO nt_group_subgroups(nt_group_id, nt_subgroup_id, rank) VALUES("
        . $dbh->quote($parent_group_id)
        . ", $gid, $rank)";
    $dbh->do($sql);
    warn "$sql\n" if $self->debug_sql;

    $sql = "SELECT parent_group_id FROM nt_group WHERE nt_group_id = "
        . $dbh->quote($parent_group_id);
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    my $row = $sth->fetch;

    if ( $row->[0] != 0 ) {
        $self->add_to_group_subgroups( $gid, $row->[0], $rank - 1 );
    }
}

sub delete_group {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

#unless( $self->is_subgroup($data->{'user'}->{'nt_group_id'}, $data->{'nt_group_id'}) ) {
#$error{'error_code'} = '403';
#$error{'error_msg'} = 'You are trying access an object that is not in your group tree';
#
#return \%error;
#}

    my $sql
        = "SELECT COUNT(*) FROM nt_zone WHERE deleted = '0' AND nt_group_id = "
        . $dbh->quote( $data->{'nt_group_id'} );
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    if ( $sth->fetch->[0] > 0 ) {
        return $self->error_response( 600,
            'You can\'t delete this group until you delete all of it\'s zones'
        );
    }

    $sql
        = "SELECT COUNT(*) FROM nt_user WHERE deleted = '0' AND nt_group_id = "
        . $dbh->quote( $data->{'nt_group_id'} );
    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    if ( $sth->fetch->[0] > 0 ) {
        return $self->error_response( 600,
            'You can\'t delete this group until you delete all of it\'s users'
        );
    }

    $sql
        = "SELECT COUNT(*) FROM nt_group WHERE deleted = '0' AND parent_group_id = "
        . $dbh->quote( $data->{'nt_group_id'} );
    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    if ( $sth->fetch->[0] > 0 ) {
        return $self->error_response( 600,
            'You can\'t delete this group until you delete all of it\'s sub-groups'
        );
    }

    my $group_data = $self->find_group( $data->{'nt_group_id'} );
    $group_data->{'user'} = $data->{'user'};

    $sql = "UPDATE nt_group SET deleted = '1' WHERE nt_group_id = "
        . $dbh->quote( $data->{'nt_group_id'} );
    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {
        return $self->error_response( 600, $dbh->errstr );
    }

    $self->log_group( $group_data, 'deleted' );

    return \%error;
}

sub get_group {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT nt_group.*, "
        . $self->perm_fields_select
        . " FROM nt_group,nt_perm WHERE nt_group.nt_group_id = "
        . $dbh->quote( $data->{'nt_group_id'} )
        . " AND nt_perm.nt_group_id = nt_group.nt_group_id";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    my %rv;

    $sth->execute || return $self->error_response( 505, $dbh->errstr );
    my $ref = $sth->fetchrow_hashref;
    if ($ref) {
        %rv               = %$ref;
        $rv{'error_code'} = 200;
        $rv{'error_msg'}  = 'OK';
    }
    else {
        $rv{'error_code'} = 600;
        $rv{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    if ( $rv{'nt_group_id'} ) {
        $sql = "SELECT COUNT(*) FROM nt_group WHERE deleted='0' AND parent_group_id = "
            . $dbh->quote( $rv{'nt_group_id'} );
        $sth = $dbh->prepare($sql);
        warn "$sql\n" if $self->debug_sql;
        $sth->execute;
        $rv{'has_children'} = $sth->fetch->[0];
        $sth->finish;
    };

    delete $rv{'nt_user_id'};

    return \%rv;
}

sub get_group_groups {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT nt_group.*, "
        . $self->perm_fields_select
        . " FROM nt_group,nt_perm WHERE nt_group.deleted = '0' AND nt_perm.deleted='0' AND nt_group.parent_group_id = "
        . $dbh->quote( $data->{'nt_group_id'} )
        . " AND nt_perm.nt_group_id = nt_group.nt_group_id ORDER BY nt_group.name";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    my $r_data = { error_code => 200, error_msg => 'OK' };
    $r_data->{'groups'} = [];

    if ( $sth->execute ) {
        while ( my $row = $sth->fetchrow_hashref ) {
            delete $row->{'nt_user_id'};
            push( @{ $r_data->{'groups'} }, $row );
        }
    }
    else {
        $r_data->{'error_code'} = '600';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    if ( ref( $r_data->{'groups'} ) ) {
        foreach ( @{ $r_data->{'groups'} } ) {
            $sql
                = "SELECT COUNT(*) FROM nt_group WHERE deleted = '0' AND parent_group_id = "
                . $dbh->quote( $_->{'nt_group_id'} );
            $sth = $dbh->prepare($sql);
            warn "$sql\n" if $self->debug_sql;
            $sth->execute;
            $_->{'has_children'} = $sth->fetch->[0];
            $sth->finish;
        }
    }

    return $r_data;
}

sub get_group_subgroups {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %field_map = (
        group =>
            { timefield => 0, quicksearch => 1, field => 'nt_group.name' },
        parent_group_id => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_group.parent_group_id'
        },
    );

    my $conditions = $self->format_search_conditions( $data, \%field_map );
    my $sortby = $self->format_sort_conditions( $data, \%field_map,
        "nt_group.name" );

    my @group_list;
    if ( $data->{'include_subgroups'} ) {
        @group_list = (
            $data->{'nt_group_id'},
            @{ $self->get_subgroup_ids( $data->{'start_group_id'} ) }
        );
    }
    else {
        @group_list = ( $data->{'nt_group_id'} );
    }

    my $r_data = { error_code => 200, error_msg => 'OK', groups => [] };

    my $sql = "SELECT COUNT(*) FROM nt_group ";
    $sql .= "WHERE deleted = '0' AND nt_group.parent_group_id IN("
        . join( ',', @group_list ) . ") "
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    $r_data->{'total'} = $sth->fetch->[0];
    $sth->finish;

    $self->set_paging_vars( $data, $r_data );

    $r_data->{'total'}++ if ( $data->{'include_parent'} );

    if ( $r_data->{'total'} == 0 ) {
        return $r_data;
    }

    $sql = "SELECT nt_group.* FROM nt_group "
        . "WHERE deleted = '0' AND nt_group.parent_group_id IN("
        . join( ',', @group_list ) . ") ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{'start'} - 1 ) . ", $r_data->{'limit'}";

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    if ( $sth->execute ) {
        my %groups;
        while ( my $row = $sth->fetchrow_hashref ) {
            $sql
                = "SELECT COUNT(*) FROM nt_group WHERE deleted = '0' AND parent_group_id = "
                . $dbh->quote( $row->{'nt_group_id'} );
            my $sh = $dbh->prepare($sql);
            warn "$sql\n" if $self->debug_sql;
            $sh->execute || return $self->error_response( 505, $dbh->errstr );
            $row->{'has_children'} = $sh->fetch->[0];
            $sh->finish;

            push( @{ $r_data->{'groups'} }, $row );

            $groups{ $row->{'nt_group_id'} } = 1;
        }

        unshift(
            @{ $r_data->{'groups'} },
            $self->find_group( $data->{'user'}->{'nt_group_id'} )
        ) if ( $data->{'include_parent'} );

        $r_data->{'group_map'}
            = $self->get_group_map( $data->{'start_group_id'},
            [ keys %groups ] );
    }
    else {
        $r_data->{'error_code'} = '600';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    warn "get_group_subgroups: " . Data::Dumper::Dumper($r_data)
        if $self->debug_result;

    return $r_data;
}

sub get_global_application_log {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %field_map = (
        timestamp => {
            timefield   => 1,
            quicksearch => 0,
            field       => 'nt_user_global_log.timestamp'
        },
        user =>
            { timefield => 0, quicksearch => 1, field => 'nt_user.username' },
        action => {
            timefield   => 0,
            quicksearch => 1,
            field       => 'nt_user_global_log.action'
        },
        object => {
            timefield   => 0,
            quicksearch => 1,
            field       => 'nt_user_global_log.object'
        },
        title => {
            timefield   => 0,
            quicksearch => 1,
            field       => 'nt_user_global_log.title'
        },
        description => {
            timefield   => 0,
            quicksearch => 1,
            field       => 'nt_user_global_log.description'
        },
    );

    my $conditions = $self->format_search_conditions( $data, \%field_map );
    my $sortby = $self->format_sort_conditions( $data, \%field_map,
        "nt_user_global_log.timestamp DESC" );

    my @group_list;
    if ( $data->{'include_subgroups'} ) {
        @group_list = (
            $data->{'nt_group_id'},
            @{ $self->get_subgroup_ids( $data->{'nt_group_id'} ) }
        );
    }
    else {
        @group_list = ( $data->{'nt_group_id'} );
    }

    my $r_data = { error_code => 200, error_msg => 'OK', log => [] };

    my $sql = "SELECT COUNT(*) FROM nt_user_global_log, nt_user ";
    $sql .= "WHERE nt_user_global_log.nt_user_id = nt_user.nt_user_id ";
    $sql
        .= "AND nt_user.nt_group_id IN("
        . join( ',', @group_list ) . ") "
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    warn "$sql\n" if $self->debug_sql;

    my $sth = $dbh->prepare($sql);
    $sth->execute;
    $r_data->{'total'} = $sth->fetch->[0];
    $sth->finish;

    $self->set_paging_vars( $data, $r_data );

    if ( $r_data->{'total'} == 0 ) {
        return $r_data;
    }

    $sql
        = "SELECT nt_user_global_log.*, "
        . "       CONCAT(nt_user.first_name, \" \", nt_user.last_name, \" (\", nt_user.username, \")\") as user, "
        . "       nt_user.nt_group_id, "
        . "       nt_group.name as group_name "
        . "FROM nt_user_global_log, nt_user, nt_group "
        . "WHERE nt_user_global_log.nt_user_id = nt_user.nt_user_id AND nt_user.nt_group_id IN("
        . join( ',', @group_list )
        . ") AND nt_user.nt_group_id = nt_group.nt_group_id ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{'start'} - 1 ) . ", $r_data->{'limit'}";

    warn "$sql\n" if $self->debug_sql;
    $sth = $dbh->prepare($sql);

    if ( $sth->execute ) {
        my %groups;
        while ( my $row = $sth->fetchrow_hashref ) {
            push( @{ $r_data->{'log'} }, $row );

            $groups{ $row->{'nt_group_id'} } = 1;
        }

        $r_data->{'group_map'}
            = $self->get_group_map( $data->{'start_group_id'},
            [ keys %groups ] );
    }
    else {
        $r_data->{'error_code'} = '600';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    return $r_data;
}

sub get_group_branch {
    my ( $self, $data ) = @_;

    my $user_group = $data->{'user'}->{'nt_group_id'};
    my $cur_group  = $data->{'nt_group_id'};
    my $last_group = '';

    my $dbh = $self->{'dbh'};

    my %rv = ( error_code => 200, error_msg => 'OK', groups => [] );

    while ( $last_group != $user_group ) {
        my $sql
            = "SELECT * FROM nt_group WHERE deleted = '0' AND nt_group_id = $cur_group";
        my $sth = $dbh->prepare($sql);
        warn "$sql\n" if $self->debug_sql;
        unless ( $sth->execute ) {
            $rv{'error_code'} = 600;
            $rv{'error_msg'}  = $dbh->errstr;

            return \%rv;
        }

        my $group = $sth->fetchrow_hashref;
        $sth->finish;
        $last_group = $cur_group;
        $cur_group  = $group->{'parent_group_id'};

        unshift( @{ $rv{'groups'} }, $group );
    }

    return \%rv;
}

sub log_group {
    my ( $self, $data, $action, $prev_data ) = @_;

    my $dbh = $self->{'dbh'};
    my @columns
        = qw(nt_group_id parent_group_id nt_user_id action timestamp modified_group_id name);
    my @values;

    my $user = $data->{'user'};
    $data->{'modified_group_id'} ||= $data->{'nt_group_id'};
    $data->{'nt_user_id'} = $user->{'nt_user_id'};
    $data->{'action'}     = $action;
    $data->{'timestamp'}  = time();

    my $sql
        = "INSERT INTO nt_group_log("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";

    warn "$sql\n" if $self->debug_sql;

    $dbh->do($sql) || warn $dbh->errstr;

    # TODO test this..
    my @g_columns
        = qw(nt_user_id timestamp action object object_id log_entry_id title description);

    $data->{'object'}       = 'group';
    $data->{'log_entry_id'} = $dbh->{'mysql_insertid'};
    $data->{'title'} = $data->{'name'} || $prev_data->{'name'} || '(group)';
    $data->{'object_id'} = $data->{'modified_group_id'};

    if ( $action eq 'modified' ) {    # modified
        $prev_data->{'modified_group_id'}
            = delete( $prev_data->{'nt_group_id'} );

        $data->{'description'} = $self->diff_changes( $data, $prev_data );
    }
    elsif ( $action eq 'deleted' ) {    #deleted
        $data->{'description'} = 'deleted group';
    }
    elsif ( $action eq 'added' ) {      #added
        $data->{'description'} = 'initial creation';
    }

  #warn "action $action logging data: ".Data::Dumper::Dumper($data);
  #warn "action $action logging prev_data: ".Data::Dumper::Dumper($prev_data);
    $sql
        = "INSERT INTO nt_user_global_log("
        . join( ',', @g_columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @g_columns ) ) . ")";
    warn "$sql\n" if $self->debug_sql;
    $dbh->do($sql) || warn $dbh->errstr;

}

sub find_group {
    my ( $self, $nt_group_id ) = @_;

    my $dbh = $self->{'dbh'};
    my $sql = "SELECT * FROM nt_group WHERE nt_group_id = $nt_group_id";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    return $sth->fetchrow_hashref || {};
}

1;
