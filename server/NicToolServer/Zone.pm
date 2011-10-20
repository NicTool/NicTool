package NicToolServer::Zone;

# vim:set ts=4:
#
# $Id: Zone.pm 667 2008-10-01 01:33:43Z matt $
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

@NicToolServer::Zone::ISA = qw(NicToolServer);

sub get_zone {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my $sql = "SELECT nt_zone.* FROM nt_zone WHERE nt_zone_id = "
        . $dbh->quote( $data->{'nt_zone_id'} );
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    my %rv;
    if ( $sth->execute ) {
        %rv = %{ $sth->fetchrow_hashref };
        $rv{'nameservers'} = $self->pack_nameservers( \%rv );

        $rv{'error_code'} = 200;
        $rv{'error_msg'}  = 'OK';
        if ( my $del = $self->get_param_meta( 'nt_zone_id', 'delegate' ) ) {

# this info comes from NicToolServer.pm when it checks for access perms to the objects
            my %mapping = (
                delegated_by_id   => 'delegated_by_id',
                delegated_by_name => 'delegated_by_name',
                pseudo            => 'pseudo',

                #perm_read=>'delegate_read',
                perm_write               => 'delegate_write',
                perm_delete              => 'delegate_delete',
                perm_delegate            => 'delegate_delegate',
                zone_perm_add_records    => 'delegate_add_records',
                zone_perm_delete_records => 'delegate_delete_records',

                #perm_move=>'delegate_move',
                #perm_full=>'delegate_full',
                group_name => 'group_name'
            );
            foreach my $key ( keys %mapping ) {
                $rv{ $mapping{$key} } = $del->{$key};
            }
        }
    }
    else {
        $rv{'error_code'} = 600;
        $rv{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;
    return \%rv;
}

sub pack_nameservers {
    my ( $self, $data ) = @_;

    my @temp;
    for ( my $i = 0; $i < 10; $i++ ) {
        push( @temp, $data->{ 'ns' . $i } ) if ( $data->{ 'ns' . $i } );
        delete( $data->{ 'ns' . $i } );
    }
    unless (@temp) {
        $data->{'nameservers'} = [];
        return [];
    }

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT nt_nameserver.*,nt_zone.nt_zone_id FROM nt_nameserver,nt_zone WHERE nt_nameserver.nt_nameserver_id IN ("
        . join( ',', @temp )
        . ") AND nt_zone.nt_zone_id = "
        . $dbh->quote( $data->{nt_zone_id} );
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    my @ns;
    while ( my $data = $sth->fetchrow_hashref ) {
        push( @ns, $data );
    }
    $sth->finish;

    $data->{'nameservers'} = \@ns;
}

sub get_zone_log {
    my ( $self, $data ) = @_;

    my $sql
        = "SELECT nt_zone_log.*, nt_group.name AS group_name, nt_zone_log.action AS action, CONCAT(nt_user.first_name, \" \", nt_user.last_name) as user "
        . "FROM nt_zone_log, nt_group, nt_user "
        . "WHERE nt_zone_log.nt_group_id = nt_group.nt_group_id "

       #. "AND nt_zone_log.nt_log_action_id = nt_log_action.nt_log_action_id "
        . "AND nt_zone_log.nt_user_id = nt_user.nt_user_id "
        . "AND nt_zone_log.nt_zone_id = $data->{'nt_zone_id'} "
        . "ORDER BY timestamp DESC";

    my $sth = $self->{'dbh'}->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    my %rv;
    if ( $sth->execute ) {
        $rv{'data'} = [];

        while ( my $data = $sth->fetchrow_hashref ) {
            push( @{ $rv{'data'} }, $data );
        }

        $rv{'error_code'} = 200;
        $rv{'error_msg'}  = 'OK';
    }
    else {
        $rv{'error_code'} = 600;
        $rv{'error_msg'}  = $sth->errstr;
    }

    $sth->finish;
    return \%rv;
}

sub get_zone_record_log {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %field_map = (
        action => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record_log.action'
        },
        user =>
            { timefield => 0, quicksearch => 0, field => 'nt_user.username' },
        timestamp => {
            timefield   => 1,
            quicksearch => 0,
            field       => 'nt_zone_record_log.timestamp'
        },
        name => {
            timefield   => 0,
            quicksearch => 1,
            field       => 'nt_zone_record_log.name'
        },
        description => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record_log.description'
        },
        type => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record_log.type'
        },
        address => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record_log.address'
        },
        weight => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record_log.weight'
        },
        priority => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record_log.priority'
        },
        other => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record_log.other'
        },
    );

    my $conditions = $self->format_search_conditions( $data, \%field_map );
    my $sortby = $self->format_sort_conditions( $data, \%field_map,
        "nt_zone_record_log.timestamp DESC" );

    my $r_data = { error_code => 200, error_msg => 'OK', log => [] };

    my $sql
        = "SELECT COUNT(*) FROM "
        . "nt_zone_record_log, nt_zone_record, nt_user "
        . "WHERE nt_zone_record_log.nt_zone_record_id = nt_zone_record.nt_zone_record_id "

