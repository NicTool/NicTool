package NicToolServer::Nameserver;

#
# $Id: Nameserver.pm 639 2008-09-13 04:43:46Z matt $
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

#my @groups = ($data->{'nt_group_id'}, @{ $self->get_parentgroup_ids($data->{'nt_group_id'}) });
    my @groups;
    my @usable;
    my $dbh = $self->{'dbh'};
    if ( $data->{'nt_group_id'} ) {

#push @groups,$data->{'nt_group_id'};
#my $gperm = $self->NicToolServer::Permission::get_group_permissions({nt_group_id=>$data->{'nt_group_id'}});

#warn "using ". ($data->{'nt_group_id'}? "data " : "user ").$gperm->{'nt_group_id'};
#warn "gperm group id is ".$gperm->{'nt_group_id'};
#foreach (0..9){
#push @usable,$gperm->{"usable_ns$_"} if $gperm->{"usable_ns$_"} ne 0;
#}
        my $res = $self->NicToolServer::Group::get_group_branch($data);
        return $res if $self->is_error_response($res);
        @groups = map { $_->{'nt_group_id'} } @{ $res->{'groups'} };
    }

    #if($data->{'include_for_user'} || !$data->{'nt_group_id'}){
    push @groups, $self->{'user'}->{'nt_group_id'};
    foreach ( 0 .. 9 ) {
        push @usable, $self->{'user'}->{"usable_ns$_"}
            if $self->{'user'}->{"usable_ns$_"} ne 0;
    }

    #}
    my $sql
        = "SELECT * FROM nt_nameserver "
        . " WHERE deleted = '0' "
        . " AND (nt_group_id IN ("
        . join( ",", @groups )
        . ")"    #$gperm->{'nt_group_id'}
        . (
        @usable
        ? " OR " . "nt_nameserver_id IN (" . join( ",", @usable ) . " )"
        : ''
        ) . " ) ";

  #my $sql = "SELECT DISTINCT n.* FROM nt_nameserver as n "
  #.   "INNER JOIN nt_group as g "
  #.       "ON g.nt_group_id=n.nt_group_id "
  #.   "INNER JOIN nt_group_subgroups as s "
  #.       "ON g.nt_group_id=s.nt_group_id OR g.nt_group_id=s.nt_subgroup_id "
  #.   "WHERE g.deleted = '0' "
  #.   "AND n.deleted = '0' "
  #.   "AND s.nt_group_id=".$self->{'user'}->{'nt_group_id'}
  #.   (@usable ?
  #" OR "
  #. "n.deleted='0' "
  #. "AND nt_nameserver_id IN (".join (",",@usable)." )"
  #: '')
  #;

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    my $r_data = $self->error_response(200);
    $r_data->{'nameservers'} = [];

    if ( $sth->execute ) {
        while ( my $row = $sth->fetchrow_hashref ) {
            push( @{ $r_data->{'nameservers'} }, $row );
        }
    }
    else {
        $r_data->{'error_code'} = '600';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    return $r_data;
}

