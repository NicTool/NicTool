package NicToolServer::Nameserver;

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

@NicToolServer::Nameserver::ISA = qw(NicToolServer);

sub get_usable_nameservers {
    my ( $self, $data ) = @_;

    my @groups;
    my @usable;
    if ( $data->{'nt_group_id'} ) {

        my $res = $self->NicToolServer::Group::get_group_branch($data);
        return $res if $self->is_error_response($res);
        @groups = map { $_->{'nt_group_id'} } @{ $res->{'groups'} };
    }

    push @groups, $self->{'user'}->{'nt_group_id'};
    foreach ( 0 .. 9 ) {
        push @usable, $self->{'user'}->{"usable_ns$_"}
            if $self->{'user'}->{"usable_ns$_"} ne 0;
    }

    my $r_data = $self->error_response(200);
    $r_data->{'nameservers'} = [];

    my $sql
        = "SELECT * FROM nt_nameserver "
        . " WHERE deleted = '0' AND (nt_group_id IN ("
        . join( ",", @groups )
        . ")"
        . (
        @usable
        ? " OR " . "nt_nameserver_id IN (" . join( ",", @usable ) . " )"
        : ''
        ) . " ) ";

    my $nameservers = $self->exec_query( $sql )
        or return {
            error_code => 600,
            error_msg  => $self->{dbh}->errstr,
        }; 

    foreach my $row ( @$nameservers ) {
        push( @{ $r_data->{'nameservers'} }, $row );
    }

    return $r_data;
}

sub get_group_nameservers {
    my ( $self, $data ) = @_;

    my %field_map = (
        name => {
            timefield   => 0,
            quicksearch => 1,
            field       => 'nt_nameserver.name'
        },
        description => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver.description'
        },
        address => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver.address'
        },
        service_type => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver.service_type'
        },
        output_format => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver.output_format'
        },
        status => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver_export_procstatus.status'
        },
    );

    $field_map{'group_name'}
        = { timefield => 0, quicksearch => 0, field => 'nt_group.name' }
        if $data->{'include_subgroups'};

    my $conditions = $self->format_search_conditions( $data, \%field_map );

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

    my $r_data = { 'error_code' => 200, 'error_msg' => 'OK', list => [] };

    my $sql = "SELECT COUNT(*) AS count FROM nt_nameserver "
        . "INNER JOIN nt_group ON nt_nameserver.nt_group_id = nt_group.nt_group_id "
        . "WHERE nt_nameserver.deleted = '0' "
        . "AND nt_nameserver.nt_group_id IN("
        . join( ',', @group_list ) . ")"
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
    my $c = $self->exec_query( $sql );

    $r_data->{'total'} = $c->[0]{count};

    $self->set_paging_vars( $data, $r_data );

    my $sortby;
    return $r_data if $r_data->{'total'} == 0;

    if ( $r_data->{'total'} > 10000 ) {
        $sortby = $self->format_sort_conditions( $data, \%field_map, "" );
    }
    else {
        $sortby = $self->format_sort_conditions( $data, \%field_map,
            "nt_nameserver.name" );
    }

    $sql = "SELECT nt_nameserver.*, "
        . " nt_group.name as group_name, "
        . " nt_nameserver_export_procstatus.status as status "
        . "FROM nt_nameserver "
        . "INNER JOIN nt_group ON nt_nameserver.nt_group_id = nt_group.nt_group_id "
        . "LEFT JOIN nt_nameserver_export_procstatus ON nt_nameserver.nt_nameserver_id = nt_nameserver_export_procstatus.nt_nameserver_id "
        . "WHERE nt_nameserver.deleted = '0' "
        . "AND nt_group.nt_group_id IN("
        . join( ',', @group_list ) . ") ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{'start'} - 1 ) . ", $r_data->{'limit'}";

    my $nameservers = $self->exec_query( $sql )
        or return {
            error_code => '600',
            error_msg  => $self->{dbh}->errstr,
        };

    my %groups;
    foreach my $row ( @$nameservers ) {
        push( @{ $r_data->{'list'} }, $row );
        $groups{ $row->{'nt_group_id'} } = 1;
    }

    $r_data->{group_map} = $self->get_group_map( $data->{nt_group_id},
        [ keys %groups ] );

    return $r_data;
}

