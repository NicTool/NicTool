package NicToolServer::Group;

# ABSTRACT: nictool groups (aka, permission realms)

use strict;

@NicToolServer::Group::ISA = 'NicToolServer';

sub new_group {
    my ( $self, $data ) = @_;

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my $sql = "SELECT COUNT(*) AS count FROM nt_group
        WHERE deleted=0 AND parent_group_id=? AND name=?";

    my $groups = $self->exec_query( $sql, [ $data->{nt_group_id}, $data->{name} ] );

    if ( $groups->[0]{count} > 0 ) {
        return $self->error_response( 600, 'A group with that name already exists.' );
    }

    $data->{parent_group_id} = $data->{nt_group_id};

    $sql = "INSERT INTO nt_group (parent_group_id, name) VALUES(??)";

    my $insertid = $error{nt_group_id} =
        $self->exec_query( $sql, [ $data->{parent_group_id}, $data->{name} ] )
        or return $self->error_response( 505, $self->{dbh}->errstr );

    $data->{modified_group_id} = $insertid;

    my @permcols = grep { exists $data->{$_} } $self->perm_fields;

    #cannot change permissions unless you have those permissions
    foreach (@permcols) {
        $data->{$_} = 0 unless $data->{user}{$_};
    }

    $sql =
          "INSERT INTO nt_perm("
        . join( ',', 'nt_group_id', @permcols, 'usable_ns' )
        . ") VALUES(??)";

    my @values = map( $data->{$_}, @permcols );
    push @values, join( ',', sort $data->{usable_nameservers} );
    my $permid = $self->exec_query( $sql, [ $insertid, @values ] );
    warn "$sql\n" if $self->debug_sql;

    if ( !$permid ) {
        $error{error_code} = 505;
        $error{error_msg}  = $self->{dbh}->errstr;

        # now we have to undo the nt_group insert else we have a group with
        # no perms, and that's a problem
        $sql = "DELETE FROM nt_group WHERE nt_group_id=$insertid";
        if ( !$self->exec_query( $sql, $insertid ) ) {
            $error{error_msg} .= " (further:) " . $self->{dbh}->errstr;
        }
        return \%error;
    }

    $self->add_to_group_subgroups( $insertid, $data->{nt_group_id}, 1000 );

    $self->log_group( $data, 'added', undef );

    return \%error;
}

sub edit_group {
    my ( $self, $data ) = @_;

    my $dbh = $self->{dbh};

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );
    my $sql;

    if ( $data->{nt_group_id} == $data->{user}{nt_group_id} ) {
        return $self->error_response( 600, 'You may not edit the group you belong to' );
    }

    my @columns = grep { exists $data->{$_} } qw/ parent_group_id name /;

    my $action;
    my $prev_data = $self->find_group( $data->{nt_group_id} );
    $data->{modified_group_id} = $data->{nt_group_id};

    if (@columns) {
        $sql =
              "UPDATE nt_group SET "
            . join( ',', map( "$_ = " . $dbh->quote( $data->{$_} ), @columns ) )
            . " WHERE nt_group_id=?";

        $self->exec_query( $sql, $data->{nt_group_id} )
            or return $self->error_response( 505, $dbh->errstr );

        $action = 'modified';
        $error{nt_group_id} = $data->{nt_group_id};
    }

    my @permcols = grep { exists $data->{$_} && $data->{user}{$_} } $self->perm_fields;

    my %usable = map { $_ => 1 } split( /,/, $data->{usable_nameservers} );

    # merge the usable nameservers settings
    $sql = "SELECT * from nt_perm WHERE nt_group_id = ?
        AND (nt_user_id IS NULL OR nt_user_id = 0)";
    my $gperms = $self->exec_query( $sql, $data->{nt_group_id} )
        or return $self->error_response( 505, $dbh->errstr );
    $gperms     = $gperms->[0];
    %$prev_data = ( %$prev_data, map { $_ => $gperms->{$_} } $self->perm_fields );

    if ( !$gperms ) {
        return $self->error_response( 507,
            "No permissions found for group ID $data->{nt_group_id}." );
    }

    my %userns  = map { $_ => 1 } split( /,/, $data->{user}{usable_ns} );
    my %groupns = map { $_ => 1 } split( /,/, $gperms->{usable_ns} );

    foreach my $n ( keys %groupns ) {
        delete $groupns{$n} if !$usable{$n};

        next if !$userns{$n};                                                # no access
        next if !$self->get_access_permission( 'NAMESERVER', $n, 'read' );

        #delete it or set it to true according to presence in the data array
        $groupns{$n} = 1 if $usable{$n};
        delete $usable{$n};
    }

    # add the nameservers that weren't present before
    foreach my $n ( keys %usable ) {
        $groupns{$n} = 1;
    }

    # leave the rest
    my @newns;
    foreach ( keys %groupns ) {
        push @newns, $_ if exists $groupns{$_};
        delete $groupns{$_};
    }
    $data->{usable_ns} = scalar @newns ? join( ',', sort @newns ) : '';

    if (@permcols) {
        my @s = map( "$_ = " . $dbh->quote( $data->{$_} ), @permcols );
        $sql = "UPDATE nt_perm SET " . join( ',', @s )
            . " WHERE nt_group_id=? AND (nt_user_id IS NULL OR nt_user_id = 0)";
        $self->exec_query( $sql, $data->{nt_group_id} )
            or return $self->error_response( 505, $dbh->errstr );

        #TODO rollback the nt_group changes above if error?
        $action = 'modified';
    }

    if ( defined $data->{usable_ns} ) {
        $sql = "UPDATE nt_perm SET usable_ns=?
            WHERE nt_group_id=? AND (nt_user_id IS NULL OR nt_user_id = 0)";
        $self->exec_query( $sql, [ $data->{usable_ns}, $data->{nt_group_id} ] )
            or return $self->error_response( 505, $dbh->errstr );
        $action = 'modified';
    }

    $self->log_group( $data, $action, $prev_data ) if $action;

    return \%error;
}