#. "AND nt_zone_record_log.nt_log_action_id = nt_log_action.nt_log_action_id "
        . "AND nt_zone_record_log.nt_user_id = nt_user.nt_user_id "
        . "AND nt_zone_record_log.nt_zone_id = "
        . $dbh->quote( $data->{'nt_zone_id'} )
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    $r_data->{'total'} = $sth->fetch->[0];
    $sth->finish;

    $self->set_paging_vars( $data, $r_data );

    if ( $r_data->{'total'} == 0 ) {
        return $r_data;
    }

    $sql
        = "SELECT nt_zone_record_log.*, nt_zone_record_log.action as action, CONCAT(nt_user.first_name, \" \", nt_user.last_name, \" (\", nt_user.username, \")\") as user FROM "
        . "nt_zone_record_log, nt_zone_record, nt_user "
        . "WHERE nt_zone_record_log.nt_zone_record_id = nt_zone_record.nt_zone_record_id "

#. "AND nt_zone_record_log.nt_log_action_id = nt_log_action.nt_log_action_id "
        . "AND nt_zone_record_log.nt_user_id = nt_user.nt_user_id "
        . "AND nt_zone_record_log.nt_zone_id = "
        . $dbh->quote( $data->{'nt_zone_id'} )
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
    $sql .= " ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{'start'} - 1 ) . ", $r_data->{'limit'}";

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    if ( $sth->execute ) {
        while ( my $row = $sth->fetchrow_hashref ) {
            push( @{ $r_data->{'log'} }, $row );
        }
    }
    else {
        $r_data->{'error_code'} = '600';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    return $r_data;
}

sub get_group_zones_log {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %field_map = (
        action => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_log.action'
        },
        user =>
            { timefield => 0, quicksearch => 0, field => 'nt_user.username' },
        timestamp => {
            timefield   => 1,
            quicksearch => 0,
            field       => 'nt_zone_log.timestamp'
        },
        zone =>
            { timefield => 0, quicksearch => 1, field => 'nt_zone_log.zone' },
        description => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_log.description'
        },
        ttl =>
            { timefield => 0, quicksearch => 0, field => 'nt_zone_log.ttl' },
        group_name =>
            { timefield => 0, quicksearch => 0, field => 'nt_group.name' },
    );

    my $conditions = $self->format_search_conditions( $data, \%field_map );
    my $sortby = $self->format_sort_conditions( $data, \%field_map,
        "nt_zone_log.timestamp DESC" );

    my $r_data = { error_code => 200, error_msg => 'OK', log => [] };

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

    my $sql
        = "SELECT COUNT(*) FROM "
        . "nt_zone_log, nt_zone, nt_user, nt_group "
        . "WHERE nt_zone_log.nt_zone_id = nt_zone.nt_zone_id "
        . "AND nt_zone_log.nt_user_id = nt_user.nt_user_id "
        . "AND nt_zone.nt_group_id = nt_group.nt_group_id "
        . "AND nt_zone.nt_group_id IN("
        . join( ',', @group_list ) . ")"
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    $r_data->{'total'} = $sth->fetch->[0];
    $sth->finish;

    $self->set_paging_vars( $data, $r_data );

    if ( $r_data->{'total'} == 0 ) {
        return $r_data;
    }

    $sql
        = "SELECT nt_zone_log.*, CONCAT(nt_user.first_name, \" \", nt_user.last_name, \" (\", nt_user.username, \")\") as user, nt_zone.nt_group_id, nt_group.name as group_name FROM "
        . "nt_zone_log, nt_zone, nt_user, nt_group "
        . "WHERE nt_zone_log.nt_zone_id = nt_zone.nt_zone_id "
        . "AND nt_zone_log.nt_user_id = nt_user.nt_user_id "
        . "AND nt_zone.nt_group_id = nt_group.nt_group_id "
        . "AND nt_zone.nt_group_id IN("
        . join( ',', @group_list ) . ")"
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
    $sql .= " ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{'start'} - 1 ) . ", $r_data->{'limit'}";

    $sth = $dbh->prepare($sql);

    warn "$sql\n" if $self->debug_sql;

    if ( $sth->execute ) {
        my %groups;
        while ( my $row = $sth->fetchrow_hashref ) {
            push( @{ $r_data->{'log'} }, $row );
            $groups{ $row->{'nt_group_id'} } = 1;
        }

        $r_data->{'group_map'} = $self->get_group_map( $data->{'nt_group_id'},
            [ keys %groups ] );
    }
    else {
        $r_data->{'error_code'} = '600';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    return $r_data;
}

