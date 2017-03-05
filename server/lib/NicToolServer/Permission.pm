package NicToolServer::Permission;
# ABSTRACT: 

use strict;

@NicToolServer::Permission::ISA = 'NicToolServer';

sub delegate_fields_perm {
    qw(
        perm_write
        perm_delete
        perm_delegate
        zone_perm_add_records
        zone_perm_delete_records
    );
}

sub delegate_fields_full {
    qw(
        perm_write
        perm_delete
        perm_delegate
        zone_perm_add_records
        zone_perm_delete_records

        zone_perm_modify_zone
        zone_perm_modify_mailaddr
        zone_perm_modify_desc
        zone_perm_modify_minimum
        zone_perm_modify_serial
        zone_perm_modify_refresh
        zone_perm_modify_retry
        zone_perm_modify_expire
        zone_perm_modify_ttl
        zone_perm_modify_nameservers

        zonerecord_perm_modify_name
        zonerecord_perm_modify_type
        zonerecord_perm_modify_addr
        zonerecord_perm_modify_weight
        zonerecord_perm_modify_ttl
        zonerecord_perm_modify_desc

    );
}

sub delegate_fields_select {
    "nt_delegate.delegated_by_id, " 
    . "nt_delegate.delegated_by_name, "
    . "nt_delegate.perm_write, "
    . "nt_delegate.perm_delete, "
    . "nt_delegate.perm_delegate, "
    . "nt_delegate.zone_perm_add_records, "
    . "nt_delegate.zone_perm_delete_records, "
}

sub delegate_fields_select_as {
    " nt_delegate.delegated_by_id, 
    nt_delegate.delegated_by_name, 
    nt_delegate.perm_write AS delegate_write, 
    nt_delegate.perm_delete AS delegate_delete, 
    nt_delegate.perm_delegate AS delegate_delegate, 
    nt_delegate.zone_perm_add_records AS delegate_add_records, 
    nt_delegate.zone_perm_delete_records AS delegate_delete_records, "
}

sub get_group_permissions {
    my ( $self, $data ) = @_;


    my $gid = $data->{nt_group_id};
    my $sql
        = "SELECT * FROM nt_perm WHERE deleted != 1 " . "AND nt_group_id = ?";
    my $perms = $self->exec_query( $sql, $gid )
        or return $self->error_response( 505, $self->{dbh}->errstr );

    my $perm = $perms->[0];
    if ( !$perm ) {
        return $self->error_response( 507,
            "Could not find permissions for group ($gid)" );
    }

    $perm->{error_code} = 200;
    $perm->{error_msg}  = 'OK';
    return $perm;
}

sub get_user_permissions {
    my ( $self, $data ) = @_;


    my $uid   = $data->{nt_user_id};
    my $sql   = "SELECT * FROM nt_perm WHERE deleted != 1 AND nt_user_id = ?";
    my $perms = $self->exec_query( $sql, $uid )
        or return $self->error_response( 505, $self->{dbh}->errstr );

    my $perm = $perms->[0];
    if ( !$perm ) {
        $sql
            = "SELECT nt_perm.* FROM nt_perm,nt_user WHERE nt_perm.deleted!=1 "
            . "AND nt_user.deleted != 1 "
            . "AND nt_user.nt_user_id = ?"
            . "AND nt_perm.nt_group_id = nt_user.nt_group_id";
        $perms = $self->exec_query( $sql, $uid )
            or return $self->error_response( 505, $self->{dbh}->errstr );
        $perm = $perms->[0];
    }
    if ( !$perm ) {
        return $self->error_response( 507,
            "Could not find permissions for user ($uid)" );
    }

    $perm->{error_code} = 200;
    $perm->{error_msg}  = 'OK';
    return $perm;
}