sub add_to_group_subgroups {
    my ( $self, $gid, $parent_group_id, $rank ) = @_;

    my $sql = "INSERT INTO nt_group_subgroups(nt_group_id, nt_subgroup_id, `rank`) VALUES(??)";
    $self->exec_query( $sql, [ $parent_group_id, $gid, $rank ] );

    $sql = "SELECT parent_group_id FROM nt_group WHERE nt_group_id = ?";
    my $ids  = $self->exec_query( $sql, $parent_group_id );
    my $pgid = $ids->[0]->{parent_group_id};

    if ( $pgid != 0 ) {
        $self->add_to_group_subgroups( $gid, $pgid, $rank - 1 );
    }
}

sub delete_group {
    my ( $self, $data ) = @_;

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my $sql = "SELECT COUNT(*) AS count FROM nt_zone
        WHERE deleted=0 AND nt_group_id = ?";
    my $c = $self->exec_query( $sql, $data->{nt_group_id} );

    if ( $c->[0]->{count} > 0 ) {
        return $self->error_response( 600,
            'You can\'t delete this group until you delete all of its zones' );
    }

    $sql = "SELECT COUNT(*) AS count FROM nt_user
    WHERE deleted=0 AND nt_group_id = ?";
    $c = $self->exec_query( $sql, $data->{nt_group_id} );
    if ( $c->[0]->{count} > 0 ) {
        return $self->error_response( 600,
            'You can\'t delete this group until you delete all of its users' );
    }

    $sql = "SELECT COUNT(*) AS count FROM nt_group WHERE deleted=0 AND parent_group_id = ?";
    $c   = $self->exec_query( $sql, $data->{nt_group_id} );
    if ( $c->[0]->{count} > 0 ) {
        return $self->error_response( 600,
            'You can\'t delete this group until you delete all of its sub-groups' );
    }

    my $group_data = $self->find_group( $data->{nt_group_id} );
    $group_data->{user} = $data->{user};

    $sql = "UPDATE nt_group SET deleted=1 WHERE nt_group_id = ?";
    $self->exec_query( $sql, $data->{nt_group_id} )
        or return $self->error_response( 600, $self->{dbh}->errstr );

    $self->log_group( $group_data, 'deleted' );

    return \%error;
}

sub get_group {
    my ( $self, $data ) = @_;

    my $sql =
          "SELECT nt_group.*, "
        . $self->perm_fields_select
        . " FROM nt_group,nt_perm WHERE nt_group.nt_group_id = ?"
        . " AND nt_perm.nt_group_id = nt_group.nt_group_id"
        . " AND (nt_perm.nt_user_id IS NULL OR nt_perm.nt_user_id = 0)";
    my $perms = $self->exec_query( $sql, $data->{nt_group_id} )
        or return $self->error_response( 505, $self->{dbh}->errstr );

    my %rv;

    my $ref = $perms->[0];
    if ($ref) {
        %rv             = %$ref;
        $rv{error_code} = 200;
        $rv{error_msg}  = 'OK';
    }
    else {
        $rv{error_code} = 600;
        $rv{error_msg}  = $self->{dbh}->errstr;
    }

    if ( $rv{nt_group_id} ) {
        $sql = "SELECT COUNT(*) AS count FROM nt_group WHERE deleted=0 AND parent_group_id = ?";
        my $r = $self->exec_query( $sql, $rv{nt_group_id} );
        $rv{has_children} = $r->[0]->{count};
    }

    delete $rv{nt_user_id};

    return \%rv;
}

