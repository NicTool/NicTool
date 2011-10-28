package NicToolServer::User;

#
# $Id: User.pm 1044 2010-03-26 00:53:36Z matt $
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
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);

@NicToolServer::User::ISA = qw(NicToolServer);

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

sub perm_fields {
    qw(group_create group_delete group_write
        zone_create zone_delegate zone_delete zone_write
        zonerecord_create zonerecord_delegate zonerecord_delete zonerecord_write
        user_create user_delete user_write self_write
        nameserver_create nameserver_delete nameserver_write);
}

sub get_user {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my $sql = "SELECT * FROM nt_user WHERE nt_user_id = "
        . $dbh->quote( $data->{'nt_user_id'} );
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
    $rv{'password'} = '' if exists $rv{'password'};

    if ( $rv{'error_code'} ne 200 ) {
        return \%rv;
    }

    $sql
        = "SELECT "
        . $self->perm_fields_select
        . " FROM nt_perm WHERE deleted = '0' "
        . "AND nt_user_id = "
        . $data->{'nt_user_id'};

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || return $self->error_response( 505, $dbh->errstr );

    my $perm = $sth->fetchrow_hashref;

    # if( !$perm) {
    $sql
        = "SELECT "
        . $self->perm_fields_select
        . " FROM nt_perm"
        . " INNER JOIN nt_user ON nt_perm.nt_group_id = nt_user.nt_group_id "
        . " WHERE ( nt_perm.deleted = '0' "
        . " AND nt_user.deleted = '0' "
        . " AND nt_user.nt_user_id = "
        . $dbh->quote( $data->{'nt_user_id'} ) . " )";
    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || return $self->error_response( 505, $dbh->errstr );
    my $groupperm = $sth->fetchrow_hashref;

    # }
    if ( !$perm ) {
        $perm = $groupperm;
        $perm->{'inherit_group_permissions'} = 1;
    }
    else {
        $perm->{'inherit_group_permissions'} = 0;

        #for now usable_ns settings are always inherited from the group
        for ( 0 .. 9 ) {
            $perm->{"usable_ns$_"} = $groupperm->{"usable_ns$_"};
        }
    }
    if ( !$perm ) {
        return $self->error_response( 507,
                  "Could not find permissions for user ("
                . $data->{'nt_user_id'}
                . ")" );
    }
    delete $perm->{'nt_user_id'};
    delete $perm->{'nt_group_id'};
    delete $perm->{'nt_perm_id'};
    delete $perm->{'nt_perm_name'};

    #@rv{sort keys %$perm} = @{$perm}{sort keys %$perm};
    foreach ( keys %$perm ) {
        $rv{$_} = $$perm{$_};
    }

    return \%rv;
}

sub save_user {
    my ( $self, $data ) = @_;
    warn "XXX: User::save_user is deprecated as of NicToolServer 2.0: "
        . Data::Dumper::Dumper($data);
    return $self->error_result( 503, 'save_user, use new_user or edit_user' );
}

