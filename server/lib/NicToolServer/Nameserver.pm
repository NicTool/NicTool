package NicToolServer::Nameserver;
# ABSTRACT: manage NicTool nameservers

use strict;
use parent 'NicToolServer';

sub get_usable_nameservers {
    my ( $self, $data ) = @_;

    my @groups;
    if ( $data->{nt_group_id} ) {
        my $res = $self->NicToolServer::Group::get_group_branch($data);
        return $res if $self->is_error_response($res);
        @groups = map { $_->{nt_group_id} } @{ $res->{groups} };
    }

    push @groups, $self->{user}{nt_group_id};
    my @usable = split /,/, $self->{user}{usable_ns};

    my $r_data = $self->error_response(200);
    $r_data->{nameservers} = [];

    my $groups_string = join(',', @groups);
    my $usable_string = join(',', @usable);
    my $sql =
"
SELECT ns.nt_nameserver_id, ns.nt_group_id, ns.name, ns.description, ns.address, ns.remote_login,
    et.name AS export_format, ns.export_type_id,
    logdir, datadir, export_interval, export_serials, export_status
 FROM nt_nameserver ns
  LEFT JOIN nt_nameserver_export_type et ON ns.export_type_id=et.id
  WHERE ns.deleted=0
    AND (ns.nt_group_id IN ($groups_string)";

    if ($usable_string && scalar @usable) {
        $sql .= " OR ns.nt_nameserver_id IN ($usable_string)";
    };
    $sql .= " ORDER BY ns.nt_nameserver_id";
    $sql .= ")";

    #warn $sql;
    my $nameservers = $self->exec_query($sql)
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

    foreach my $row (@$nameservers) {
        push( @{ $r_data->{nameservers} }, $row );
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
        address6 => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver.address6'
        },
        export_format => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver_export_type.name'
        },
        export_type_id => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver.export_type_id'
        },
        status => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_nameserver.export_status'
        },
    );

    $field_map{group_name}
        = { timefield => 0, quicksearch => 0, field => 'nt_group.name' }
        if $data->{include_subgroups};

    my $conditions = $self->format_search_conditions( $data, \%field_map );

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

    my $r_data = { 'error_code' => 200, 'error_msg' => 'OK', list => [] };

    my $sql = "SELECT COUNT(*) AS count "
        . "FROM nt_nameserver ns "
        . "INNER JOIN nt_group g ON ns.nt_group_id = g.nt_group_id "
        . "LEFT JOIN nt_nameserver_export_type et ON ns.export_type_id=et.id "
        . "WHERE ns.deleted=0 "
        . "AND ns.nt_group_id IN("
        . join( ',', @group_list ) . ")"
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );
    my $c = $self->exec_query($sql);

    $r_data->{total} = $c->[0]{count};

    $self->set_paging_vars( $data, $r_data );

    my $sortby;
    return $r_data if $r_data->{total} == 0;

    if ( $r_data->{total} > 10000 ) {
        $sortby = $self->format_sort_conditions( $data, \%field_map, "" );
    }
    else {
        $sortby = $self->format_sort_conditions( $data, \%field_map, "ns.name" );
    }

    $sql = "SELECT ns.*,
        et.name AS export_format,
        g.name AS group_name,
        ns.export_status AS status
    FROM nt_nameserver ns
        LEFT JOIN nt_nameserver_export_type et ON ns.export_type_id=et.id
        INNER JOIN nt_group g ON ns.nt_group_id = g.nt_group_id
    WHERE ns.deleted=0
    AND g.nt_group_id IN(" . join( ',', @group_list ) . ") ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{start} - 1 ) . ", $r_data->{limit}";

    my $nameservers = $self->exec_query($sql)
        or return {
        error_code => '600',
        error_msg  => $self->{dbh}->errstr,
        };

    my %groups;
    foreach my $row (@$nameservers) {
        push( @{ $r_data->{list} }, $row );
        $groups{ $row->{nt_group_id} } = 1;
    }

    $r_data->{group_map}
        = $self->get_group_map( $data->{nt_group_id}, [ keys %groups ] );

    return $r_data;
}

