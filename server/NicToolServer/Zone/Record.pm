package NicToolServer::Zone::Record;

#
# $Id: Record.pm 667 2008-10-01 01:33:43Z matt $
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

@NicToolServer::Zone::Record::ISA = qw(NicToolServer::Zone);

sub save_zone_record {
    my ( $self, $data ) = @_;
    warn
        "XXX: Zone::Record::save_zone_record is deprecated as of NicToolServer 2.0: "
        . Data::Dumper::Dumper($data);
    return $self->error_response( 503,
        "save_zone_record, use new_zone_record or edit_zone_record" );
}

sub new_zone_record {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my @columns
        = qw(nt_zone_id name ttl description type address weight priority other);
    my @values;

    my $z = $self->find_zone( $data->{'nt_zone_id'} );
    my ( $sql, $log_action, $prev_data );
    if ( my $del = $self->get_param_meta( 'nt_zone_id', 'delegate' ) ) {
        return $self->error_response( 404,
            "Not allowed to add records to the delegated zone." )
            unless $del->{'zone_perm_add_records'};
    }

    # bump the zone's serial number
    my $new_serial
        = $self->bump_serial( $data->{'nt_zone_id'}, $z->{'serial'} );
    $sql = "UPDATE nt_zone SET serial = $new_serial WHERE nt_zone_id = "
        . $dbh->quote( $data->{'nt_zone_id'} );
    $dbh->do($sql);
    warn "$sql\n" if $self->debug_sql;

    $sql
        = "INSERT INTO nt_zone_record("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";
    $log_action = 'added';

    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {
        $error{'error_code'} = 600;
        $error{'error_msg'}  = $dbh->errstr;
    }
    else {
        $error{'nt_zone_record_id'}
            = ( $log_action eq 'added' )
            ? $dbh->{'mysql_insertid'}
            : $data->{'nt_zone_record_id'};
    }

    my $insertid = $dbh->{'mysql_insertid'};
    $data->{'nt_zone_record_id'} = $insertid;

    $self->log_zone_record( $data, $log_action, $prev_data, $z );

    return \%error;
}

sub edit_zone_record {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my @columns = grep { exists $data->{$_} }
        qw(name ttl description type address weight priority other);
    my @values;

    my $z = $self->find_zone( $data->{'nt_zone_id'} );
    my $sql;
    my $log_action;
    my $prev_data;

    # bump the zone's serial number
    my $new_serial
        = $self->bump_serial( $data->{'nt_zone_id'}, $z->{'serial'} );
    $sql = "UPDATE nt_zone SET serial = $new_serial WHERE nt_zone_id = "
        . $dbh->quote( $data->{'nt_zone_id'} );
    $dbh->do($sql);
    warn "$sql\n" if $self->debug_sql;

    $prev_data = $self->find_zone_record( $data->{'nt_zone_record_id'} );
    $log_action = $prev_data->{'deleted'} ? 'recovered' : 'modified';
    $data->{'deleted'} = 0;
    $sql = "UPDATE nt_zone_record SET "
        . join( ',',
        map( "$_ = " . $dbh->quote( $data->{$_} ), ( @columns, 'deleted' ) ) )
        . " WHERE nt_zone_record_id = "
        . $data->{'nt_zone_record_id'};

    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {
        $error{'error_code'} = 600;
        $error{'error_msg'}  = $dbh->errstr;
    }
    else {
        $error{'nt_zone_record_id'}
            = ( $log_action eq 'added' )
            ? $dbh->{'mysql_insertid'}
            : $data->{'nt_zone_record_id'};
    }

    if ( !$data->{'nt_zone_record_id'} ) {
        my $insertid = $dbh->{'mysql_insertid'};
        $data->{'nt_zone_record_id'} = $insertid;
    }

    $self->log_zone_record( $data, $log_action, $prev_data, $z );

    return \%error;
}

sub delete_zone_record {
    my ( $self, $data, $zone ) = @_;

    my $dbh = $self->{'dbh'};

    if ( my $del = $self->get_param_meta( 'nt_zone_record_id', 'delegate' ) )
    {
        return $self->error_response( 404,
            "Not allowed to delete delegated record." )
            unless $del->{'pseudo'} && $del->{'zone_perm_delete_records'};
    }

    my $sql
        = "SELECT nt_zone_id FROM nt_zone_record WHERE nt_zone_record_id = "
        . $dbh->quote( $data->{'nt_zone_record_id'} );
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    my @zonerow = $sth->fetchrow;

    my $new_serial = $self->bump_serial( $zonerow[0] );
    $sql = "UPDATE nt_zone SET serial = $new_serial WHERE nt_zone_id = "
        . $dbh->quote( $zonerow[0] );
    $dbh->do($sql);
    warn "$sql\n" if $self->debug_sql;

    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );
    $sql
        = "UPDATE nt_zone_record set deleted = '1' WHERE nt_zone_record_id = "
        . $dbh->quote( $data->{'nt_zone_record_id'} );

    my $zr_data = $self->find_zone_record( $data->{'nt_zone_record_id'} );
    $zr_data->{'user'} = $data->{'user'};

    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {
        $error{'error_code'} = 600;
        $error{'error_msg'}  = $dbh->errstr;
    }

    $self->log_zone_record( $zr_data, 'deleted', {}, $zone );

    return \%error;
}