sub log_delegate {
    my ( $self, $data, $action, $prev_data ) = @_;

    my $dbh = $self->{dbh};
    my @columns
        = qw(nt_user_id nt_user_name action nt_object_type nt_object_id nt_group_id timestamp perm_write perm_delete perm_delegate zone_perm_add_records zone_perm_delete_records zone_perm_modify_zone zone_perm_modify_mailaddr zone_perm_modify_desc zone_perm_modify_minimum zone_perm_modify_serial zone_perm_modify_refresh zone_perm_modify_retry zone_perm_modify_expire zone_perm_modify_ttl zone_perm_modify_nameservers);
    my @values;

    my $user = $data->{user};
    $data->{nt_user_id} = $data->{delegated_by_id};
    $data->{nt_user_id} ||= $user->{nt_user_id};
    $data->{nt_user_name} = $data->{delegated_by_name};
    $data->{nt_user_name} ||= $user->{username};
    $data->{action}    = $action;
    $data->{timestamp} = time();

    foreach ( keys %$prev_data ) {
        $data->{$_} = $prev_data->{$_} unless exists $data->{$_};
    }

    my $sql
        = "INSERT INTO nt_delegate_log("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";
    my $insertid = $self->exec_query($sql);

    my @g_columns
        = qw(nt_user_id timestamp action object object_id target target_id target_name log_entry_id title description);

    $data->{object} = lc( $data->{nt_object_type} );
    $data->{object} = 'zone_record' if $data->{object} eq 'zonerecord';
    $data->{log_entry_id} = $insertid;
    $data->{title}        = $self->get_title( $data->{nt_object_type},
        $data->{nt_object_id} );
    $data->{object_id} = $data->{nt_object_id};
    $data->{target_id} = $data->{nt_group_id};
    $data->{target}    = 'group';
    $data->{target_name}
        = $self->get_title( 'group', $data->{target_id} );

    if ( $action eq 'modified' ) {
        $data->{action} = 'modified delegation';
        $data->{description} = $self->diff_changes( $data, $prev_data );
    }
    elsif ( $action eq 'deleted' ) {
        $data->{action}      = 'removed delegation';
        $data->{description} = 'removed delegation';
    }
    elsif ( $action eq 'delegated' ) {
        $data->{action}      = 'delegated';
        $data->{description} = 'initial delegation';
    }

    $sql
        = "INSERT INTO nt_user_global_log("
        . join( ',', @g_columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @g_columns ) ) . ")";
    $self->exec_query($sql);
}