sub get_nameserver_list {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK', list => [] );

# my %groups = map { $_, 1 } ($data->{user}{nt_group_id}, @{ $self->get_subgroup_ids($data->{user}{nt_group_id}) });

    my $sql = "SELECT ns.*, et.name AS export_format
  FROM nt_nameserver ns
  LEFT JOIN nt_nameserver_export_type et ON ns.export_type_id=et.id
WHERE deleted=0 AND ns.nt_nameserver_id IN(??) ORDER BY ns.name";

    my @ns_list = split( ',', $data->{nameserver_list} );
    my $nameservers = $self->exec_query( $sql, [@ns_list] )
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        list       => [],
        };

    foreach my $ns (@$nameservers) {
        push @{ $rv{list} }, $ns;
    }

    return \%rv;
}

sub move_nameservers {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my %groups = map { $_, 1 } (
        $data->{user}{nt_group_id},
        @{ $self->get_subgroup_ids( $data->{user}{nt_group_id} ) }
    );

    my $new_group
        = $self->NicToolServer::Group::find_group( $data->{nt_group_id} );

    my $sql
        = "SELECT ns.*, g.name AS old_group_name FROM nt_nameserver ns, nt_group g "
        . "WHERE ns.nt_group_id = g.nt_group_id AND nt_nameserver_id IN(??)";

    my @ns_list = split( ',', $data->{nameserver_list} );
    my $nameservers = $self->exec_query( $sql, [@ns_list] )
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

    foreach my $row (@$nameservers) {
        next unless $groups{ $row->{nt_group_id} };

        $sql = "UPDATE nt_nameserver SET nt_group_id=? WHERE nt_nameserver_id=?";
        $self->exec_query( $sql,
            [ $data->{nt_group_id}, $row->{nt_nameserver_id} ] )
            or next;

        my %ns = ( %$row, user => $data->{user} );
        $ns{nt_group_id} = $data->{nt_group_id};
        $ns{group_name}  = $new_group->{name};

        $self->log_nameserver( \%ns, 'moved', $row );
    }

    return \%rv;
}

sub get_nameserver {
    my ( $self, $data ) = @_;

    my $sql = "SELECT ns.*, et.name AS export_format
    FROM nt_nameserver ns
        LEFT JOIN nt_nameserver_export_type et ON ns.export_type_id=et.id
        WHERE nt_nameserver_id=?";

    my $nameservers = $self->exec_query( $sql, $data->{nt_nameserver_id} )
        or return {
            error_code => 600,
            error_msg  => $self->{dbh}->errstr,
        };

    return {
        %{ $nameservers->[0] },
        error_code => 200,
        error_msg  => 'OK',
    } if $nameservers->[0];

    return {
        error_code => 601,
        error_msg  => 'No nameserver with that ID found',
    };
}

sub get_nameserver_export_types {
    my ( $self, $data ) = @_;
    my $lookup = $data->{type};

    if ( ! $self->{export_types} ) {
        my $sql = "SELECT id,name,descr,url FROM nt_nameserver_export_type";
        my $types = $self->exec_query($sql);
        foreach my $t ( @$types ) {
            $self->{export_types}{$t->{id}} = $t;   # index by id
            $self->{export_types}{$t->{name}} = $t; # index by name
        }
        $self->{export_types}{'ALL'} = $types;
    };

    if ( $lookup =~ /^\d+$/ ) {   # all numeric
        return $self->{export_types}{$lookup}{name}; # return type name
    }
    if ( $lookup eq 'ALL' ) {
        return {
            types      => $self->{export_types}{'ALL'},
            error_code => 200,
            error_msg  => 'OK',
        };
    };

    return $self->{export_types}{$lookup}{id};  # got a name, return ID
};

sub new_nameserver {
    my ( $self, $data ) = @_;

    my @columns = qw/ nt_group_id nt_nameserver_id name ttl description logdir
        remote_login address address6 export_type_id datadir export_interval /;

    my $sql = "INSERT INTO nt_nameserver("
        . join( ',', @columns )
        . ') VALUES(??)';
    my @values = map( $data->{$_}, @columns);

    my $insertid = $self->exec_query($sql, \@values)
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

    $data->{nt_nameserver_id} = $insertid;
    $self->log_nameserver( $data, 'added' );

    return {
        error_code       => 200,
        error_msg        => 'OK',
        nt_nameserver_id => $insertid,
    };
}