sub new_user {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my @columns
        = qw(nt_group_id first_name last_name username email password);

# only update the password if the field isn't NULL (has been provided)
#push(@columns, 'password') if (exists($data->{'password'}) && $data->{'password'} ne '');

    # RCC - use hmac to store the password using the username as a key
    $data->{'password'} = hmac_sha1_hex($data->{'password'}, $data->{'username'});

    my @values;

    my ( $sql, $action, $prev_data );

    $sql
        = "INSERT INTO nt_user("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";
    $action = 'added';

    warn "$sql\n" if $self->debug_sql;

    unless ( $dbh->do($sql) ) {
        $error{'error_code'} = 600;
        $error{'error_msg'}  = $dbh->errstr;
    }
    else {
        $error{'nt_user_id'} = $dbh->{'mysql_insertid'};
    }

    my $insertid = $dbh->{'mysql_insertid'};
    $data->{'modified_user_id'} = $insertid;
    my @permcols = $self->perm_fields;
    if ( $insertid && @permcols && !$data->{'inherit_group_permissions'} ) {

#XXX can set usable ns stuff explicitly for user but has no effect (see NicToolServer/Session.pm and  get_user function
        my @usable = split( /,/, $data->{'usable_nameservers'} );

        @usable = @usable[ 0 .. 9 ] if scalar @usable gt 10;
        my @ns = map {"usable_ns$_"} ( 0 .. scalar @usable - 1 );

        foreach (@permcols) {
            $data->{$_} = 0 unless exists $data->{$_};
            $data->{$_} = 0 unless $self->{'user'}->{$_};
        }

        $sql
            = "INSERT INTO nt_perm("
            . join( ',', 'nt_group_id', 'nt_user_id', @permcols, @ns )
            . ") VALUES("
            . join( ',',
            0, $insertid, map( $dbh->quote( $data->{$_} ), @permcols ),
            @usable )
            . ")";

        warn "$sql\n" if $self->debug_sql;

        unless ( $dbh->do($sql) ) {
            $error{'error_code'} = 600;
            $error{'error_msg'}  = $dbh->errstr;
        }
    }

    $self->log_user( $data, $action, $prev_data );

    return \%error;
}

sub edit_user {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};
    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my @columns = grep { exists $data->{$_} }
        qw(nt_group_id first_name last_name username email);

    # only update the password if the field is not NULL
    push( @columns, 'password' )
        if ( exists( $data->{'password'} ) && $data->{'password'} ne '' );

    # RCC - use hmac to store the password using the username as a key
    $data->{'password'} = hmac_sha1_hex($data->{'password'}, $data->{'username'});

    my @values;

    my ( $sql, $action, $prev_data );

    $prev_data = $self->get_user( { nt_user_id => $data->{'nt_user_id'} } );
    return $prev_data if $self->is_error_response($prev_data);

    if (@columns) {
        $sql
            = "UPDATE nt_user SET "
            . join( ',',
            map( "$_ = " . $dbh->quote( $data->{$_} ), @columns ) )
            . " WHERE nt_user_id = "
            . $dbh->quote( $data->{'nt_user_id'} );
        $action = 'modified';

        warn "$sql\n" if $self->debug_sql;

        unless ( $dbh->do($sql) ) {
            $error{'error_code'} = 600;
            $error{'error_msg'}  = $dbh->errstr;
        }
        else {
            $error{'nt_user_id'} = $data->{'nt_user_id'};
        }

        #VVVVVVVVVVVV
        #cruft  ?
        if ( !$data->{'modified_user_id'} ) {
            my $insertid = $dbh->{'mysql_insertid'};
            $data->{'modified_user_id'} = $insertid;
        }

        #cruft  ?
        #^^^^^^^^^^^^

    }

#XXX may want to let this happen ?
#prevent user from modifying their own permissions (since all they could do is remove perms)
    if ( $data->{'nt_user_id'} eq $self->{'user'}->{'nt_user_id'} ) {
        delete @$data{ $self->perm_fields, 'usable_nameservers' };
    }

    #permissions are kind of independent from other user-data,
    #so we will not rollback if something goes wrong now

    #perms the current user doesn't have.
    my %nonperm
        = map { $_ => 1 } grep { !$data->{'user'}->{$_} } $self->perm_fields;
    my @permcols = grep { exists $data->{$_} && $data->{'user'}->{$_} }
        $self->perm_fields;