sub get_group_zones {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %field_map = (
        zone => { timefield => 0, quicksearch => 1, field => 'nt_zone.zone' },
        group_name => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone.nt_group_id'
        },
        description => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone.description'
        },
    );

    $field_map{'group_name'}
        = { timefield => 0, quicksearch => 0, field => 'nt_group.name' }
        if $data->{'include_subgroups'};

    my $conditions = $self->format_search_conditions( $data, \%field_map );

    #warn "conditions: ".Data::Dumper::Dumper($conditions);
    my @group_list = $data->{'nt_group_id'};
    if ( $data->{'include_subgroups'} ) {
        push @group_list,
            @{ $self->get_subgroup_ids( $data->{'nt_group_id'} ) };
    }

    my $r_data = { 'error_code' => 200, 'error_msg' => 'OK', zones => [] };

    #count total number of zones inside the groups
    my $sql
        = "SELECT COUNT(*) FROM nt_zone "
        . " WHERE nt_zone.nt_group_id IN ("
        . join( ",", @group_list ) . ") "
        . " AND nt_zone.deleted='"
        . ( $data->{'search_deleted'} ? '1' : '0' ) . "' ";

    $sql .= (
        @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || return $self->error_response( 508, $dbh->errstr );
    $r_data->{'total'} = $sth->fetch->[0];
    $sth->finish;

    if (0) {
## slink 2007-02-01 :
#  this query is highly ineffecient, due to massive left joining, result set
#  becomes really big (with redundancies removed by COUNT(DISTINCT ) afterwards)
#
#  rather than getting the count first and then getting the delegates,
#  we might as well get the delegates now
##
        #add count of delegates/pseudo delegates,
        my $sql2
            = "SELECT COUNT(DISTINCT nt_zone.nt_zone_id) FROM nt_group "
            . "LEFT JOIN nt_delegate as zdel ON "
            . "zdel.nt_group_id= $data->{'nt_group_id'} AND zdel.nt_object_type='ZONE'  "
            . "LEFT JOIN nt_delegate as zrdel ON "
            . "zrdel.nt_group_id= $data->{'nt_group_id'} AND zrdel.nt_object_type='ZONERECORD' "
            . "LEFT JOIN nt_zone_record ON "
            . "zrdel.nt_object_id=nt_zone_record.nt_zone_record_id AND nt_zone_record.deleted ='0' "
            . "INNER JOIN nt_zone ON "
            . " nt_zone.nt_zone_id=zdel.nt_object_id OR nt_zone.nt_zone_id=nt_zone_record.nt_zone_id "
            . " AND ( nt_zone_record.deleted='0' OR nt_zone_record.deleted IS NULL )";

        $sql2 .= (
            @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

        $sth = $dbh->prepare($sql2);
        warn "$sql2\n" if $self->debug_sql;
        $sth->execute || return $self->error_response( 508, $dbh->errstr );
        $r_data->{'total'} += $sth->fetch->[0];
        $sth->finish;
    }

    my %delegates;

  #get zones that are 'pseudo' delegates: some of their records are delegated.
    $sql
        = " SELECT nt_zone.nt_zone_id, "
        . "       count(*) as delegated_records,"
        . "       nt_delegate.delegated_by_id,"
        . "       nt_delegate.delegated_by_name,"
        . "       1 as pseudo "
        . " FROM nt_delegate "
        . " INNER JOIN nt_zone_record ON nt_delegate.nt_object_id=nt_zone_record.nt_zone_record_id "
        . " INNER JOIN nt_zone ON nt_zone.nt_zone_id=nt_zone_record.nt_zone_id "
        . " WHERE nt_delegate.nt_group_id=$data->{'nt_group_id'} AND nt_delegate.nt_object_type='ZONERECORD'"
        . " GROUP BY nt_zone.nt_zone_id";
    $sql .= (
        @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || return $self->error_response( 505, $sth->errstr );
    while ( my $z = $sth->fetchrow_hashref ) {
        $delegates{ $z->{'nt_zone_id'} } = $z;
    }

    #get zones that are normal delegates
    $sql
        = " SELECT nt_zone.nt_zone_id,"
        . "      d.delegated_by_id,"
        . "      d.delegated_by_name,"
        . "      d.perm_write as delegate_write,"
        . "      d.perm_delete as delegate_delete,"
        . "      d.perm_delegate as delegate_delegate,"
        . "      d.zone_perm_add_records as delegate_add_records,"
        . "      d.zone_perm_delete_records as delegate_delete_records"
        . " FROM  nt_delegate as d"
        . " INNER JOIN nt_zone ON nt_zone.nt_zone_id=d.nt_object_id"
        . " WHERE d.nt_group_id=$data->{'nt_group_id'} AND d.nt_object_type='ZONE'";
    $sql .= (
        @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || return $self->error_response( 505, $sth->errstr );
    while ( my $z = $sth->fetchrow_hashref ) {
        $delegates{ $z->{'nt_zone_id'} } = $z;
    }
    my @zones = keys %delegates;

    $r_data->{'total'} += scalar(@zones);

    $self->set_paging_vars( $data, $r_data );

    return $r_data if ( $r_data->{'total'} == 0 );

    my $sortby;
    if ( $r_data->{'total'} > 10000 ) {

# if > than 10,000 zones, don't explicity ORDER BY -- mysql takes too long. --ai
        $sortby = $self->format_sort_conditions( $data, \%field_map, "" );
    }
    else {

        # get the name of the group
        $sql
            = "SELECT name from nt_group where nt_group_id=$data->{'nt_group_id'}";
        my $sth = $dbh->prepare($sql);
        warn "$sql\n" if $self->debug_sql;
        $sth->execute;
        my $group_name = $sth->fetch->[0];
        $sth->finish;

        if ( $group_name =~ /reverse/ ) {
            $sortby = $self->format_sort_conditions( $data, \%field_map,
                "cast(nt_zone.zone as signed)" );
        }
        else {
            $sortby = $self->format_sort_conditions( $data, \%field_map,
                "nt_zone.zone" );
        }
    }

    #get all zones in user's group (or subgroups) and the delegated zones
    $sql
        = "SELECT nt_zone.nt_zone_id, "
        . "       nt_zone.zone, "
        . "       nt_zone.nt_group_id as owner_group_id, "
        . "       nt_zone.description, "
        . "       nt_zone.deleted, "
        . "	   nt_group.name as group_name, "
        . "	   nt_group.nt_group_id "
        . "FROM nt_zone "
        . "INNER JOIN nt_group ON nt_zone.nt_group_id=nt_group.nt_group_id "
        . "WHERE "
        . "    nt_zone.deleted='"
        . ( $data->{'search_deleted'} ? '1' : '0' ) . "' "
        . "    AND ( "
        . "          nt_group.nt_group_id IN("
        . join( ',', @group_list ) . ") "
        . (
        @zones
        ? "       OR nt_zone.nt_zone_id IN (" . join( ',', @zones ) . " ) "
        : ''
        ) . "         ) ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "GROUP BY nt_zone.nt_zone_id ";
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{'start'} - 1 ) . ", $r_data->{'limit'}";

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    if ( $sth->execute ) {
        my %groups;
        while ( my $row = $sth->fetchrow_hashref ) {
            my $zid = $row->{'nt_zone_id'};

            #copy delegation information
            if ( $delegates{$zid} ) {
                my @k = keys %{ $delegates{$zid} };
                @$row{@k} = @{ $delegates{$zid} }{@k};
            }
            push( @{ $r_data->{'zones'} }, $row );
            $groups{ $row->{'nt_group_id'} } = 1;
        }

        $r_data->{'group_map'} = $self->get_group_map( $data->{'nt_group_id'},
            [ keys %groups ] );
    }
    else {
        $r_data->{'error_code'} = '505';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    return $r_data;
}

sub get_zone_records {
    my ( $self, $data ) = @_;

    my $dbh      = $self->{'dbh'};
    my $group_id = $data->{'user'}->{'nt_group_id'};

    my %field_map = (
        name => {
            timefield   => 0,
            quicksearch => 1,
            field       => 'nt_zone_record.name'
        },
        description => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record.description'
        },
        type => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record.type'
        },
        address => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record.address'
        },
        weight => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record.weight'
        },
        priority => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record.priority'
        },
        other => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_zone_record.other'
        },
    );

    my $conditions = $self->format_search_conditions( $data, \%field_map );

    my $r_data = { error_code => 200, error_msg => 'OK', records => [] };
    my $sql;
    my $del = $self->get_param_meta( "nt_zone_id", "delegate" );
    if ( $del && $del->{'pseudo'} ) {
        $sql
            = "SELECT COUNT(*) FROM nt_zone_record "
            . "LEFT JOIN nt_delegate ON (nt_delegate.nt_group_id=$group_id AND nt_delegate.nt_object_id=nt_zone_record.nt_zone_record_id AND nt_delegate.nt_object_type='ZONERECORD' ) "
            . "WHERE nt_zone_record.nt_zone_id = $data->{'nt_zone_id'} "
            . "AND nt_zone_record.deleted = '0' "
            . "AND nt_delegate.deleted = '0' "
            . (
            @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
    }
    else {
        $sql
            = "SELECT COUNT(*) FROM nt_zone_record WHERE nt_zone_record.deleted = '0' AND nt_zone_record.nt_zone_id = $data->{'nt_zone_id'}"
            . (
            @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
    }
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    $r_data->{'total'} = $sth->fetch->[0];
    $sth->finish;

    $self->set_paging_vars( $data, $r_data );

    my $sortby;
    if ( $r_data->{'total'} == 0 ) {
        return $r_data;
    }
    elsif ( $r_data->{'total'} > 10000 ) {

        # sorting really large zones takes too long
        $sortby = $self->format_sort_conditions( $data, \%field_map, "" );
    }
    else {

        # get the name of the zone
        $sql
            = "SELECT zone from nt_zone where nt_zone_id=$data->{'nt_zone_id'}";
        my $sth = $dbh->prepare($sql);
        warn "$sql\n" if $self->debug_sql;
        $sth->execute;
        my $zone_name = $sth->fetch->[0];
        $sth->finish;

        if ( $zone_name =~ /in-addr.arpa/ ) {

            # thanks Patrick Woo at telus
            $sortby = $self->format_sort_conditions( $data, \%field_map,
                "cast(nt_zone_record.name as signed)" );
        }
        else {
            $sortby = $self->format_sort_conditions( $data, \%field_map,
                "nt_zone_record.name" );
        }
    }
    my $join;
    if ( $del && $del->{'pseudo'} ) {
        $join = "INNER";
    }
    else {
        $join = "LEFT";
    }

    #if($del && $del->{'pseudo'}){
    $sql
        = "SELECT nt_zone_record.*, "
        . "       nt_delegate.delegated_by_id, "
        . "       nt_delegate.delegated_by_name, "

        #. "       nt_delegate.perm_read as delegate_read, "
        . "       nt_delegate.perm_write as delegate_write, "

        #. "       nt_delegate.perm_move as delegate_move, "
        . "       nt_delegate.perm_delete as delegate_delete, "
        . "       nt_delegate.perm_delegate as delegate_delegate, "
        . "       nt_delegate.zone_perm_add_records as delegate_add_records, "
        . "       nt_delegate.zone_perm_delete_records as delegate_delete_records, "

        #. "       nt_delegate.perm_full as delegate_full, "
        . "FROM nt_zone_record "
        . "$join JOIN nt_delegate ON (nt_delegate.nt_group_id=$group_id AND nt_delegate.nt_object_id=nt_zone_record.nt_zone_record_id AND nt_delegate.nt_object_type='ZONERECORD' ) "
        . "WHERE nt_zone_record.nt_zone_id = $data->{'nt_zone_id'} "
        . "AND nt_zone_record.deleted = '0' "
        . "AND ( nt_delegate.deleted = '0' OR nt_delegate.deleted IS NULL ) "

        ;
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{'start'} - 1 ) . ", $r_data->{'limit'}";

#}
#else{
#$sql = "SELECT nt_zone_record.*, "
#. "FROM nt_zone_record "
#. "WHERE deleted = '0' "
#. "AND nt_zone_record.nt_zone_id = $data->{'nt_zone_id'} ";
#$sql .= 'AND (' . join(' ', @$conditions) . ') ' if @$conditions;
#$sql .= "ORDER BY " . join(', ', @$sortby) . " " if( @$sortby );
#$sql .= "LIMIT " . ($r_data->{'start'} - 1) . ", $r_data->{'limit'}";
#}

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    if ( $sth->execute ) {
        while ( my $row = $sth->fetchrow_hashref ) {
            foreach (
                qw(delegated_by_id delegated_by_name delegate_read delegate_write delegate_move delegate_delete delegate_delegate delegate_full)
                )
            {
                delete $row->{$_} if $row->{$_} eq '';
            }
            push( @{ $r_data->{'records'} }, $row );
        }
    }
    else {
        $r_data->{'error_code'} = '600';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    return $r_data;
}

sub get_group_zone_query_log {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %field_map = (
        timestamp => {
            timefield   => 1,
            quicksearch => 0,
            field       => 'nt_nameserver_qlog.timestamp'
        },
        nameserver => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver.name'
        },
        zone => { timefield => 0, quicksearch => 0, field => 'nt_zone.zone' },
        query => {
            timefield   => 0,
            quicksearch => 1,
            field       => 'nt_nameserver_qlog.query'
        },
        qtype => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver_qlog.qtype'
        },
        flag => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver_qlog.flag'
        },
        ip => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver_qlog.ip'
        },
        port => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver_qlog.port'
        }
    );

    my $conditions = $self->format_search_conditions( $data, \%field_map );

    my $r_data = { 'search_result' => [] };

    my @zone_ids;
    my $sql
        = "SELECT nt_zone_id FROM nt_zone WHERE nt_group_id = $data->{'nt_group_id'}";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    while ( my $row = $sth->fetch ) {
        push( @zone_ids, $row->[0] );
    }
    $sth->finish;

    if (@zone_ids) {
        my $sql
            = "SELECT COUNT(*) FROM nt_nameserver_qlog, nt_zone, nt_nameserver WHERE nt_zone.nt_zone_id IN("
            . join( ',', @zone_ids )
            . ") AND nt_nameserver_qlog.nt_zone_id = nt_zone.nt_zone_id AND nt_nameserver_qlog.nt_nameserver_id = nt_nameserver.nt_nameserver_id "
            . (
            @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
        $sth = $dbh->prepare($sql);
        warn "$sql\n" if $self->debug_sql;
        $sth->execute;
        $r_data->{'total'} = $sth->fetch->[0];
        $sth->finish;
    }
    else {
        $r_data->{'total'} = 0;
    }

    $self->set_paging_vars( $data, $r_data );

    my $sortby;
    if ( $r_data->{'total'} == 0 ) {
        return $r_data;
    }
    elsif ( $r_data->{'total'} > 10000 ) {
        $sortby = $self->format_sort_conditions( $data, \%field_map, "" );
    }
    else {
        $sortby = $self->format_sort_conditions( $data, \%field_map,
            "timestamp DESC" );
    }

    $sql
        = "SELECT nt_nameserver_qlog.*, "
        . "nt_zone.zone, "
        . "nt_nameserver.name AS nameserver "
        . "FROM nt_nameserver_qlog, nt_zone, nt_nameserver "
        . "WHERE nt_zone.nt_zone_id IN("
        . join( ',', @zone_ids ) . ") "
        . "AND nt_nameserver_qlog.nt_zone_id = nt_zone.nt_zone_id "
        . "AND nt_nameserver_qlog.nt_nameserver_id = nt_nameserver.nt_nameserver_id ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{'start'} - 1 ) . ", $r_data->{'limit'}";

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    if ( $sth->execute ) {
        while ( my $row = $sth->fetchrow_hashref ) {
            push( @{ $r_data->{'search_result'} }, $row );
        }
    }
    else {
        $r_data->{'error_code'} = '600';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    return $r_data;
}

sub save_zone {
    my ( $self, $data ) = @_;

    warn "XXX: Zone::save_zone is deprecated as of NicToolServer 2.0: "
        . Data::Dumper::Dumper($data);
    return $self->error_result( 503, 'save_zone, use new_zone or edit_zone' );
}

sub new_zone {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my @columns
        = qw(mailaddr description refresh retry expire minimum ttl serial nt_group_id zone);
    my @values;

    my $sql;
    my $log_action;
    my $prev_data;
    my $default_serial = 0;

    $self->unpack_nameservers( $data, \@columns )
        if ( $data->{'nameservers'} );

    if ( $data->{'serial'} eq '' ) {
        $data->{'serial'} = $self->bump_serial('new');
        $default_serial = 1;
    }

    $sql
        = "INSERT INTO nt_zone("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";
    $log_action = 'added';

    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {
        $error{'error_code'} = 600;
        $error{'error_msg'}  = $dbh->errstr;
        return \%error;
    }

    $error{'nt_zone_id'} = $data->{'nt_zone_id'} = $dbh->{'mysql_insertid'}
        if ( $log_action eq 'added' );

    $self->log_zone( $data, $log_action, $prev_data, $default_serial );

    return \%error;
}

sub edit_zone {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );
    if ( my $del = $self->get_param_meta( "nt_zone_id", "delegate" ) ) {
        delete $data->{'nt_group_id'};
        return $self->error_response( 404,
            'Not allowed to undelete delegated zones.' )
            if $data->{'deleted'} eq '0';
    }
    if ( exists $data->{'deleted'} and $data->{'deleted'} != '0' ) {
        delete $data->{'deleted'};
    }
    my @columns = grep { exists $data->{$_} }
        qw(nt_group_id mailaddr description refresh retry expire minimum ttl serial deleted);
    my @values;

    unless ( @columns || exists $data->{'nameservers'} ) {
        return $self->error_response(200);
    }

    my $sql;
    my $log_action;
    my $prev_data;
    my $default_serial = 0;

    #$self->unpack_nameservers($data,\@columns) if ($data->{'nameservers'});

    $prev_data  = $self->find_zone( $data->{'nt_zone_id'} );
    $log_action = $prev_data->{'deleted'}
        && ( $data->{'deleted'} eq '0' ) ? 'recovered' : 'modified';

    my %ns;
    if ( exists $data->{'nameservers'} ) {

        #my $nss=$self->NicToolServer::Nameserver::get_usable_nameservers;
        #return $nss if $nss->{'error_code'} ne 200;
        #warn Data::Dumper::Dumper($nss);
        my %datans = map { $_ => 1 } split /,/, $data->{'nameservers'};

       #my %userns =map{$_->{'nt_nameserver_id'}=>1} @{$nss->{'nameservers'}};
        my @oldns = map { $prev_data->{$_} }
            grep { $prev_data->{$_} } map {"ns$_"} ( 0 .. 9 );
        my %zonens = map { $_ => 1 } @oldns;
        my %newns;
        foreach my $n ( keys %datans, keys %zonens ) {
            if ( $self->get_access_permission( 'NAMESERVER', $n, 'read' ) ) {
                if ( !$datans{$n} ) {

                    #warn "YES: can read NAMESERVER $n: DELETE newns $n";
                    delete $newns{$n};
                }
                else {

                    #warn "YES: can read NAMESERVER $n: SET newns $n to 1";
                    $newns{$n} = 1;
                }
            }
            else {
                $newns{$n} = $zonens{$n} if $zonens{$n};

                #warn "NO: leaving zonens as $zonens{$n}";
            }
        }

        %newns = map { $_ => 1 } grep { $newns{$_} } keys %newns;

        my @newns = keys %newns;
        @newns = map { $newns[$_] ? $newns[$_] : 0 } ( 0 .. 9 );

        #warn "SET: newns is ".join(" ",@newns);
        %ns = map { ( "ns$_" => $newns[$_] ) } ( 0 .. 9 );
    }

    if ( $data->{'serial'} eq '' ) {
        $data->{'serial'} = $self->bump_serial( $data->{'nt_zone_id'} );
        $default_serial = 1;
    }

    $sql = "UPDATE nt_zone SET "
        . join( ',',
        map( "$_ = " . $dbh->quote( $data->{$_} ), @columns ),
        map( "$_ = " . $ns{$_},                    keys %ns ) )
        . " WHERE nt_zone_id = "
        . $data->{'nt_zone_id'};

    $data->{'nt_group_id'} = $prev_data->{'nt_group_id'}
        unless $data->{'nt_group_id'};

    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {
        $error{'error_code'} = 600;
        $error{'error_msg'}  = $dbh->errstr;
        return \%error;
    }

    $error{'nt_zone_id'} = $data->{'nt_zone_id'} = $dbh->{'mysql_insertid'}
        if ( $log_action eq 'added' );

    $self->log_zone( $data, $log_action, $prev_data, $default_serial );

    return \%error;
}

