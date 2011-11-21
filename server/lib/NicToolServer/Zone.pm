package NicToolServer::Zone;
# ABSTRACT: manage (add,delete,move,find) DNS zones

use strict;

@NicToolServer::Zone::ISA = qw(NicToolServer);

sub get_zone {
    my ( $self, $data ) = @_;

    my $sql = "SELECT * FROM nt_zone WHERE nt_zone_id = ?";
    my $zones = $self->exec_query( $sql, $data->{nt_zone_id} )
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

    my %rv = ( %{ $zones->[0] },
        'nameservers' => $self->pack_nameservers( $zones->[0] ),
        'error_code'  => 200,
        'error_msg'   => 'OK',
    );

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
    return \%rv;
}

sub pack_nameservers {
    my ( $self, $data ) = @_;

    # $data = { ns0=>?, ns1=>?, ns2....};
    my $query
        = "SELECT nt_nameserver_id FROM nt_zone_nameserver WHERE nt_zone_id=?";
    my @nsids = $self->dbix->query( $query, $data->{nt_zone_id} )->flat;
    return [] if scalar @nsids == 0;

    my $sql
        = "SELECT nt_nameserver.*,nt_zone.nt_zone_id FROM nt_nameserver,nt_zone 
        WHERE nt_nameserver.nt_nameserver_id IN ("
        . join( ',', @nsids )
        . ") AND nt_zone.nt_zone_id = ?";
    $data->{nameservers} = $self->exec_query( $sql, $data->{nt_zone_id} );
}

sub get_zone_log {
    my ( $self, $data ) = @_;

    my $sql
        = "SELECT nt_zone_log.*, nt_group.name AS group_name, nt_zone_log.action AS action, CONCAT(nt_user.first_name, \" \", nt_user.last_name) as user "
        . "FROM nt_zone_log, nt_group, nt_user "
        . "WHERE nt_zone_log.nt_group_id = nt_group.nt_group_id "

       #. "AND nt_zone_log.nt_log_action_id = nt_log_action.nt_log_action_id "
        . "AND nt_zone_log.nt_user_id = nt_user.nt_user_id "
        . "AND nt_zone_log.nt_zone_id = $data->{nt_zone_id} "
        . "ORDER BY timestamp DESC";

    my $zone_logs = $self->exec_query($sql)
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,

        };

    my %rv = (
        data       => [],
        error_code => 200,
        error_msg  => 'OK',
    );

    foreach my $data (@$zone_logs) {
        push( @{ $rv{data} }, $data );
    }

    return \%rv;
}