sub delegate_objects {
    my ( $self, $data ) = @_;

    ##sanity checks
    #XXX someday move these sanity checks to Permission/Sanity.pm

    if ( $data->{nt_group_id} eq $data->{user}{nt_group_id} ) {
        $self->error( 'nt_group_id', 'Cannot delegate to your own group.' );
    }

    $self->error( 'nt_group_id', 'Cannot delegate to a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{nt_group_id} );

    foreach my $id ( split( /,/, $data->{nt_object_id_list} ) ) {
        $self->error( 'nt_object_id_list', 'Cannot delegate deleted objects!' )
            if $self->check_object_deleted( lc( $data->{nt_object_type} ),
                    $id );
    }

    return $self->throw_sanity_error if ( $self->{errors} );
    ##end sanity checks

    my @fields = $self->delegate_fields_full;
    foreach (@fields) {
        $data->{$_} = 0 unless exists $data->{$_};
    }

    my %objs = map { $_ => 0 } split( /,/, $data->{nt_object_id_list} );
    my $sql = "SELECT * FROM nt_delegate
        WHERE deleted=0
         AND nt_group_id = ?
         AND nt_object_type = ?
         AND nt_object_id IN (" . $data->{nt_object_id_list} . ") ";

    my $delegates
        = $self->exec_query( $sql,
        [ $data->{nt_group_id}, $data->{nt_object_type} ] )
        or return $self->error_response( 505, $self->{dbh}->errstr );

    my @already;
    foreach my $row (@$delegates) { push @already, $row->{nt_object_id}; }

    if (@already) {
        return $self->error_response( 600,
                  "Some objects were already delegated to that group: "
                . join( ",", @already )
                . "." );
    }
    if ( $self->check_object_deleted( 'group', $data->{nt_group_id} ) ) {
        return $self->error_response( 600,
            "Cannot delegate to a deleted group!" );
    }
    foreach ( split( /,/, $data->{nt_object_id_list} ) ) {
        if ( $self->check_object_deleted( $data->{nt_object_type}, $_ ) ) {
            return $self->error_response( 600,
                "Cannot delegate a deleted object!" );
        }
    }

    foreach my $id ( grep { !$objs{$_} } keys %objs ) {
        $data->{delegated_by_id}   = $data->{user}{nt_user_id};
        $data->{delegated_by_name} = $data->{user}{username};
        foreach (@fields) {
            $data->{$_} = 0 unless exists $data->{$_};
        }
        my @columns = (
            qw/nt_group_id nt_object_type delegated_by_id delegated_by_name/,
            @fields
        );
        $sql
            = "INSERT INTO nt_delegate ("
            . join( ",", 'nt_object_id', @columns )
            . ") VALUES(??)";
        my $insertid = $self->exec_query( $sql,
            [ $id, map( $data->{$_}, @columns ) ] );
        return $self->error_response( 505, $self->{dbh}->errstr )
            if !defined $insertid;
        my %pdata;
        @pdata{ 'nt_object_id', @columns } = ( $id, @$data{@columns} );
        $pdata{user} = $data->{user};

        #log entry
        $self->log_delegate( \%pdata, 'delegated', {} );
    }
    return $self->error_response(200);
}

sub delegate_groups {
    my ( $self, $data ) = @_;
    $data->{nt_object_id_list} = $data->{group_list};
    $data->{nt_object_type}    = 'GROUP';
    return $self->delegate_objects($data);
}

sub delegate_zones {
    my ( $self, $data ) = @_;
    $data->{nt_object_id_list} = $data->{zone_list};
    $data->{nt_object_type}    = 'ZONE';
    unless ( $self->{user}{zone_write} ) {
        delete $data->{perm_write};
    }
    unless ( $self->{user}{zonerecord_create} ) {
        delete $data->{zone_perm_add_records};
    }
    unless ( $self->{user}{zonerecord_delete} ) {
        delete $data->{zone_perm_delete_records};
    }
    return $self->delegate_objects($data);
}

sub delegate_zone_records {
    my ( $self, $data ) = @_;
    $data->{nt_object_id_list} = $data->{zonerecord_list};
    $data->{nt_object_type}    = 'ZONERECORD';
    unless ( $self->{user}{zonerecord_write} ) {
        delete $data->{perm_write};
    }
    return $self->delegate_objects($data);
}

sub delegate_nameservers {
    my ( $self, $data ) = @_;
    $data->{nt_object_id_list} = $data->{nameserver_list};
    $data->{nt_object_type}    = 'NAMESERVER';
    return $self->delegate_objects($data);
}

sub delete_object_delegation {
    my ( $self, $data ) = @_;

    my $dbh = $self->{dbh};

    my $sql
        = "SELECT * FROM nt_delegate WHERE deleted=0 "
        . "AND nt_object_id = ?"
        . " AND nt_object_type = ?"
        . " AND nt_group_id = ?";

    my $delegates = $self->exec_query(
        $sql,
        [   $data->{nt_object_id}, $data->{nt_object_type},
            $data->{nt_group_id}
        ]
    ) or return $self->error_response( 505, $dbh->errstr );
    my $prev_data;
    unless ( $prev_data = $delegates->[0] ) {
        return $self->error_response( 601,
            "No Such Delegation ($data->{nt_object_type} id $data->{nt_object_id} to group $data->{nt_group_id}"
        );
    }
    else {

        if ($self->check_object_deleted(
                $data->{nt_object_type},
                $data->{nt_object_id}
            )
            )
        {
            return $self->error_response( 600,
                "Cannot delete delegation for a deleted object!" );
        }
        if ( $self->check_object_deleted( 'group', $data->{nt_group_id} ) )
        {
            return $self->error_response( 600,
                "Cannot delete delegation to a deleted group!" );
        }
        my @fields = qw(nt_group_id nt_object_id nt_object_type);
        $sql = "DELETE FROM nt_delegate WHERE "
            . join( " AND ",
            map( "$_ = " . $dbh->quote( $data->{$_} ), @fields ) );
        $self->exec_query($sql)
            or return $self->error_response( 505, $dbh->errstr );
    }
    my %user = ( %$prev_data, user => $data->{user} );
    $self->log_delegate( \%user, 'deleted', $prev_data );

    return $self->error_response(200);
}

sub delete_group_delegation {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{delegate_nt_group_id};
    $data->{nt_object_type} = 'GROUP';
    return $self->delete_object_delegation($data);
}

sub delete_zone_delegation {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_zone_id};
    $data->{nt_object_type} = 'ZONE';
    return $self->delete_object_delegation($data);
}