sub log_zone_record {
    my ( $self, $data, $action, $prev_data, $zone ) = @_;

    $zone ||= $self->find_zone( $data->{'nt_zone_id'} );

    my $dbh = $self->{'dbh'};
    my @columns
        = qw(nt_zone_id nt_zone_record_id nt_user_id action timestamp name ttl description type address weight priority other);
    my @values;

    my $user = $data->{'user'};
    $data->{'nt_user_id'} = $user->{'nt_user_id'};
    $data->{'action'}     = $action;
    $data->{'timestamp'}  = time();

    # get zone_id if it's not provided.
    unless ( $data->{'nt_zone_id'} ) {
        my $db_data = $self->find_zone_record( $data->{'nt_zone_record_id'} );
        $data->{'nt_zone_id'} = $db_data->{'nt_zone_id'};
    }

    my $sql
        = "INSERT INTO nt_zone_record_log("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";

    warn "$sql\n" if $self->debug_sql;
    $dbh->do($sql) || warn $dbh->errstr;

    my @g_columns
        = qw(nt_user_id timestamp action object object_id log_entry_id title description);

    $data->{'object'}       = 'zone_record';
    $data->{'log_entry_id'} = $dbh->{'mysql_insertid'};
    $data->{'object_id'}    = $data->{'nt_zone_record_id'};

    if ( uc( $data->{'type'} ) ne 'MX' || uc( $data->{'type'} ) ne 'SRV' ) {
        delete $data->{'weight'};
    }
    if ( uc( $data->{'type'} ) ne 'SRV' ) {
        delete $data->{'other'};
        delete $data->{'priority'};
    }

    if ( $data->{'name'} =~ /\.$/ ) {
        $data->{'title'} = $data->{'name'};
    }
    else {
        $data->{'title'} = $data->{'name'} . "." . $zone->{'zone'} . ".";
    }

    if ( $action eq 'modified' ) {
        $data->{'description'} = $self->diff_changes( $data, $prev_data );
    }
    elsif ( $action eq 'deleted' ) {
        $data->{'description'} = "deleted record from $zone->{'zone'}";
    }
    elsif ( $action eq 'added' ) {
        $data->{'description'} = 'initial creation';
    }
    elsif ( $action eq 'recovered' ) {
        $data->{'description'}
            = "recovered previous settings ($data->{'type'} $data->{'weight'} $data->{'address'})";
    }

    $sql
        = "INSERT INTO nt_user_global_log("
        . join( ',', @g_columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @g_columns ) ) . ")";
    $dbh->do($sql) || warn $dbh->errstr;

}

sub get_zone_record {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    $data->{'sortby'} ||= 'name';

    my $sql
        = "SELECT * FROM nt_zone_record WHERE nt_zone_record_id = "
        . $dbh->quote( $data->{'nt_zone_record_id'} )
        . " ORDER BY $data->{'sortby'}";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    my %rv;
    if ( $sth->execute ) {
        %rv               = %{ $sth->fetchrow_hashref };
        $rv{'error_code'} = 200;
        $rv{'error_msg'}  = 'OK';
        if ( my $del
            = $self->get_param_meta( 'nt_zone_record_id', 'delegate' ) )
        {

# this info comes from NicToolServer.pm when it checks for access perms to the objects
            my %mapping = (
                delegated_by_id   => 'delegated_by_id',
                delegated_by_name => 'delegated_by_name',
                pseudo            => 'pseudo',
                perm_write        => 'delegate_write',
                perm_delete       => 'delegate_delete',
                perm_delegate     => 'delegate_delegate',
                group_name        => 'group_name'
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

sub get_zone_record_log_entry {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my $sql
        = "SELECT nt_zone_record_log.* FROM nt_zone_record_log "
        . "   INNER JOIN nt_zone_record on nt_zone_record_log.nt_zone_record_id=nt_zone_record.nt_zone_record_id"
        . "   WHERE nt_zone_record_log.nt_zone_record_log_id = "
        . $dbh->quote( $data->{'nt_zone_record_log_id'} )
        . "   AND nt_zone_record.nt_zone_record_id="
        . $dbh->quote( $data->{'nt_zone_record_id'} );

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    my $rv;
    if ( $sth->execute ) {
        if ( $rv = $sth->fetchrow_hashref ) {
            $rv->{'error_code'} = 200;
            $rv->{'error_msg'}  = 'OK';
        }
        else {
            $rv = $self->error_response( 600, 'No such log entry exists' );
        }
    }
    else {
        $rv = $self->error_response( 600, $sth->errstr );
    }
    $sth->finish;
    return $rv;
}

sub find_zone_record {
    my ( $self, $nt_zone_record_id ) = @_;

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT * FROM nt_zone_record WHERE nt_zone_record_id = $nt_zone_record_id";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    return $sth->fetchrow_hashref || {};
}

1;