sub get_zone_record_log {
    my ( $self, $data ) = @_;

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

    my $dbh = $self->{dbh};

    my $sql = "SELECT COUNT(*) AS count FROM 
        nt_zone_record_log, nt_zone_record, nt_user 
        WHERE nt_zone_record_log.nt_zone_record_id = nt_zone_record.nt_zone_record_id "

#       . "AND nt_zone_record_log.nt_log_action_id = nt_log_action.nt_log_action_id "
        . "AND nt_zone_record_log.nt_user_id = nt_user.nt_user_id "
        . "AND nt_zone_record_log.nt_zone_id = "
        . $dbh->quote( $data->{nt_zone_id} )
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $c = $self->exec_query($sql);
    $r_data->{total} = $c->[0]{count};

    $self->set_paging_vars( $data, $r_data );

    return $r_data if $r_data->{total} == 0;

    $sql = "SELECT nt_zone_record_log.*, nt_zone_record_log.action as action, 
        CONCAT(nt_user.first_name, \" \", nt_user.last_name, \" (\", nt_user.username, \")\") as user
        FROM nt_zone_record_log, nt_zone_record, nt_user
          WHERE nt_zone_record_log.nt_zone_record_id = nt_zone_record.nt_zone_record_id "

#          AND nt_zone_record_log.nt_log_action_id = nt_log_action.nt_log_action_id "
        . "AND nt_zone_record_log.nt_user_id = nt_user.nt_user_id 
           AND nt_zone_record_log.nt_zone_id = "
        . $dbh->quote( $data->{nt_zone_id} )
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
    $sql .= " ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{start} - 1 ) . ", $r_data->{limit}";

    my $zr_logs = $self->exec_query($sql)
        or return {
        error_code => '600',
        error_msg  => $self->{dbh}->errstr,
        };

    foreach my $row (@$zr_logs) {
        push( @{ $r_data->{log} }, $row );
    }

    return $r_data;
}

sub get_group_zones_log {
    my ( $self, $data ) = @_;

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
    if ( $data->{include_subgroups} ) {
        @group_list = (
            $data->{nt_group_id},
            @{ $self->get_subgroup_ids( $data->{nt_group_id} ) }
        );
    }
    else {
        @group_list = ( $data->{nt_group_id} );
    }

    my $sql = "SELECT COUNT(*) AS count FROM
          nt_zone_log, nt_zone, nt_user, nt_group
        WHERE nt_zone_log.nt_zone_id = nt_zone.nt_zone_id
          AND nt_zone_log.nt_user_id = nt_user.nt_user_id
          AND nt_zone.nt_group_id = nt_group.nt_group_id
          AND nt_zone.nt_group_id IN("
        . join( ',', @group_list ) . ")"
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $c = $self->exec_query($sql);
    $r_data->{total} = $c->[0]{count};

    $self->set_paging_vars( $data, $r_data );

    return $r_data if $r_data->{total} == 0;

    $sql = "SELECT nt_zone_log.*, 
        CONCAT(nt_user.first_name, \" \", nt_user.last_name, \" (\", nt_user.username, \")\") as user, nt_zone.nt_group_id, nt_group.name as group_name 
        FROM nt_zone_log, nt_zone, nt_user, nt_group
          WHERE nt_zone_log.nt_zone_id = nt_zone.nt_zone_id
           AND nt_zone_log.nt_user_id = nt_user.nt_user_id
           AND nt_zone.nt_group_id = nt_group.nt_group_id
           AND nt_zone.nt_group_id IN("
        . join( ',', @group_list ) . ")"
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
    $sql .= " ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{start} - 1 ) . ", $r_data->{limit}";

    my $zone_logs = $self->exec_query($sql)
        or return {
        error_code => '600',
        error_msg  => $self->{dbh}->errstr,
        };

    my %groups;
    foreach my $row (@$zone_logs) {
        push( @{ $r_data->{log} }, $row );
        $groups{ $row->{nt_group_id} } = 1;
    }

    $r_data->{group_map}
        = $self->get_group_map( $data->{nt_group_id}, [ keys %groups ] );

    return $r_data;
}

sub get_group_zones {
    my ( $self, $data ) = @_;

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

    $field_map{group_name}
        = { timefield => 0, quicksearch => 0, field => 'nt_group.name' }
        if $data->{include_subgroups};

    my $conditions = $self->format_search_conditions( $data, \%field_map );

    #warn "conditions: ".Data::Dumper::Dumper($conditions);
    my @group_list = $data->{nt_group_id};
    if ( $data->{include_subgroups} ) {
        push @group_list,
            @{ $self->get_subgroup_ids( $data->{nt_group_id} ) };
    }

    my $r_data = { 'error_code' => 200, 'error_msg' => 'OK', zones => [] };

    #count total number of zones inside the groups
    my $sql
        = "SELECT COUNT(*) AS count FROM nt_zone "
        . " WHERE nt_zone.nt_group_id IN ("
        . join( ",", @group_list ) . ") "
        . " AND nt_zone.deleted='"
        . ( $data->{search_deleted} ? '1' : '0' ) . "' ";

    $sql .= (
        @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $c = $self->exec_query($sql)
        or return $self->error_response( 508, $self->{dbh}->errstr );
    $r_data->{total} = $c->[0]{count};

    my %delegates;

  #get zones that are 'pseudo' delegates: some of their records are delegated.
    $sql = " SELECT nt_zone.nt_zone_id,
                 count(*) as delegated_records,
               nt_delegate.delegated_by_id,
               nt_delegate.delegated_by_name,
               1 as pseudo
         FROM nt_delegate
         INNER JOIN nt_zone_record ON nt_delegate.nt_object_id=nt_zone_record.nt_zone_record_id
         INNER JOIN nt_zone ON nt_zone.nt_zone_id=nt_zone_record.nt_zone_id
       WHERE nt_delegate.nt_group_id=$data->{nt_group_id} AND nt_delegate.nt_object_type='ZONERECORD'
         GROUP BY nt_zone.nt_zone_id";
    $sql .= (
        @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $delegs = $self->exec_query($sql)
        or return $self->error_response( 505, $self->{dbh}->errstr );

    foreach my $z (@$delegs) {
        $delegates{ $z->{nt_zone_id} } = $z;
    }

    #get zones that are normal delegates
    $sql = " SELECT nt_zone.nt_zone_id,
              d.delegated_by_id,
              d.delegated_by_name,
              d.perm_write as delegate_write,
              d.perm_delete as delegate_delete,
              d.perm_delegate as delegate_delegate,
              d.zone_perm_add_records as delegate_add_records,
              d.zone_perm_delete_records as delegate_delete_records
         FROM  nt_delegate as d
         INNER JOIN nt_zone ON nt_zone.nt_zone_id=d.nt_object_id
         WHERE d.nt_group_id=$data->{nt_group_id} AND d.nt_object_type='ZONE'";
    $sql .= (
        @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    $delegs = $self->exec_query($sql)
        or return $self->error_response( 505, $self->{dbh}->errstr );
    foreach my $z (@$delegs) {
        $delegates{ $z->{nt_zone_id} } = $z;
    }
    my @zones = keys %delegates;

    $r_data->{total} += scalar @zones;

    $self->set_paging_vars( $data, $r_data );

    return $r_data if $r_data->{total} == 0;

    my $sortby;
    if ( $r_data->{total} > 10000 ) {
        $sortby = $self->format_sort_conditions( $data, \%field_map, "" );

# if > than 10,000 zones, don't explicity ORDER BY -- mysql takes too long. --ai
    }
    else {

        # get the name of the group
        $sql = "SELECT name from nt_group where nt_group_id=?";
        my $g = $self->exec_query( $sql, $data->{nt_group_id} );
        my $group_name = $g->[0]{name};

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
    $sql = "SELECT nt_zone.nt_zone_id,
               nt_zone.zone,
               nt_zone.nt_group_id as owner_group_id,
               nt_zone.description,
               nt_zone.deleted,
        	   nt_group.name as group_name,
        	   nt_group.nt_group_id
        FROM nt_zone
          INNER JOIN nt_group ON nt_zone.nt_group_id=nt_group.nt_group_id
        WHERE nt_zone.deleted='"
        . ( $data->{search_deleted} ? '1' : '0' ) . "' "
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
    $sql .= "LIMIT " . ( $r_data->{start} - 1 ) . ", $r_data->{limit}";

    my $all_zones = $self->exec_query($sql)
        or return {
        error_code => '505',
        error_msg  => $self->{dbh}->errstr,
        };

    my %groups;
    foreach my $row (@$all_zones) {
        my $zid = $row->{nt_zone_id};

        #copy delegation information
        if ( $delegates{$zid} ) {
            my @k = keys %{ $delegates{$zid} };
            @$row{@k} = @{ $delegates{$zid} }{@k};
        }
        push( @{ $r_data->{zones} }, $row );
        $groups{ $row->{nt_group_id} } = 1;
    }

    $r_data->{group_map}
        = $self->get_group_map( $data->{nt_group_id}, [ keys %groups ] );

    return $r_data;
}

sub get_zone_records {
    my ( $self, $data ) = @_;

    my $group_id = $data->{user}{nt_group_id};

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
    if ( $del && $del->{pseudo} ) {
        $sql
            = "SELECT COUNT(*) AS count FROM nt_zone_record "
            . "LEFT JOIN nt_delegate ON (nt_delegate.nt_group_id=$group_id AND nt_delegate.nt_object_id=nt_zone_record.nt_zone_record_id AND nt_delegate.nt_object_type='ZONERECORD' ) "
            . "WHERE nt_zone_record.nt_zone_id = $data->{nt_zone_id} "
            . "AND nt_zone_record.deleted=0 "
            . "AND nt_delegate.deleted=0 "
            . (
            @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
    }
    else {
        $sql = "SELECT COUNT(*) AS count FROM nt_zone_record 
            WHERE nt_zone_record.deleted=0 AND nt_zone_record.nt_zone_id = $data->{nt_zone_id}"
            . (
            @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
    }
    my $c = $self->exec_query($sql);
    $r_data->{total} = $c->[0]{count};

    $self->set_paging_vars( $data, $r_data );

    my $sortby;
    if ( $r_data->{total} == 0 ) {
        return $r_data;
    }
    elsif ( $r_data->{total} > 10000 ) {

        # sorting really large zones takes too long
        $sortby = $self->format_sort_conditions( $data, \%field_map, "" );
    }
    else {

        # get the name of the zone
        $sql = "SELECT zone from nt_zone where nt_zone_id=?";
        my $znames = $self->exec_query( $sql, $data->{nt_zone_id} );
        my $zone_name = $znames->[0]{zone};

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
    if ( $del && $del->{pseudo} ) {
        $join = "INNER";
    }
    else {
        $join = "LEFT";
    }

    $sql = "SELECT nt_zone_record.*,
               nt_delegate.delegated_by_id,
               nt_delegate.delegated_by_name,
               nt_delegate.perm_write as delegate_write,
               nt_delegate.perm_delete as delegate_delete,
               nt_delegate.perm_delegate as delegate_delegate,
               nt_delegate.zone_perm_add_records as delegate_add_records,
               nt_delegate.zone_perm_delete_records as delegate_delete_records
        FROM nt_zone_record
         $join JOIN nt_delegate ON (nt_delegate.nt_group_id=$group_id AND nt_delegate.nt_object_id=nt_zone_record.nt_zone_record_id AND nt_delegate.nt_object_type='ZONERECORD' )
        WHERE nt_zone_record.nt_zone_id = $data->{nt_zone_id}
          AND nt_zone_record.deleted=0
          AND ( nt_delegate.deleted=0 OR nt_delegate.deleted IS NULL ) ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{start} - 1 ) . ", $r_data->{limit}";

    my $zrecords = $self->exec_query($sql)
        or return {
        error_code => '600',
        error_msg  => $self->{dbh}->errstr,
        };

    foreach my $row (@$zrecords) {
        foreach (
            qw(delegated_by_id delegated_by_name delegate_read delegate_write delegate_move delegate_delete delegate_delegate delegate_full)
            )
        {
            delete $row->{$_} if $row->{$_} eq '';
        }
        push( @{ $r_data->{records} }, $row );
    }

    return $r_data;
}

sub get_group_zone_query_log {
    my ( $self, $data ) = @_;

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

    my $sql = "SELECT nt_zone_id FROM nt_zone WHERE nt_group_id =?";
    my $zone_ids = $self->exec_query( $sql, $data->{nt_group_id} );
    foreach my $row (@$zone_ids) {
        push( @zone_ids, $row->[0] );
    }

    if (@zone_ids) {
        my $sql
            = "SELECT COUNT(*) AS count FROM nt_nameserver_qlog, nt_zone, nt_nameserver WHERE nt_zone.nt_zone_id IN("
            . join( ',', @zone_ids )
            . ") AND nt_nameserver_qlog.nt_zone_id = nt_zone.nt_zone_id AND nt_nameserver_qlog.nt_nameserver_id = nt_nameserver.nt_nameserver_id "
            . (
            @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
        my $c = $self->exec_query($sql);
        $r_data->{total} = $c->[0]{count};
    }
    else {
        $r_data->{total} = 0;
    }

    $self->set_paging_vars( $data, $r_data );

    my $sortby;
    if ( $r_data->{total} == 0 ) {
        return $r_data;
    }
    elsif ( $r_data->{total} > 10000 ) {
        $sortby = $self->format_sort_conditions( $data, \%field_map, "" );
    }
    else {
        $sortby = $self->format_sort_conditions( $data, \%field_map,
            "timestamp DESC" );
    }

    $sql = "SELECT nt_nameserver_qlog.*,
        nt_zone.zone,
        nt_nameserver.name AS nameserver
        FROM nt_nameserver_qlog, nt_zone, nt_nameserver
        WHERE nt_zone.nt_zone_id IN(" . join( ',', @zone_ids ) . ")
          AND nt_nameserver_qlog.nt_zone_id = nt_zone.nt_zone_id 
          AND nt_nameserver_qlog.nt_nameserver_id = nt_nameserver.nt_nameserver_id ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{start} - 1 ) . ", $r_data->{limit}";

    my $nses = $self->exec_query($sql)
        or return {
        error_code => '600',
        error_msg  => $self->{dbh}->errstr,
        };

    foreach my $row (@$nses) {
        push( @{ $r_data->{search_result} }, $row );
    }

    return $r_data;
}

sub new_zone {
    my ( $self, $data ) = @_;

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my @columns
        = qw(mailaddr description refresh retry expire minimum ttl serial nt_group_id zone);

    my $prev_data;
    my $default_serial = 0;

    if ( $data->{serial} eq '' ) {
        $data->{serial} = $self->bump_serial('new');
        $default_serial = 1;
    }

    my $sql
        = "INSERT INTO nt_zone("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $self->{dbh}->quote( $data->{$_} ), @columns ) )
        . ")";

    my $insertid = $self->exec_query($sql)
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

    $error{nt_zone_id} = $data->{nt_zone_id} = $insertid;

    $self->log_zone( $data, 'added', $prev_data, $default_serial );

    foreach my $ns ( split ',', $data->{nameservers} ) {
        $self->exec_query(
            "INSERT INTO nt_zone_nameserver SET nt_zone_id=?, nt_nameserver_id=?",
            [ $insertid, $ns ],
        );
    }

    return \%error;
}

sub edit_zone {
    my ( $self, $data ) = @_;

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );
    if ( my $del = $self->get_param_meta( "nt_zone_id", "delegate" ) ) {
        delete $data->{nt_group_id};
        return $self->error_response( 404,
            'Not allowed to undelete delegated zones.' )
            if $data->{deleted} eq '0';
    }
    if ( exists $data->{deleted} and $data->{deleted} != '0' ) {
        delete $data->{deleted};
    }
    my @columns = grep { exists $data->{$_} }
        qw(nt_group_id mailaddr description refresh retry expire minimum ttl serial deleted);
    my @values;

    unless ( @columns || exists $data->{nameservers} ) {
        return $self->error_response(200);
    }

    my $sql;
    my $prev_data;
    my $default_serial = 0;

    $prev_data = $self->find_zone( $data->{nt_zone_id} );
    my $log_action = $prev_data->{deleted}
        && ( $data->{deleted} eq '0' ) ? 'recovered' : 'modified';

    my %ns;
    if ( exists $data->{nameservers} ) {

        my %datans = map { $_ => 1 } split /,/, $data->{nameservers};

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
        $self->set_zone_nameservers( $data->{nt_zone_id}, \@newns );

        #        @newns = map { $newns[$_] ? $newns[$_] : 0 } ( 0 .. 9 );

        #warn "SET: newns is ".join(" ",@newns);
        #        %ns = map { ( "ns$_" => $newns[$_] ) } ( 0 .. 9 );
    }

    if ( $data->{serial} eq '' ) {
        $data->{serial} = $self->bump_serial( $data->{nt_zone_id} );
        $default_serial = 1;
    }

    my $dbh = $self->{dbh};
    $sql = "UPDATE nt_zone SET " . join(
        ',',
        map( "$_ = " . $dbh->quote( $data->{$_} ), @columns ),

        #map( "$_ = " . $ns{$_},                    keys %ns )
    ) . " WHERE nt_zone_id = ?";
    my $r = $self->exec_query( $sql, $data->{nt_zone_id} );

    $data->{nt_group_id} = $prev_data->{nt_group_id} if !$data->{nt_group_id};

    return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        }
        if !$r;

    $self->log_zone( $data, $log_action, $prev_data, $default_serial );

    return \%error;
}

sub log_zone {
    my ( $self, $data, $action, $prev_data, $default_serial ) = @_;

    my @columns
        = qw(nt_group_id nt_zone_id nt_user_id action timestamp zone mailaddr description refresh retry expire ttl);

    # only log serial if it wasn't set by default
    $default_serial
        ? delete( $data->{serial} )
        : push( @columns, 'serial' );

    my $user = $data->{user};
    $data->{nt_user_id} = $user->{nt_user_id};
    $data->{action}     = $action;
    $data->{timestamp}  = time();
    $data->{zone}       = $prev_data->{zone} unless $data->{zone};

    foreach ( keys %$prev_data ) {
        $data->{$_} = $prev_data->{$_} unless $data->{$_};
    }

    my $dbh = $self->{dbh};
    my $sql
        = "INSERT INTO nt_zone_log("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";

    my $insertid = $self->exec_query($sql) or warn $dbh->errstr;

    my @g_columns
        = qw(nt_user_id timestamp action object object_id log_entry_id title description);

    $data->{object}       = 'zone';
    $data->{log_entry_id} = $insertid;
    $data->{title}        = $data->{zone} || $prev_data->{zone};
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
    $self->exec_query($sql);
}

sub delete_zones {
    my ( $self, $data ) = @_;

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my %groups = map { $_, 1 } (
        $data->{'user'}->{'nt_group_id'},
        @{ $self->get_subgroup_ids( $data->{'user'}->{'nt_group_id'} ) }
    );

    my $sql = "SELECT * FROM nt_zone WHERE nt_zone.nt_zone_id IN("
        . $data->{'zone_list'} . ')';
    my $zones_data = $self->exec_query($sql);

    my $record_obj = NicToolServer::Zone::Record->new( $self->{Apache},
        $self->{client}, $self->{dbh} );

    foreach my $zone_data (@$zones_data) {
        next if !( $groups{ $zone_data->{nt_group_id} } );

        $sql = "UPDATE nt_zone SET deleted=1 WHERE nt_zone_id=?";
        $zone_data->{user} = $data->{user};
        $self->exec_query( $sql, $zone_data->{nt_zone_id} ) or do {
            $error{error_code} = 600;
            $error{error_msg}  = $self->{dbh}->errstr;
            next;
        };

        $self->log_zone( $zone_data, 'deleted', $zone_data, 0 );
    }

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

    my $sql = "SELECT nt_zone.*, nt_group.name as old_group_name 
        FROM nt_zone, nt_group 
       WHERE nt_zone.nt_group_id = nt_group.nt_group_id 
         AND nt_zone_id IN(" . $data->{'zone_list'} . ")";

    my $zrecs = $self->exec_query($sql)
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

    foreach my $row (@$zrecs) {
        next if !$groups{ $row->{'nt_group_id'} };

        $sql = "UPDATE nt_zone SET nt_group_id = ?" . " WHERE nt_zone_id = ?";

        if ($self->exec_query(
                $sql, [ $data->{nt_group_id}, $row->{nt_zone_id}, ]
            )
            )
        {
            my %zone = ( %$row, user => $data->{'user'} );
            $zone{'nt_group_id'} = $data->{'nt_group_id'};
            $zone{'group_name'}  = $new_group->{'name'};

            $self->log_zone( \%zone, 'moved', $row, 0 );
        }
    }

    return \%rv;
}

sub get_zone_list {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK' );

#my %groups = map { $_, 1 } ($data->{'user'}->{'nt_group_id'}, @{ $self->get_subgroup_ids($data->{'user'}->{'nt_group_id'}) });

    my $sql = "SELECT * FROM nt_zone WHERE deleted=0 
        AND nt_zone_id IN(" . $data->{zone_list} . ") ORDER BY zone";

    my $ntzones = $self->exec_query($sql)
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

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

    foreach my $row (@$ntzones) {

        if (my $del = $self->get_param_meta(
                "zone_list:$row->{'nt_zone_id'}", 'delegate'
            )
            )
        {
            foreach my $key ( keys %delegatemapping ) {
                $row->{ $delegatemapping{$key} } = $del->{$key};

                #next unless( $groups{ $row->{'nt_group_id'} } );
            }
        }
        push( @{ $rv{'zones'} }, $row );
    }

    return \%rv;
}

sub find_zone {
    my ( $self, $nt_zone_id ) = @_;

    my $sql = "SELECT * FROM nt_zone WHERE nt_zone_id = ?";
    my $zones = $self->exec_query( $sql, $nt_zone_id );
    return $zones->[0] || {};
}

sub set_zone_nameservers {
    my $self = shift;
    my ( $zone_id, $nsids ) = @_;

    $self->exec_query( "DELETE FROM nt_zone_nameserver WHERE nt_zone_id=?",
        $zone_id );

    foreach my $ns (@$nsids) {
        $self->exec_query(
            "INSERT INTO nt_zone_nameserver SET nt_zone_id=?, nt_nameserver_id=?",
            [ $zone_id, $ns ],
        );
    }
}

sub zone_exists {
    my ( $self, $zone, $zid ) = @_;

    my $sql = "SELECT nt_zone_id,nt_group_id FROM nt_zone WHERE deleted=0 
        AND nt_zone_id != ? AND zone = ?";

    my $zones = $self->exec_query( $sql, [ $zid, $zone ] );
    my $href = $zones->[0];

    return ref $href ? $href : 0;
}

### serial number routines
sub bump_serial {
    my ( $self, $nt_zone_id, $current_serial ) = @_;

    my $serial;

    if ( $nt_zone_id eq 'new' ) {
        $serial = $self->new_serial;
    }
    else {
        if ( $current_serial eq '' ) {
            my $sql = "SELECT serial FROM nt_zone WHERE nt_zone_id = ?";
            my $serials = $self->exec_query( $sql, $nt_zone_id );
            $current_serial = $serials->[0]->{serial};
        }
        $serial = $self->serial_increment($current_serial);
    }

    return $serial;
}

sub serial_increment {
    my ( $self, $serial_current ) = @_;

    my $serial_new;

    if (    ( length($serial_current) == 10 )
        and $serial_current > 1970000000
        and ( $serial_current =~ /^(\d{4,4})(\d{2,2})(\d{2,2})(\d{2,2})$/ ) )
    {

        # dated serials have 10 chars in form YYYYMMDDxx
        my $s_year  = $1;
        my $s_month = $2;
        my $s_day   = $3;
        my $s_digit = $4;

        my $serial_str = $s_year . $s_month . $s_day;
        my $new_str    = $self->serial_date_str;

        if ( $serial_str < $new_str ) {
            $serial_new = $new_str . '00';
        }
        else {

            # serial_str >= new_str, so do serial number math, jumping
            # into the next day/month/year as neccessary to keep incrementing

            $s_digit += 1;

            if ( $s_digit > 99 ) {
                $s_digit = '00';
                $s_day += 1;
                if ( $s_day > 99 ) {
                    $s_day = '01';
                    $s_month += 1;
                    if ( $s_month > 99 ) {
                        $s_month = '01';
                        $s_year = sprintf( "%04d", $s_year + 1 );
                    }
                    $s_month = sprintf( "%02d", $s_month );
                }
                $s_day = sprintf( "%02d", $s_day );
            }
            $s_digit = sprintf( "%02d", $s_digit );

            $serial_new = $s_year . $s_month . $s_day . $s_digit;
        }

    }
    else {
        $serial_new = $serial_current + 1;
    }

    if ( $serial_new > ( ( 2**32 ) - 1 ) ) {
        $serial_new = 1;

        # 4294967295 is the max. (32-bit int minus 1)
        # when we hit this, we have to roll over
    }

    return $serial_new;
}

sub new_serial {
    my $self = shift;

    return 1 if $NicToolServer::serial_format ne 'dated';

    return $self->serial_date_str .'00';
}

sub serial_date_str {
    my $self = shift;
    my @datestr = localtime(time);
    my $year  = $datestr[5] + 1900;
    my $month = sprintf( "%02d", $datestr[4] + 1 );
    my $day   = sprintf( "%02d", $datestr[3] );
    return $year . $month . $day;
}

1;

__END__

=head1 SYNOPSIS

=cut