sub unpack_nameservers {
    my ( $self, $data, $columns ) = @_;

    my @temp = split( ',', $data->{'nameservers'} );
    for ( 0 .. 9 ) {
        $data->{ 'ns' . $_ } = 0;
        push( @{$columns}, 'ns' . $_ );
    }
    my $i = 0;
    foreach my $ns (@temp) {
        $data->{ 'ns' . $i } = "$ns";
        $i++;
    }

}

sub log_zone {
    my ( $self, $data, $action, $prev_data, $default_serial ) = @_;

    my $dbh = $self->{'dbh'};
    my @columns
        = qw(nt_group_id nt_zone_id nt_user_id action timestamp zone mailaddr description refresh retry expire ttl);
    my @values;

    # only log serial if it wasn't set by default
    $default_serial
        ? delete( $data->{'serial'} )
        : push( @columns, 'serial' );

    my $user = $data->{'user'};
    $data->{'nt_user_id'} = $user->{'nt_user_id'};
    $data->{'action'}     = $action;
    $data->{'timestamp'}  = time();
    $data->{'zone'}       = $prev_data->{'zone'} unless ( $data->{'zone'} );

    foreach ( keys %$prev_data ) {
        $data->{$_} = $prev_data->{$_} unless $data->{$_};
    }

    my $sql
        = "INSERT INTO nt_zone_log("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";

    warn "$sql\n" if $self->debug_sql;
    $dbh->do($sql) || warn $dbh->errstr;

    my @g_columns
        = qw(nt_user_id timestamp action object object_id log_entry_id title description);

    $data->{'object'}       = 'zone';
    $data->{'log_entry_id'} = $dbh->{'mysql_insertid'};
    $data->{'title'}        = $data->{'zone'} || $prev_data->{'zone'};
    $data->{'object_id'}    = $data->{'nt_zone_id'};

    if ( $action eq 'modified' ) {
        $data->{'description'} = $self->diff_changes( $data, $prev_data );
    }
    elsif ( $action eq 'deleted' ) {
        $data->{'description'} = 'deleted zone and all associated records';
    }
    elsif ( $action eq 'added' ) {
        $data->{'description'} = 'initial creation';
    }
    elsif ( $action eq 'moved' ) {
        $data->{'description'}
            = "moved from $data->{'old_group_name'} to $data->{'group_name'}";
    }
    elsif ( $action eq 'recovered' ) {

     #TODO add 'recovered' to the enum for global_application_log action field
     #$data->{'action'}='added';
        $data->{'description'} = "recovered zone from deleted bin";
    }

    $sql
        = "INSERT INTO nt_user_global_log("
        . join( ',', @g_columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @g_columns ) ) . ")";
    warn "$sql\n" if $self->debug_sql;
    $dbh->do($sql) || warn $dbh->errstr;

}