#XXX can set usable_nameservers explicitly for a user, but they will always be inherited. (see get_user and Session.pm)
    my @usable = split( /,/, $data->{'usable_nameservers'} );

    my %ns;
    my @nskeys;
    if (@usable) {
        @usable = map { $usable[$_] ? $usable[$_] : 0 } ( 0 .. 9 );
        @nskeys = map {"usable_ns$_"} ( 0 .. 9 );
        %ns = map { ( "usable_ns$_" => $usable[$_] ) } ( 0 .. 9 );
    }

    #see if the user has explicit perms
    #$sql = "SELECT * FROM nt_perm WHERE nt_user_id = ".$data->{'nt_user_id'};
    #warn "$sql\n" if $self->debug_sql;
    my $sth; # = $dbh->prepare($sql);
             #$sth->execute || return $self->error_response(505,$dbh->errstr);
    if ( !$prev_data->{'inherit_group_permissions'} ) {

        #the user has some explicit permissions
        #$sth->finish;
        if ( $data->{'inherit_group_permissions'} ) {

#make sure moving from explicit perms to inherited perms doesn't restrict a permission
# that the executing user doens't have the right to modify
            $sql
                = "SELECT nt_perm.*,nt_user.nt_group_id as group_id FROM nt_perm INNER JOIN nt_user ON nt_perm.nt_group_id = nt_user.nt_group_id "
                . " AND nt_user.nt_user_id = "
                . $data->{'nt_user_id'};
            $sth = $dbh->prepare($sql);
            $sth->execute
                || return $self->error_response( 505, $dbh->errstr );
            if ( my $group = $sth->fetchrow_hashref ) {
                foreach my $k ( keys %nonperm ) {
                    return $self->error_response( 404,
                        "You do not have permission to restrict the $k permission of that user."
                    ) if !$group->{$k} && $prev_data->{$k};
                }

#things are good, we will now delete the user perms and perms will then be inherited automatically.
                $sql = "DELETE FROM nt_perm WHERE nt_user_id = "
                    . $data->{'nt_user_id'};
            }
            else {

                #this would be bad
                return $self->error_response( 507,
                    "No group permissions were found (!!) for the user's group: USER : $data->{'nt_user_id'} (YOUR DB HAS A PROBLEM)"
                );
            }
        }
        else {

            #ok, update the user perms which are allowed
            if ( @permcols + keys %ns ) {
                $sql = "UPDATE nt_perm SET "
                    . join( ',',
                    map( "$_ = " . $dbh->quote( $data->{$_} ), @permcols ),
                    map( "$_ = " . $ns{$_},                    keys %ns ) )
                    . " WHERE nt_user_id = "
                    . $data->{'nt_user_id'};
            }
            else {
                $sql = '';
            }
        }
        if ($sql) {
            warn "$sql\n" if $self->debug_sql;

            if ( $dbh->do($sql) ) {
                $action = 'modified';
            }
            else {
                $error{'error_code'} = 600;
                $error{'error_msg'}  = $dbh->errstr;
            }
        }
    }
    elsif ( !$data->{'inherit_group_permissions'} && ( @permcols + @nskeys ) )
    {

        #no preexisting permissions, so just insert into db
        $sql
            = "INSERT INTO nt_perm("
            . join( ',', 'nt_group_id', 'nt_user_id', @permcols, @nskeys )
            . ") VALUES("
            . join( ',',
            0, $data->{'nt_user_id'},
            map( $dbh->quote( $data->{$_} ), @permcols ),
            map( $ns{$_},                    @nskeys ) )
            . ")";

        warn "$sql\n" if $self->debug_sql;

        if ( $dbh->do($sql) ) {
            $action = 'modified';
        }
        else {
            $error{'error_code'} = 600;
            $error{'error_msg'}  = $dbh->errstr;
        }
    }
    else {

   #perms are already inherited and inherit_group_permissions is 1: do nothing
    }

    $data->{'nt_group_id'} = $prev_data->{'nt_group_id'}
        unless $data->{'nt_group_id'};
    if ($action) {
        $self->log_user( $data, $action, $prev_data );
    }

    return \%error;
}

sub delete_users {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my %groups = map { $_, 1 } (
        $data->{'user'}->{'nt_group_id'},
        @{ $self->get_subgroup_ids( $data->{'user'}->{'nt_group_id'} ) }
    );

    my $dbh = $self->{'dbh'};
    my $sql = "SELECT * FROM nt_user WHERE nt_user_id IN("
        . $data->{'user_list'} . ")";
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
            = "UPDATE nt_user SET deleted = '1' WHERE nt_user_id = $row->{'nt_user_id'}";
        warn "$sql\n" if $self->debug_sql;

        if ( $dbh->do($sql) ) {
            my %user = ( %$row, user => $data->{'user'} );
            $self->log_user( \%user, 'deleted', $row );
        }
    }
    $sth->finish;

    return \%rv;
}