sub get_group_groups {
    my ( $self, $data ) = @_;

    my $sql =
          "SELECT nt_group.*, "
        . $self->perm_fields_select
        . " FROM nt_group,nt_perm WHERE nt_group.deleted=0 AND nt_perm.deleted=0 AND nt_group.parent_group_id = ?"
        . " AND nt_perm.nt_group_id = nt_group.nt_group_id"
        . " AND (nt_perm.nt_user_id IS NULL OR nt_perm.nt_user_id = 0)"
        . " ORDER BY nt_group.name";
    my $rows   = $self->exec_query( $sql, $data->{nt_group_id} );
    my $r_data = { error_code => 200, error_msg => 'OK' };
    $r_data->{groups} = [];

    if ($rows) {
        foreach my $row (@$rows) {
            delete $row->{nt_user_id};
            push( @{ $r_data->{groups} }, $row );
        }
    }
    else {
        $r_data->{error_code} = '600';
        $r_data->{error_msg}  = $self->{dbh}->errstr;
    }

    if ( ref( $r_data->{groups} ) ) {
        $sql = "SELECT COUNT(*) AS count FROM nt_group WHERE deleted=0 AND parent_group_id = ?";
        foreach ( @{ $r_data->{groups} } ) {
            my $c = $self->exec_query( $sql, $_->{nt_group_id} );
            $_->{has_children} = $c->[0]->{count};
        }
    }

    return $r_data;
}

sub get_group_subgroups {
    my ( $self, $data ) = @_;

    my %field_map = (
        group           => { timefield => 0, quicksearch => 1, field => 'nt_group.name' },
        parent_group_id => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_group.parent_group_id'
        },
        sub_groups => {
            timefield   => 0,
            quicksearch => 0,
            field       => '(SELECT COUNT(*) FROM nt_group sg WHERE sg.parent_group_id = nt_group.nt_group_id AND sg.deleted = 0)'
        },
    );

    my $conditions = $self->format_search_conditions( $data, \%field_map );
    my $sortby     = $self->format_sort_conditions( $data, \%field_map, "nt_group.name" );

    my @group_list = $data->{nt_group_id};
    if ( $data->{include_subgroups} ) {
        push @group_list, @{ $self->get_subgroup_ids( $data->{start_group_id} ) };
    }
        @group_list = @{ $self->sanitize_int_list(\@group_list) };
        return $self->error_response( 503, 'invalid group list' ) if !@group_list;

    my $r_data = { error_code => 200, error_msg => 'OK', groups => [] };

        my ( $group_in_sql, $group_in_params ) =
                $self->sql_in_clause( 'parent_group_id', \@group_list );
    my $sql          = "SELECT COUNT(*) AS count FROM nt_group
    WHERE deleted=0 AND $group_in_sql";
    $sql .= $self->and_conditions_sql($conditions);

        my $c = $self->exec_query( $sql, $group_in_params );
    $r_data->{total} = $c->[0]->{count};

    $self->set_paging_vars( $data, $r_data );

    $r_data->{total}++ if $data->{include_parent};

    return $r_data if $r_data->{total} == 0;

        my ( $limit_sql, $limit_params ) = $self->sql_limit_clause($r_data);
    $sql = "SELECT nt_group.* FROM nt_group
    WHERE deleted=0 AND $group_in_sql";
    $sql .= $self->and_conditions_sql($conditions);
    $sql .= $self->order_by_sql($sortby);
        $sql .= $limit_sql;
        my $group_rows = $self->exec_query( $sql, [ @$group_in_params, @$limit_params ] );

    return { error_code => '600', error_msg => $self->{dbh}->errstr }
        if !$group_rows;

    my %groups;
    foreach my $row (@$group_rows) {
        $sql = "SELECT COUNT(*) AS count FROM nt_group WHERE deleted=0 AND parent_group_id = ?";
        $c   = $self->exec_query( $sql, $row->{nt_group_id} )
            or return $self->error_response( 505, $self->{dbh}->errstr );
        $row->{has_children} = $c->[0]->{count};

        push @{ $r_data->{groups} }, $row;

        $groups{ $row->{nt_group_id} } = 1;
    }

    if ( $data->{include_parent} ) {
        unshift @{ $r_data->{groups} }, $self->find_group( $data->{user}{nt_group_id} );
    }

    $r_data->{group_map} = $self->get_group_map( $data->{start_group_id}, [ keys %groups ] );

    warn "get_group_subgroups: " . Data::Dumper::Dumper($r_data)
        if $self->debug_result;

    return $r_data;
}