sub delete_zones {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my %groups = map { $_, 1 } (
        $data->{'user'}->{'nt_group_id'},
        @{ $self->get_subgroup_ids( $data->{'user'}->{'nt_group_id'} ) }
    );

    my $sql = "SELECT * FROM nt_zone WHERE nt_zone.nt_zone_id IN("
        . $data->{'zone_list'} . ")";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;

    my $record_obj = new NicToolServer::Zone::Record( $self->{'Apache'},
        $self->{'client'}, $self->{'dbh'} );

    while ( my $zone_data = $sth->fetchrow_hashref ) {
        next unless ( $groups{ $zone_data->{'nt_group_id'} } );

        $sql
            = "UPDATE nt_zone SET deleted = '1' WHERE nt_zone_id = $zone_data->{'nt_zone_id'}";
        $zone_data->{'user'} = $data->{'user'};
        warn "$sql\n" if $self->debug_sql;
        unless ( $dbh->do($sql) ) {
            $error{'error_code'} = 600;
            $error{'error_msg'}  = $dbh->errstr;
            next;
        }

        $self->log_zone( $zone_data, 'deleted', $zone_data, 0 );

        next;

        # delete associated zone_record records
        $sql
            = "SELECT * from nt_zone_record where deleted = '0' AND nt_zone_id = "
            . $dbh->quote( $zone_data->{'nt_zone_id'} );
        my $sth = $dbh->prepare($sql);
        warn "$sql\n" if $self->debug_sql;
        $sth->execute;
        while ( my $zr = $sth->fetchrow_hashref ) {
            $zr->{'user'} = $data->{'user'};
            $record_obj->delete_zone_record( $zr, $zone_data );
        }
    }
    $sth->finish;

    return \%error;
}