sub get_nameserver_tree_old {
    my ( $self, $data ) = @_;

    my @groups = (
        $data->{'nt_group_id'},
        @{ $self->get_parentgroup_ids( $data->{'nt_group_id'} ) }
    );

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT * FROM nt_nameserver WHERE deleted = '0' AND nt_group_id IN (";
    $sql .= join( ",", @groups ) . ")";

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    my $r_data = {};
    $r_data->{'nameservers'} = [];

    if ( $sth->execute ) {
        while ( my $row = $sth->fetchrow_hashref ) {
            push( @{ $r_data->{'nameservers'} }, $row );
        }
    }
    else {
        $r_data->{'error_code'} = '600';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    return $r_data;
}

sub get_group_nameservers {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

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

    my $sql = "SELECT COUNT(*) FROM nt_nameserver ";
    $sql
        .= "INNER JOIN nt_group ON nt_nameserver.nt_group_id = nt_group.nt_group_id ";
    $sql .= "WHERE nt_nameserver.deleted = '0' ";
    $sql
        .= "AND nt_nameserver.nt_group_id IN("
        . join( ',', @group_list ) . ")"
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

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
        $sortby = $self->format_sort_conditions( $data, \%field_map, "" );
    }
    else {
        $sortby = $self->format_sort_conditions( $data, \%field_map,
            "nt_nameserver.name" );
    }

    $sql = "SELECT nt_nameserver.*, "

        #.   "nt_nameserver.nt_nameserver_id, "
        #. " nt_nameserver.name, "
        #. "	nt_nameserver.description, "
        #. " nt_nameserver.address, "
        #. " nt_nameserver.service_type, "
        #. " nt_nameserver.output_format, "
        #. " nt_nameserver.nt_group_id, "
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

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    if ( $sth->execute ) {
        my %groups;
        while ( my $row = $sth->fetchrow_hashref ) {
            push( @{ $r_data->{'list'} }, $row );
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

sub get_nameserver_list {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK', list => [] );

#my %groups = map { $_, 1 } ($data->{'user'}->{'nt_group_id'}, @{ $self->get_subgroup_ids($data->{'user'}->{'nt_group_id'}) });

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT * FROM nt_nameserver WHERE deleted = '0' AND nt_nameserver_id IN("
        . $data->{'nameserver_list'}
        . ") ORDER BY name";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    unless ( $sth->execute ) {
        $rv{'error_code'} = 600;
        $rv{'error_msg'}  = $sth->errstr;
        return \%rv;
    }

    while ( my $row = $sth->fetchrow_hashref ) {

        #    next unless( $groups{ $row->{'nt_group_id'} } );

        push( @{ $rv{'list'} }, $row );
    }
    $sth->finish;

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

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT nt_nameserver.*, nt_group.name as old_group_name FROM nt_nameserver, nt_group WHERE nt_nameserver.nt_group_id = nt_group.nt_group_id AND nt_nameserver_id IN("
        . $data->{'nameserver_list'} . ")";
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
            = "UPDATE nt_nameserver SET nt_group_id = "
            . $dbh->quote( $data->{'nt_group_id'} )
            . " WHERE nt_nameserver_id = $row->{'nt_nameserver_id'}";
        warn "$sql\n" if $self->debug_sql;

        if ( $dbh->do($sql) ) {
            my %ns = ( %$row, user => $data->{'user'} );
            $ns{'nt_group_id'} = $data->{'nt_group_id'};
            $ns{'group_name'}  = $new_group->{'name'};

            $self->log_nameserver( \%ns, 'moved', $row );
        }
    }
    $sth->finish;

    return \%rv;
}

sub get_nameserver {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my $sql = "SELECT * FROM nt_nameserver WHERE nt_nameserver_id = "
        . $dbh->quote( $data->{'nt_nameserver_id'} );
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    my %rv;
    if ( $sth->execute ) {
        %rv               = %{ $sth->fetchrow_hashref };
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

sub save_nameserver {
    my ( $self, $data ) = @_;
    warn
        "XXX: Nameserver::save_nameserver is deprecated as of NicToolServer 2.0: "
        . Data::Dumper::Dumper($data);
    return $self->error_result( 503,
        'save_nameserver, use new_nameserver or edit_nameserver' );
}

sub new_nameserver {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my @columns
        = qw(nt_group_id nt_nameserver_id name ttl description address service_type output_format logdir datadir export_interval);
    my @values;

    my ( $sql, $action, $prev_data );

    $sql
        = "INSERT INTO nt_nameserver("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";
    $action = 'added';

    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {
        $error{'error_code'} = 600;
        $error{'error_msg'}  = $dbh->errstr;
        return \%error;
    }
    else {
        $error{'nt_nameserver_id'}
            = ( $action == 'added' )
            ? $dbh->{'mysql_insertid'}
            : $data->{'nt_nameserver_id'};
    }

    my $insertid = $dbh->{'mysql_insertid'};
    $data->{'nt_nameserver_id'} = $insertid;
    $self->log_nameserver( $data, $action, $prev_data );

    return \%error;
}

sub edit_nameserver {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my @columns = grep { exists $data->{$_} }
        qw(nt_group_id nt_nameserver_id name ttl description address service_type output_format logdir datadir export_interval);
    my @values;

    my ( $sql, $action, $prev_data );

    $sql
        = "UPDATE nt_nameserver SET "
        . join( ',', map( "$_ = " . $dbh->quote( $data->{$_} ), @columns ) )
        . " WHERE nt_nameserver_id = "
        . $data->{'nt_nameserver_id'};
    $action    = 'modified';
    $prev_data = $self->find_nameserver( $data->{'nt_nameserver_id'} );

    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {
        $error{'error_code'} = 600;
        $error{'error_msg'}  = $dbh->errstr;
        return \%error;
    }
    else {
        $error{'nt_nameserver_id'}
            = ( $action == 'added' )
            ? $dbh->{'mysql_insertid'}
            : $data->{'nt_nameserver_id'};
    }

    $self->log_nameserver( $data, $action, $prev_data );

    return \%error;
}

sub delete_nameserver {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my $nsid = $dbh->quote( $data->{'nt_nameserver_id'} );
    my $sql
        = "SELECT nt_zone_id FROM nt_zone "
        . "WHERE deleted = '0' "
        . "AND (ns0 = $nsid OR ns1 = $nsid OR ns2 = $nsid OR ns3 = $nsid OR ns4 = $nsid OR ns5 = $nsid OR ns6 = $nsid OR ns7 = $nsid OR ns8 = $nsid OR ns9 = $nsid)";

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    if ( $sth->rows ) {
        return $self->error_response( 600,
            "You can't delete this nameserver until you delete all of it's zones"
        );
    }

    my $ns_data = $self->find_nameserver( $data->{'nt_nameserver_id'} );
    $ns_data->{'user'} = $data->{'user'};

    $sql
        = "UPDATE nt_nameserver SET deleted = '1' WHERE nt_nameserver_id = $nsid";

    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {

        #$error{'error_code'} = 600;
        #$error{'error_msg'} = $dbh->errstr;
        return $self->error_response( 600, $dbh->errstr );
    }

    $self->log_nameserver( $ns_data, 'deleted' );

    return \%error;
}

sub log_nameserver {
    my ( $self, $data, $action, $prev_data ) = @_;

    my $dbh = $self->{'dbh'};
    my @columns
        = qw(nt_group_id nt_user_id action timestamp nt_nameserver_id name ttl description address service_type output_format logdir datadir export_interval);
    my @values;

    my $user = $data->{'user'};
    $data->{'nt_user_id'} = $user->{'nt_user_id'};
    $data->{'action'}     = $action;
    $data->{'timestamp'}  = time();

    my $sql
        = "INSERT INTO nt_nameserver_log("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";

    warn "$sql\n" if $self->debug_sql;
    $dbh->do($sql) || warn $dbh->errstr;

    my @g_columns
        = qw(nt_user_id timestamp action object object_id log_entry_id title description);

    $data->{'object'}       = 'nameserver';
    $data->{'log_entry_id'} = $dbh->{'mysql_insertid'};
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

    $sql
        = "INSERT INTO nt_user_global_log("
        . join( ',', @g_columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @g_columns ) ) . ")";
    warn "$sql\n" if $self->debug_sql;
    $dbh->do($sql) || warn $dbh->errstr;
}

sub find_nameserver {
    my ( $self, $nt_nameserver_id ) = @_;

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT * FROM nt_nameserver WHERE nt_nameserver_id = $nt_nameserver_id";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    return $sth->fetchrow_hashref || {};
}

1;