sub get_group_users {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %field_map = (
        username =>
            { timefield => 0, quicksearch => 1, field => 'nt_user.username' },
        first_name => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_user.first_name'
        },
        last_name => {
            timefield   => 0,
            quicksearch => 0,
            field       => 'nt_user.last_name'
        },
        email =>
            { timefield => 0, quicksearch => 0, field => 'nt_user.email' },
    );

    $field_map{'group_name'}
        = { timefield => 0, quicksearch => 0, field => 'nt_group.name' }
        if $data->{'include_subgroups'};

    my $conditions = $self->format_search_conditions( $data, \%field_map );
    my $sortby = $self->format_sort_conditions( $data, \%field_map,
        "nt_user.username" );

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

    my $sql = "SELECT COUNT(*) FROM nt_user ";
    $sql
        .= "INNER JOIN nt_group ON nt_user.nt_group_id = nt_group.nt_group_id ";
    $sql .= "WHERE nt_user.deleted = '0' ";
    $sql
        .= "AND nt_user.nt_group_id IN("
        . join( ',', @group_list ) . ")"
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || return $self->error_response( 600, $sth->errstr );
    $r_data->{'total'} = $sth->fetch->[0];
    $sth->finish;

    $self->set_paging_vars( $data, $r_data );

    if ( $r_data->{'total'} == 0 ) {
        return $r_data;
    }

    $sql
        = "SELECT nt_user.nt_user_id, "
        . "       nt_user.username, "
        . "       nt_user.first_name, "
        . "	   nt_user.last_name, "
        . "	   nt_user.email, "
        . "       nt_user.nt_group_id, "
        . "	   nt_group.name as group_name "
        . "FROM nt_user "
        . "INNER JOIN nt_group ON nt_user.nt_group_id = nt_group.nt_group_id "
        . "WHERE nt_user.deleted = '0' "
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

sub move_users {
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
        = "SELECT nt_user.*, nt_group.name as old_group_name FROM nt_user, nt_group WHERE nt_user.nt_group_id = nt_group.nt_group_id AND nt_user_id IN("
        . $data->{'user_list'} . ")";
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
            = "UPDATE nt_user SET nt_group_id = "
            . $dbh->quote( $data->{'nt_group_id'} )
            . " WHERE nt_user_id = $row->{'nt_user_id'}";
        warn "$sql\n" if $self->debug_sql;

        if ( $dbh->do($sql) ) {
            my %user = ( %$row, user => $data->{'user'} );
            $user{'nt_group_id'} = $data->{'nt_group_id'};
            $user{'group_name'}  = $new_group->{'name'};

            $self->log_user( \%user, 'moved', $row );
        }
    }
    $sth->finish;

    return \%rv;
}

sub get_user_list {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK', list => [] );

    my %groups = map { $_, 1 } (
        $data->{'user'}->{'nt_group_id'},
        @{ $self->get_subgroup_ids( $data->{'user'}->{'nt_group_id'} ) }
    );

    my $dbh = $self->{'dbh'};
    my $sql
        = "SELECT * FROM nt_user WHERE deleted = '0' AND nt_user_id IN("
        . $data->{'user_list'}
        . ") ORDER BY username";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;

    unless ( $sth->execute ) {
        $rv{'error_code'} = 600;
        $rv{'error_msg'}  = $sth->errstr;
        return \%rv;
    }

    while ( my $row = $sth->fetchrow_hashref ) {
        next unless ( $groups{ $row->{'nt_group_id'} } );
        $row->{'password'} = '' if exists $row->{'password'};
        push( @{ $rv{'list'} }, $row );
    }
    $sth->finish;

    return \%rv;
}