sub delete_zone_record_delegation {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_zone_record_id};
    $data->{nt_object_type} = 'ZONERECORD';
    return $self->delete_object_delegation($data);
}

sub delete_nameserver_delegation {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_nameserver_id};
    $data->{nt_object_type} = 'NAMESERVER';
    return $self->delete_object_delegation($data);
}

sub delegated_objects_from_group {
    my ( $self, $data ) = @_;

    my @params = qw(nt_group_id delegator_nt_group_id);

    my $vals = {
        'GROUP' => { 'table' => 'nt_group', 'id' => 'nt_group_id' },
        'ZONE'  => { 'table' => 'nt_zone',  'id' => 'nt_zone_id' },
        'ZONERECORD' =>
            { 'table' => 'nt_zone_record', 'id' => 'nt_zone_record_id' },
        'NAMESERVER' =>
            { 'table' => 'nt_nameserver', 'id' => 'nt_nameserver_id' },
    };

    #my $table = $vals->{$type}->{table};
    #my $idname = $vals->{$type}->{id};
    my $response = $self->error_response(200);
    foreach my $type ( keys %$vals ) {
        my $table  = $vals->{$type}->{table};
        my $idname = $vals->{$type}->{id};

        my $sql
            = "SELECT $table.*, "
            . $self->delegate_fields_select_as
            . "nt_group.name as group_name 
            FROM $table 
            INNER JOIN nt_delegate ON $table.$idname=nt_delegate.nt_object_id 
              AND nt_delegate.nt_object_type='$type' 
            INNER JOIN nt_group ON $table.nt_group_id=nt_group.nt_group_id 
              WHERE nt_delegate.deleted=0 
                AND $table.deleted=0 
                AND nt_delegate.nt_group_id = "
             . $data->{nt_group_id}
            . " AND nt_delegate.nt_object_id = $table.$idname ";

        my $objects = $self->exec_query($sql);
        if ($objects) {
            $response->{$type} = [];
            foreach my $row (@$objects) {
                push @{ $response->{$type} }, $row;
            }
        }
        else {
            warn "WARN: delegated_objects_from_group: "
                . $self->{dbh}->errstr;
        }

    }

    return $response;
}

sub delegated_objects_by_type {
    my ( $self, $data ) = @_;

    my @params = grep { exists $data->{$_} } qw/ nt_group_id nt_object_type /;
    my $id     = $data->{nt_object_id};
    my $type   = $data->{nt_object_type};

    my $vals = {
        'GROUP' => { 'table' => 'nt_group', 'id' => 'nt_group_id' },
        'ZONE'  => { 'table' => 'nt_zone',  'id' => 'nt_zone_id' },
        'ZONERECORD' =>
            { 'table' => 'nt_zone_record', 'id' => 'nt_zone_record_id' },
        'NAMESERVER' =>
            { 'table' => 'nt_nameserver', 'id' => 'nt_nameserver_id' },
    };

    my $table  = $vals->{$type}->{table};
    my $idname = $vals->{$type}->{id};

    my $sql = "SELECT $table.*, "
        . $self->delegate_fields_select_as
        . " nt_group.name AS group_name 
FROM $table 
  INNER JOIN nt_delegate ON $table.$idname=nt_delegate.nt_object_id 
  AND nt_delegate.nt_object_type='$type' "
        . (
        $type eq 'ZONERECORD'
        ? "INNER JOIN nt_zone ON nt_zone.nt_zone_id=nt_delegate.nt_object_id 
           INNER JOIN nt_group ON nt_group.nt_group_id = nt_zone.nt_group_id "
        : "INNER JOIN nt_group ON $table.nt_group_id=nt_group.nt_group_id "
        )
        . "WHERE nt_delegate.deleted=0 
        AND $table.deleted=0 
        AND nt_delegate.nt_group_id=?";

    my $objects = $self->exec_query( $sql, $data->{nt_group_id} )
        or return $self->error_response( 505,
        $self->{dbh}->errstr . " : sql : $sql" );
    my $response = $self->error_response(200);
    $response->{$type} = [];
    foreach my $row (@$objects) {
        push @{ $response->{$type} }, $row;
    }

    return $response;
}