sub get_nameserver_list {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK', list => [] );

# my %groups = map { $_, 1 } ($data->{'user'}->{'nt_group_id'}, @{ $self->get_subgroup_ids($data->{'user'}->{'nt_group_id'}) });

    my $sql = "SELECT * FROM nt_nameserver WHERE deleted = '0' AND nt_nameserver_id IN(??) ORDER BY name";

    my @ns_list = split(',', $data->{'nameserver_list'} );
    my $nameservers = $self->exec_query( $sql, [ @ns_list ] )
        or return {
            error_code => 600,
            error_msg  => $self->{dbh}->errstr,
            list       => [],
        };

    foreach my $ns ( @$nameservers ) {
        push( @{ $rv{list} }, $ns );
    }

    return \%rv;
}

sub move_nameservers {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my %groups = map { $_, 1 } (
        $data->{'user'}->{'nt_group_id'},
        @{ $self->get_subgroup_ids( $data->{'user'}->{'nt_group_id'} ) }
    );

    my $new_group
        = $self->NicToolServer::Group::find_group( $data->{'nt_group_id'} );

    my $sql = "SELECT nt_nameserver.*, nt_group.name as old_group_name FROM nt_nameserver, nt_group "
        . "WHERE nt_nameserver.nt_group_id = nt_group.nt_group_id AND nt_nameserver_id IN(??)";

    my @ns_list = split(',', $data->{'nameserver_list'} );
    my $nameservers = $self->exec_query( $sql, [ @ns_list ] )
        or return {
            error_code => 600,
            error_msg  => $self->{dbh}->errstr,
        };

    foreach my $row ( @$nameservers ) {
        next unless $groups{ $row->{nt_group_id} };

        $sql = "UPDATE nt_nameserver SET nt_group_id = ? WHERE nt_nameserver_id = ?";
        $self->exec_query( $sql, [ $data->{nt_group_id}, $row->{nt_nameserver_id} ] ) or next;

        my %ns = ( %$row, user => $data->{'user'} );
        $ns{'nt_group_id'} = $data->{'nt_group_id'};
        $ns{'group_name'}  = $new_group->{'name'};

        $self->log_nameserver( \%ns, 'moved', $row );
    }

    return \%rv;
}

sub get_nameserver {
    my ( $self, $data ) = @_;

    my $sql = "SELECT * FROM nt_nameserver WHERE nt_nameserver_id = ?";
    my $nameservers = $self->exec_query( $sql, $data->{nt_nameserver_id} )
        or return {
            error_code => 600,
            error_msg  => $self->{dbh}->errstr,
        };

    return {
        %{ $nameservers->[0] },
        error_code => 200,
        error_msg  => 'OK',
    };
}

sub new_nameserver {
    my ( $self, $data ) = @_;

    my @columns = qw/ nt_group_id nt_nameserver_id name ttl description 
        address service_type output_format logdir datadir export_interval /;

    my $sql = "INSERT INTO nt_nameserver(" . join( ',', @columns ) . ") VALUES("
        . join( ',', map( $self->{dbh}->quote( $data->{$_} ), @columns ) ) . ")";
    my $action = 'added';

    my $insertid = $self->exec_query( $sql ) 
        or return {
            error_code => 600,
            error_msg  => $self->{dbh}->errstr,
        };

    $data->{'nt_nameserver_id'} = $insertid;
    $self->log_nameserver( $data, $action );

    return {
        error_code => 200, 
        error_msg  => 'OK',
        nt_nameserver_id => $action == 'added' ? $insertid : $data->{nt_nameserver_id},
    };
}