sub get_user_global_log {
    my ( $self, $data ) = @_;

    my $dbh = $self->{'dbh'};

    my %field_map = (
        timestamp => {
            timefield   => 1,
            quicksearch => 0,
            field       => 'nt_user_global_log.timestamp'
        },
        title => {
            timefield   => 0,
            quicksearch => 1,
            field       => 'nt_user_global_log.title'
        },
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
        description => {
            timefield   => 0,
            quicksearch => 1,
            field       => 'nt_user_global_log.description'
        },
    );

    my $conditions = $self->format_search_conditions( $data, \%field_map );
    my $sortby = $self->format_sort_conditions( $data, \%field_map,
        "nt_user_global_log.timestamp DESC" );

    my $r_data = { error_code => 200, error_msg => 'OK', list => [] };

    my $sql = "SELECT COUNT(*) FROM nt_user_global_log, nt_user ";
    $sql .= "WHERE nt_user_global_log.nt_user_id = nt_user.nt_user_id ";
    $sql
        .= "AND nt_user.nt_user_id = "
        . $dbh->quote( $data->{'nt_user_id'} ) . " "
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $sth = $dbh->prepare($sql);
    $sth->execute;
    $r_data->{'total'} = $sth->fetch->[0];
    $sth->finish;

    $self->set_paging_vars( $data, $r_data );

    if ( $r_data->{'total'} == 0 ) {
        return $r_data;
    }

    $sql
        = "SELECT nt_user_global_log.* "
        . "FROM nt_user_global_log, nt_user "
        . "WHERE nt_user_global_log.nt_user_id = nt_user.nt_user_id AND nt_user.nt_user_id = "
        . $dbh->quote( $data->{'nt_user_id'} ) . " ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{'start'} - 1 ) . ", $r_data->{'limit'}";

    $sth = $dbh->prepare($sql);

    if ( $sth->execute ) {
        while ( my $row = $sth->fetchrow_hashref ) {
            push( @{ $r_data->{'list'} }, $row );
        }
    }
    else {
        $r_data->{'error_code'} = '600';
        $r_data->{'error_msg'}  = $sth->errstr;
    }
    $sth->finish;

    return $r_data;
}

sub log_user {
    my ( $self, $data, $action, $prev_data ) = @_;

    my $dbh = $self->{'dbh'};
    my @columns
        = qw(nt_group_id nt_user_id action timestamp modified_user_id first_name last_name username email password);
    my @values;

    my $user = $data->{'user'};
    $data->{'modified_user_id'} ||= $data->{'nt_user_id'};
    $data->{'nt_user_id'} = $prev_data->{'nt_user_id'}
        = $user->{'nt_user_id'};
    $data->{'action'}    = $action;
    $data->{'timestamp'} = time();

    my $sql
        = "INSERT INTO nt_user_log("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";

    warn "$sql\n" if $self->debug_sql or $self->debug_logs;

    $dbh->do($sql) || warn $dbh->errstr;

    my @g_columns
        = qw(nt_user_id timestamp action object object_id log_entry_id title description);

    $data->{'object'}       = 'user';
    $data->{'log_entry_id'} = $dbh->{'mysql_insertid'};
    $data->{'title'} 
        = $data->{'username'}
        || $prev_data->{'username'}
        || $self->get_title( 'user', $prev_data->{'nt_user_id'} );
    $data->{'object_id'} = $data->{'modified_user_id'};

    if ( $action eq 'modified' ) {
        $data->{'description'} = $self->diff_changes( $data, $prev_data );
    }
    elsif ( $action eq 'deleted' ) {
        $data->{'description'} = 'deleted user';
    }
    elsif ( $action eq 'added' ) {
        $data->{'description'} = 'initial user creation';
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

    warn "$sql\n" if $self->debug_sql or $self->debug_logs;
    $dbh->do($sql) || warn $dbh->errstr;

}

sub find_user {
    my ( $self, $nt_user_id ) = @_;

    my $dbh = $self->{'dbh'};
    my $sql = "SELECT * FROM nt_user WHERE nt_user_id = $nt_user_id";
    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute;
    return $sth->fetchrow_hashref || {};
}

1;