sub get_delegated_groups {
    my ( $self, $data ) = @_;
    $data->{nt_object_type} = 'GROUP';
    return $self->delegated_objects_by_type($data);
}

sub get_delegated_zones {
    my ( $self, $data ) = @_;
    $data->{nt_object_type} = 'ZONE';
    return $self->delegated_objects_by_type($data);
}

sub get_delegated_zone_records {
    my ( $self, $data ) = @_;
    $data->{nt_object_type} = 'ZONERECORD';
    return $self->delegated_objects_by_type($data);
}

sub get_delegated_nameservers {
    my ( $self, $data ) = @_;
    $data->{nt_object_type} = 'NAMESERVER';
    return $self->delegated_objects_by_type($data);
}

sub get_object_delegates {
    my ( $self, $data ) = @_;

    my $sql
        = "SELECT "
        . $self->delegate_fields_select_as
        . " nt_group.nt_group_id,
            nt_group.name AS group_name
         FROM nt_delegate
         INNER JOIN nt_group
               ON nt_delegate.nt_group_id=nt_group.nt_group_id
         WHERE nt_delegate.deleted=0 
           AND nt_group.deleted=0
           AND nt_object_id = ?
           AND nt_object_type = ?";

    my $rows
        = $self->exec_query( $sql,
        [ $data->{nt_object_id}, $data->{nt_object_type} ] )
        or return $self->error_response( 505, $self->{dbh}->errstr );
    my $response = $self->error_response(200);
    $response->{delegates} = [];
    foreach my $row (@$rows) {
        push @{ $response->{delegates} }, $row;
    }

    return $response;
}

sub get_group_delegates {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_group_id};
    $data->{nt_object_type} = 'GROUP';
    return $self->get_object_delegates($data);
}

sub get_zone_delegates {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_zone_id};
    $data->{nt_object_type} = 'ZONE';
    return $self->get_object_delegates($data);
}

sub get_zone_record_delegates {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_zone_record_id};
    $data->{nt_object_type} = 'ZONERECORD';
    return $self->get_object_delegates($data);
}

sub get_nameserver_delegates {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_nameserver_id};
    $data->{nt_object_type} = 'NAMESERVER';
    return $self->get_object_delegates($data);
}