sub get_global_application_log {
    my ( $self, $data ) = @_;

    my %field_map = (
        $self->global_log_field_map,
        user => { timefield => 0, quicksearch => 1, field => 'nt_user.username' },
        group_name => {
            timefield   => 0,
            quicksearch => 0,
            field       => '(SELECT g.name FROM nt_group g WHERE g.nt_group_id = nt_user.nt_group_id)'
        },
    );

    my $conditions = $self->format_search_conditions( $data, \%field_map );
    my $sortby =
        $self->format_sort_conditions( $data, \%field_map, "nt_user_global_log.timestamp DESC" );

    my @group_list =
        $data->{include_subgroups}
        ? $self->group_with_subgroup_ids( $data->{nt_group_id} )
        : $data->{nt_group_id};

    my $r_data = { error_code => 200, error_msg => 'OK', log => [] };

    my $sql =
          "SELECT COUNT(*) AS count FROM nt_user_global_log, nt_user "
        . "WHERE nt_user_global_log.nt_user_id = nt_user.nt_user_id "
        . "AND nt_user.nt_group_id IN("
        . join( ',', @group_list ) . ") "
        . $self->and_conditions_sql($conditions);
    my $c = $self->exec_query($sql);
    $r_data->{total} = $c->[0]{count};

    $self->set_paging_vars( $data, $r_data );

    return $r_data if $r_data->{total} == 0;

    $sql =
          "SELECT nt_user_global_log.*, "
        . "       CONCAT(nt_user.first_name, \" \", nt_user.last_name, \" (\", nt_user.username, \")\") as user, "
        . "       nt_user.nt_group_id, "
        . "       nt_group.name as group_name "
        . "FROM nt_user_global_log, nt_user, nt_group "
        . "WHERE nt_user_global_log.nt_user_id = nt_user.nt_user_id AND nt_user.nt_group_id IN("
        . join( ',', @group_list )
        . ") AND nt_user.nt_group_id = nt_group.nt_group_id ";
    $sql .= $self->and_conditions_sql($conditions);
    $sql .= $self->order_by_sql($sortby);
    my ( $limit_sql, $limit_params ) = $self->sql_limit_clause($r_data);
    $sql .= $limit_sql;

    my $logs = $self->exec_query( $sql, $limit_params )
        or return {
        error_code => '600',
        error_msg  => $self->{dbh}->errstr,
        };

    my %groups;
    foreach my $row (@$logs) {
        push( @{ $r_data->{log} }, $row );

        $groups{ $row->{nt_group_id} } = 1;
    }

    $r_data->{group_map} = $self->get_group_map( $data->{start_group_id}, [ keys %groups ] );

    return $r_data;
}

sub get_group_branch {
    my ( $self, $data ) = @_;

    my $user_group = $data->{user}{nt_group_id};
    my $cur_group  = $data->{nt_group_id};
    my $last_group = '';

    my %rv = ( error_code => 200, error_msg => 'OK', groups => [] );

    while ( $last_group != $user_group ) {
        my $sql    = "SELECT * FROM nt_group WHERE deleted=0 AND nt_group_id = ?";
        my $groups = $self->exec_query( $sql, $cur_group )
            or return {
            error_code => 600,
            error_msg  => $self->{dbh}->errstr,
            };

        my $group = $groups->[0];
        $last_group = $cur_group;
        $cur_group  = $group->{parent_group_id};

        unshift @{ $rv{groups} }, $group;
    }

    return \%rv;
}

sub log_group {
    my ( $self, $data, $action, $prev_data ) = @_;

    my $user = $data->{user};
    $data->{modified_group_id} ||= $data->{nt_group_id};
    $data->{nt_user_id} = $user->{nt_user_id};
    $data->{action}     = $action;
    $data->{timestamp}  = time();

    my $insertid = $self->insert_row( 'nt_group_log', $data,
        qw/ nt_group_id parent_group_id nt_user_id action timestamp modified_group_id name / );

    $data->{object}       = 'group';
    $data->{log_entry_id} = $insertid;
    $data->{title}        = $data->{name} || $prev_data->{name} || '(group)';
    $data->{object_id}    = $data->{modified_group_id};

    if ( $action eq 'modified' ) {    # modified
        $prev_data->{modified_group_id} = delete( $prev_data->{nt_group_id} );

        $data->{description} = $self->diff_changes( $data, $prev_data );
    }
    elsif ( $action eq 'deleted' ) {    #deleted
        $data->{description} = 'deleted group';
    }
    elsif ( $action eq 'added' ) {      #added
        $data->{description} = 'initial creation';
    }

    $self->log_global($data);
}

sub find_group {
    my ( $self, $nt_group_id ) = @_;
    my $sql    = "SELECT * FROM nt_group WHERE nt_group_id = ?";
    my $groups = $self->exec_query( $sql, $nt_group_id );
    return $groups->[0] || {};
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Group - nictool groups (aka, permission realms)

=head1 VERSION

version 2.42

=head1 SYNOPSIS

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=item *

Damon Edwards

=item *

Abraham Ingersoll

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abraham Ingersoll, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