sub edit_nameserver {
    my ( $self, $data ) = @_;

    my $dbh = $self->{dbh};
    my @columns = grep { exists $data->{$_} }
        qw(nt_group_id nt_nameserver_id name ttl description address service_type output_format logdir datadir export_interval);

    my $prev_data = $self->find_nameserver( $data->{'nt_nameserver_id'} );

    my $sql = "UPDATE nt_nameserver SET "
        . join( ',', map( "$_ = " . $dbh->quote( $data->{$_} ), @columns ) )
        . " WHERE nt_nameserver_id = ?";

    $self->exec_query( $sql, $data->{'nt_nameserver_id'} )
        or return {
            error_code => 600,
            error_msg  => $dbh->errstr,
        };

    $self->log_nameserver( $data, 'modified', $prev_data );

    return {
        error_code => 200,
        error_msg  => 'OK',
        nt_nameserver_id => $data->{nt_nameserver_id},
    };
}

sub delete_nameserver {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my $nsid = $dbh->quote( $data->{'nt_nameserver_id'} );
    my $sql = "SELECT nt_zone_id FROM nt_zone WHERE deleted = '0'"
        . " AND (ns0 = $nsid OR ns1 = $nsid OR ns2 = $nsid OR ns3 = $nsid"
        . " OR ns4 = $nsid OR ns5 = $nsid OR ns6 = $nsid OR ns7 = $nsid"
        . " OR ns8 = $nsid OR ns9 = $nsid)";

    my $zones = $self->exec_query( $sql );

    if ( scalar @$zones ) {
        return $self->error_response( 600,
            "You can't delete this nameserver until you delete all of its zones"
        );
    }

    my $ns_data = $self->find_nameserver( $data->{'nt_nameserver_id'} );
    $ns_data->{'user'} = $data->{'user'};

    $sql = "UPDATE nt_nameserver SET deleted = '1' WHERE nt_nameserver_id = ?";
    $self->exec_query( $sql, $data->{'nt_nameserver_id'} )
        or return $self->error_response( 600, $dbh->errstr );

    $self->log_nameserver( $ns_data, 'deleted' );

    return \%error;
}

sub log_nameserver {
    my ( $self, $data, $action, $prev_data ) = @_;

    my $dbh = $self->{'dbh'};
    my @columns = qw/ nt_group_id nt_user_id action timestamp nt_nameserver_id
    name ttl description address service_type output_format logdir datadir export_interval /;

    my $user = $data->{'user'};
    $data->{'nt_user_id'} = $user->{'nt_user_id'};
    $data->{'action'}     = $action;
    $data->{'timestamp'}  = time();

    my $sql = "INSERT INTO nt_nameserver_log(" . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";

    my $insertid = $self->exec_query( $sql );

    my @g_columns = qw/ nt_user_id timestamp action object object_id
        log_entry_id title description /;

    $data->{'object'}       = 'nameserver';
    $data->{'log_entry_id'} = $insertid;
    $data->{'title'}        = $data->{'name'};
    $data->{'object_id'}    = $data->{'nt_nameserver_id'};

    if ( $action eq 'modified' ) {
        $data->{'description'} = $self->diff_changes( $data, $prev_data );
    }
    elsif ( $action eq 'deleted' ) {
        $data->{'description'} = 'deleted nameserver';
    }
    elsif ( $action eq 'added' ) {
        $data->{'description'} = 'initial nameserver creation';
    }
    elsif ( $action eq 'moved' ) {
        $data->{'description'}
            = "moved from $data->{'old_group_name'} to $data->{'group_name'}";
    }

    $sql = "INSERT INTO nt_user_global_log("
        . join( ',', @g_columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @g_columns ) ) . ")";
    $self->exec_query( $sql );
}

sub find_nameserver {
    my ( $self, $nt_nameserver_id ) = @_;
    my $sql = "SELECT * FROM nt_nameserver WHERE nt_nameserver_id = ?";
    my $nameservers = $self->exec_query( $sql, $nt_nameserver_id ) or return {};
    return $nameservers->[0];
}

1;