sub edit_object_delegation {
    my ( $self, $data ) = @_;

    my $dbh = $self->{dbh};

    ##sanity checks
    $self->error( 'nt_group_id', 'Cannot edit delegation to a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{nt_group_id} );

    $self->error( 'nt_object_id', 'Cannot edit delegation of a deleted object!')
        if $self->check_object_deleted( lc( $data->{nt_object_type} ),
        $data->{nt_object_id} );
    ##end sanity checks

    my $sql = "SELECT * FROM nt_delegate WHERE deleted=0
        AND nt_group_id=? AND nt_object_id=? AND nt_object_type=?";

    my $delegates = $self->exec_query(
        $sql,
        [   $data->{nt_group_id}, $data->{nt_object_id},
            $data->{nt_object_type}
        ]
    ) or return $self->error_response( 505, $self->{dbh}->errstr );
    my $prev_data;
    unless ( $prev_data = $delegates->[0] ) {
        return $self->error_response( 601,
            "No Such Delegation ($data->{nt_object_type} id $data->{nt_object_id} to group $data->{nt_group_id}"
        );
    }

    if ($self->check_object_deleted(
            $data->{nt_object_type},
            $data->{nt_object_id}
        )
        )
    {
        return $self->error_response( 600,
            "Cannot edit delegation for a deleted object!" );
    }
    if ( $self->check_object_deleted( 'group', $data->{nt_group_id} ) ) {
        return $self->error_response( 600,
            "Cannot edit delegation to a deleted group!" );
    }

    my %params = map { $_ => $data->{$_} ? 1 : 0 }
        grep { exists $data->{$_} } $self->delegate_fields_perm;

    return $self->error_response(200) unless ( keys %params );

    $sql
        = "UPDATE nt_delegate set "
        . join( ",",
        map { "$_ = " . $dbh->quote( $params{$_} ) } keys %params )
        . " WHERE deleted=0
              AND nt_group_id=?
              AND nt_object_id=?
              AND nt_object_type=?";

    $self->exec_query(
        $sql,
        [   $data->{nt_group_id}, $data->{nt_object_id},
            $data->{nt_object_type},
        ]
        )
        or return $self->error_response( 505, $dbh->errstr . ": sql :$sql" );

    $self->log_delegate( $data, 'modified', $prev_data );

    return $self->error_response(200);
}

sub edit_group_delegation {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_group_id};
    $data->{nt_object_type} = 'GROUP';
    return $self->edit_object_delegation($data);
}

sub edit_zone_delegation {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_zone_id};
    $data->{nt_object_type} = 'ZONE';
    unless ( $self->{user}{zone_write} ) {
        delete $data->{perm_write};
    }
    unless ( $self->{user}->{zonerecord_create} ) {
        delete $data->{zone_perm_add_records};
    }
    unless ( $self->{user}{zonerecord_delete} ) {
        delete $data->{zone_perm_delete_records};
    }
    return $self->edit_object_delegation($data);
}

sub edit_zone_record_delegation {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_zone_record_id};
    $data->{nt_object_type} = 'ZONERECORD';
    unless ( $self->{user}{zonerecord_write} ) {
        delete $data->{perm_write};
    }
    return $self->edit_object_delegation($data);
}

sub edit_nameserver_delegation {
    my ( $self, $data ) = @_;
    $data->{nt_object_id}   = $data->{nt_nameserver_id};
    $data->{nt_object_type} = 'NAMESERVER';
    return $self->edit_object_delegation($data);
}

sub diff_changes {
    my ( $self, $data, $prev_data ) = @_;
    my @changes;

    my %perms = (
        'perm_write'               => 'write',
        'perm_delete'              => 'delete',
        'perm_delegate'            => 're-delegate',
        'zone_perm_add_records'    => 'add records',
        'zone_perm_delete_records' => 'delete records',
    );

    foreach my $f ( keys %$prev_data ) {
        next unless ( exists $data->{$f} );
        if ( $f eq 'description' || $f eq 'password' )
        {    # description field is too long & not critical
            push( @changes, "changed $f" )
                if ( $data->{$f} ne $prev_data->{$f} );
            next;
        }
        elsif ( exists $perms{$f} ) {
            push( @changes,
                      "changed "
                    . $perms{$f}
                    . " from '"
                    . $prev_data->{$f}
                    . "' to '"
                    . $data->{$f}
                    . "'" )
                if ( $data->{$f} != $prev_data->{$f} );
        }
        else {
            push( @changes,
                "changed $f from '$prev_data->{$f}' to '$data->{$f}'" )
                if ( $data->{$f} ne $prev_data->{$f} );
        }
    }
    if ( !@changes ) {
        push( @changes, "nothing modified" );
    }
    return join( ", ", @changes );
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Permission -  

=head1 VERSION

version 2.33

=head1 SYNOPSIS

=over 
get_group_permissions returns the permissions structure for a certain group

=over 
get_user_permissions returns the permissions structure for a certain user
user's inherit from their parent groups

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=item *

Damon Edwards

=item *

Abe Shelton

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abe Shelton, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