sub edit_nameserver {
    my ( $self, $data ) = @_;

    my $dbh = $self->{dbh};
    my @columns = grep { exists $data->{$_} }
        qw/ nt_group_id nt_nameserver_id name ttl description address address6 remote_login
            export_type_id logdir datadir export_interval export_serials /;

    my $prev_data = $self->find_nameserver( $data->{nt_nameserver_id} );
    $data->{export_serials} = $data->{export_serials} ? 1 : 0;

    my $sql
        = "UPDATE nt_nameserver SET "
        . join( ',', map( "$_ = " . $dbh->quote( $data->{$_} ), @columns ) )
        . " WHERE nt_nameserver_id=?";

    $self->exec_query( $sql, $data->{nt_nameserver_id} )
        or return {
        error_code => 600,
        error_msg  => $dbh->errstr,
        };

    $self->log_nameserver( $data, 'modified', $prev_data );

    return {
        error_code       => 200,
        error_msg        => 'OK',
        nt_nameserver_id => $data->{nt_nameserver_id},
    };
}

sub delete_nameserver {
    my ( $self, $data ) = @_;

    my $dbh = $self->{dbh};

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my $sql = "SELECT z.nt_zone_id FROM nt_zone z
        LEFT JOIN nt_zone_nameserver n ON z.nt_zone_id = n.nt_zone_id
          WHERE z.deleted=0 AND n.nt_nameserver_id=?";

    my $zones = $self->exec_query( $sql, $data->{nt_nameserver_id} );

    if ( $zones && scalar @$zones ) {
        return $self->error_response( 600,
            "You can't delete this nameserver until you delete all of its zones"
        );
    }

    my $ns_data = $self->find_nameserver( $data->{nt_nameserver_id} );
    $ns_data->{user} = $data->{user};

    $sql = "UPDATE nt_nameserver SET deleted=1 WHERE nt_nameserver_id=?";
    $self->exec_query( $sql, $data->{nt_nameserver_id} )
        or return $self->error_response( 600, $dbh->errstr );

    $self->log_nameserver( $ns_data, 'deleted' );

    return \%error;
}

sub log_nameserver {
    my ( $self, $data, $action, $prev_data ) = @_;

    my $dbh     = $self->{dbh};
    my @columns = qw/ nt_group_id nt_user_id action timestamp nt_nameserver_id
        name ttl description address export_type_id logdir datadir export_interval /;

    my $user = $data->{user};
    $data->{nt_group_id} ||= $user->{nt_group_id};
    $data->{nt_user_id} = $user->{nt_user_id} if defined $user->{nt_user_id};
    $data->{action}     = $action;
    $data->{timestamp}  = time();

    my @values = map( $data->{$_}, @columns );
    my $sql = "INSERT INTO nt_nameserver_log("
        . join( ',', @columns )
        . ") VALUES(??)";

    my $insertid = $self->exec_query($sql, \@values);

    my @g_columns = qw/ nt_user_id timestamp action object object_id
        log_entry_id title description /;

    $data->{object}       = 'nameserver';
    $data->{log_entry_id} = $insertid;
    $data->{title}        = $data->{name};
    $data->{object_id}    = $data->{nt_nameserver_id};

    if ( $action eq 'modified' ) {
        $data->{description} = $self->diff_changes( $data, $prev_data );
    }
    elsif ( $action eq 'deleted' ) {
        $data->{description} = 'deleted nameserver';
    }
    elsif ( $action eq 'added' ) {
        $data->{description} = 'initial nameserver creation';
    }
    elsif ( $action eq 'moved' ) {
        $data->{description}
            = "moved from $data->{old_group_name} to $data->{group_name}";
    }

    $sql
        = "INSERT INTO nt_user_global_log("
        . join( ',', @g_columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @g_columns ) ) . ")";
    $self->exec_query($sql);
}

sub find_nameserver {
    my ( $self, $nt_nameserver_id ) = @_;
    my $sql = "SELECT * FROM nt_nameserver WHERE nt_nameserver_id=?";
    my $nameservers = $self->exec_query( $sql, $nt_nameserver_id )
        or return {};
    return $nameservers->[0];
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Nameserver - manage NicTool nameservers

=head1 VERSION

version 2.33

=head1 SYNOPSIS

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