sub move_zones {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my %groups = map { $_, 1 } (
        $data->{'user'}->{'nt_group_id'},
        @{ $self->get_subgroup_ids( $data->{'user'}->{'nt_group_id'} ) }
    );

    my $new_group
        = $self->NicToolServer::Group::find_group( $data->{'nt_group_id'} );

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT nt_zone.*, nt_group.name as old_group_name FROM nt_zone, nt_group WHERE nt_zone.nt_group_id = nt_group.nt_group_id AND nt_zone_id IN("
        . $data->{'zone_list'} . ")";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    unless ( $sth->execute ) {
        $rv{'error_code'} = 600;
        $rv{'error_msg'}  = $sth->errstr;
        return \%rv;
    }

    while ( my $row = $sth->fetchrow_hashref ) {
        next unless ( $groups{ $row->{'nt_group_id'} } );

        $sql
            = "UPDATE nt_zone SET nt_group_id = "
            . $dbh->quote( $data->{'nt_group_id'} )
            . " WHERE nt_zone_id = $row->{'nt_zone_id'}";
        warn "$sql\n" if $self->debug_sql;
        if ( $dbh->do($sql) ) {
            my %zone = ( %$row, user => $data->{'user'} );
            $zone{'nt_group_id'} = $data->{'nt_group_id'};
            $zone{'group_name'}  = $new_group->{'name'};

            $self->log_zone( \%zone, 'moved', $row, 0 );
        }
    }
    $sth->finish;

    return \%rv;
}

sub get_zone_list {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK' );

#my %groups = map { $_, 1 } ($data->{'user'}->{'nt_group_id'}, @{ $self->get_subgroup_ids($data->{'user'}->{'nt_group_id'}) });

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT * FROM nt_zone WHERE deleted = '0' AND nt_zone_id IN("
        . $data->{'zone_list'}
        . ") ORDER BY zone";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    unless ( $sth->execute ) {
        $rv{'error_code'} = 600;
        $rv{'error_msg'}  = $sth->errstr;
        return \%rv;
    }

    my %delegatemapping = (
        delegated_by_id   => 'delegated_by_id',
        delegated_by_name => 'delegated_by_name',
        pseudo            => 'pseudo',

        #perm_read=>'delegate_read',
        perm_write               => 'delegate_write',
        perm_delete              => 'delegate_delete',
        perm_delegate            => 'delegate_delegate',
        zone_perm_add_records    => 'delegate_add_records',
        zone_perm_delete_records => 'delegate_delete_records',

        #perm_move=>'delegate_move',
        #perm_full=>'delegate_full',
        group_name => 'group_name'
    );
    while ( my $row = $sth->fetchrow_hashref ) {

        #next unless( $groups{ $row->{'nt_group_id'} } );
        if (my $del = $self->get_param_meta(
                "zone_list:$row->{'nt_zone_id'}", 'delegate'
            )
            )
        {
            foreach my $key ( keys %delegatemapping ) {
                $row->{ $delegatemapping{$key} } = $del->{$key};
            }
        }
        push( @{ $rv{'zones'} }, $row );
    }
    $sth->finish;

    return \%rv;
}

sub find_zone {
    my ( $self, $nt_zone_id ) = @_;

    my $dbh = $self->{'dbh'};
    my $sql = "SELECT * FROM nt_zone WHERE nt_zone_id = $nt_zone_id";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || warn $dbh->errstr . ": sql :$sql";
    return $sth->fetchrow_hashref || {};
}

sub zone_exists {
    my ( $self, $zone, $zid ) = @_;
    my $dbh = $self->{'dbh'};

    my $sql
        = "SELECT nt_zone_id,nt_group_id FROM nt_zone WHERE deleted = '0' AND nt_zone_id != "
        . $dbh->quote($zid)
        . " AND zone = "
        . $dbh->quote($zone);
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    my $href = $sth->fetchrow_hashref;

    return ref($href) ? $href : 0;
}

1;
