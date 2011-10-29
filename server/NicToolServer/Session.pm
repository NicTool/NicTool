package NicToolServer::Session;

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
use warnings;
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);

@NicToolServer::Session::ISA = qw(NicToolServer);

sub debug_session_sql {0}

### public methods
sub verify {    # return of 0 = sucess, return of anything else = error
    my $self = shift;

    my $data = $self->{'client'}->data();
    $data->{'action'} = uc( $data->{'action'} );

    my $vcheck = $self->ver_check;
    return $vcheck if $vcheck;

    #warn "action is ".$data->{'action'};
    return $self->verify_login if $data->{'action'} eq 'LOGIN';
    return $self->verify_session;  # just verify the session
}

### private methods
sub verify_login {
    my $self = shift;

# timeout_sessions could be called from a cron job every $NicToolServer::session_timeout,
# but this is easier to setup
    $self->timeout_sessions;

    my $data = $self->{'client'}->data();
    my $dbh  = $self->{'dbh'};

    my $error_msg = 'Invalid username and/or password.';

    return $self->auth_error('invalid group(s)')
        if ! $self->populate_groups;  # sets $data->nt_group_id

    my $sql
        = "SELECT nt_user.*, nt_group.name AS groupname FROM nt_user, nt_group "
        . "WHERE nt_user.nt_group_id = nt_group.nt_group_id AND "
        . "nt_user.deleted = '0' AND nt_user.nt_group_id IN ("
        . join( ',', @{ $data->{'groups'} } )
        . ") AND nt_user.username = " . $dbh->quote( $data->{'username'} );

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_session_sql;
    $sth->execute() || return $self->error_response( 505, $dbh->errstr );

    return $self->auth_error('no such username') if ! $sth->rows;
    return $self->auth_error('invalid username') if $sth->rows > 1;

    my $attempted_pass = $data->{'password'};
    delete( $data->{'password'} )
        ; # must delete the hashkey or perl maintains attempted_pass as a ref to the hash key's lvalue

    $data->{'user'} = $sth->fetchrow_hashref;

    # RCC - Handle HMAC passwords
    if ($data->{user}{password} =~ /[0-9a-f]{40}/) {
        $attempted_pass = hmac_sha1_hex($attempted_pass, $data->{username} );
    }

    return $self->auth_error('invalid password')
        if $attempted_pass ne $data->{user}{password};

    $self->clean_user_data;

    $data->{'user'}->{'nt_user_session'} = $self->session_id;

    $sql = "SELECT * "
        . "FROM nt_perm "
        . "WHERE deleted = '0' "
        . "AND nt_user_id = "
        . $data->{'user'}->{'nt_user_id'};

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || return $self->error_response( 505, $dbh->errstr );

    my $groupperm;
    my $perm = $sth->fetchrow_hashref;

    $sql = "SELECT nt_perm.* FROM nt_perm"
        . " INNER JOIN nt_user ON nt_perm.nt_group_id = nt_user.nt_group_id "
        . " WHERE ( nt_perm.deleted = '0' "
        . " AND nt_user.deleted = '0' "
        . " AND nt_user.nt_user_id = "
        . $dbh->quote( $data->{'user'}->{'nt_user_id'} ) . " )";
    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || return $self->error_response( 505, $dbh->errstr );
    $groupperm = $sth->fetchrow_hashref;

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
                . $data->{'user'}->{'nt_user_id'}
                . ")" );
    }
    delete $perm->{'nt_user_id'};
    delete $perm->{'nt_group_id'};
    delete $perm->{'nt_perm_id'};
    delete $perm->{'nt_perm_name'};

    #@{$data->{'user'}}{sort keys %$perm} = @{$perm}{sort keys %$perm};
    foreach ( keys %$perm ) {
        $data->{'user'}->{$_} = $perm->{$_};
    }

    $sql = 'INSERT INTO nt_user_session(nt_user_id, nt_user_session, last_access) VALUES ('
        . "$data->{'user'}->{nt_user_id},"
        . $dbh->quote( $data->{'user'}->{'nt_user_session'} ) . ','
        . time() . ')';
    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_session_sql;
    $sth->execute() || warn $dbh->errstr;
    my $nt_user_session_id = $dbh->{'mysql_insertid'};

    $sql = "INSERT INTO nt_user_session_log(nt_user_id, action, timestamp, nt_user_session_id, nt_user_session) VALUES ("
        . "$data->{user}->{'nt_user_id'}, 'login',"
        . time()
        . ",$nt_user_session_id,"
        . $dbh->quote( $data->{'user'}->{'nt_user_session'} ) . ')';
    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_session_sql;
    $sth->execute || warn $dbh->errstr;

    return 0;
}

sub verify_session {
    my $self = shift;

    my $data = $self->{'client'}->data();
    my $dbh  = $self->{'dbh'};

    my $sql
        = "SELECT nt_user.*, nt_user_session.*, nt_group.name as groupname FROM nt_user_session, nt_user, nt_group "
        . "WHERE nt_user_session.nt_user_id = nt_user.nt_user_id "
        . "AND nt_user.nt_group_id = nt_group.nt_group_id "
        . "AND nt_user.deleted = '0' "
        . "AND nt_user_session.nt_user_session = "
        . $dbh->quote( $data->{'nt_user_session'} );

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_session_sql;
    $sth->execute || return $self->error_response( 505, $dbh->errstr );

    return $self->auth_error('Your session has expired. Please login again')
        unless ( $sth->rows );

    $data->{'user'} = $sth->fetchrow_hashref;

    if (time() - $NicToolServer::session_timeout
        >= $data->{'user'}->{'last_access'} )
    {

        # use logout to nuke the timed-out session
        $self->logout('timeout');
        return $self->auth_error(
            'Your session has expired. Please login again');
    }

    # delete session and log logout if LOGOUT
    return $self->logout if ( $data->{'action'} eq 'LOGOUT' );

    #warn "data 'action' was not LOGOUT: $data->{'action'}";

    $sql
        = "SELECT * FROM nt_perm WHERE deleted = '0' "
        . "AND nt_user_id = "
        . $data->{'user'}->{'nt_user_id'};

    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || return $self->error_response( 505, $dbh->errstr );

    my $groupperm;
    my $perm = $sth->fetchrow_hashref;

    #if( !$perm) {
    $sql
        = "SELECT nt_perm.* FROM nt_perm"
        . " INNER JOIN nt_user ON nt_perm.nt_group_id = nt_user.nt_group_id "
        . " WHERE ( nt_perm.deleted = '0' "
        . " AND nt_user.deleted = '0' "
        . " AND nt_user.nt_user_id = "
        . $dbh->quote( $data->{'user'}->{'nt_user_id'} ) . " )";
    $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_sql;
    $sth->execute || return $self->error_response( 505, $dbh->errstr );
    $groupperm = $sth->fetchrow_hashref;

    #}

    if ( !$perm ) {
        $perm = $groupperm;
    }
    else {

        #for now usable_ns settings are always inherited from the group
        for ( 0 .. 9 ) {
            $perm->{"usable_ns$_"} = $groupperm->{"usable_ns$_"};
        }
    }

    if ( !$perm ) {
        return $self->error_response( 507,
                  "Could not find permissions for user ("
                . $data->{'user'}->{'nt_user_id'}
                . ")" );
    }
    delete $perm->{'nt_user_id'};
    delete $perm->{'nt_group_id'};

    #@{$data->{'user'}}{sort keys %$perm} = @{$perm}{sort keys %$perm};
    foreach ( keys %$perm ) {
        $data->{'user'}->{$_} = $perm->{$_};
    }

    $sql
        = "UPDATE nt_user_session SET last_access = "
        . time()
        . " WHERE nt_user_session_id = "
        . $dbh->quote( $data->{'user'}->{'nt_user_session_id'} );
    $dbh->do($sql);
    warn "$sql\n" if $self->debug_session_sql;

    $self->clean_user_data;

    return 0;
}

sub logout {
    my $self = shift;
    my $msg  = shift;
    $msg ||= 'logout';

    #warn "calling Session::logout ... ".join(" ",caller);
    my $data = $self->{'client'}->data();
    my $dbh  = $self->{'dbh'};

    my $sql = "DELETE FROM nt_user_session WHERE nt_user_session_id = "
        . $dbh->quote( $data->{'user'}->{'nt_user_session_id'} );
    $dbh->do($sql);
    warn "$sql\n" if $self->debug_session_sql;

    $sql
        = "INSERT INTO nt_user_session_log(nt_user_id, action, timestamp, nt_user_session, nt_user_session_id) VALUES ( "
        . $dbh->quote( $data->{user}->{'nt_user_id'} )
        . ",'$msg',"
        . time() . ','
        . $dbh->quote( $data->{'user'}->{'nt_user_session'} ) . ','
        . $dbh->quote( $data->{'user'}->{'nt_user_session_id'} ) . ')';

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_session_sql;
    $sth->execute || warn $dbh->errstr;

    foreach my $key ( keys %$data ) {
        delete( $data->{$key} );
    }

    return { 'error_code' => 200, error_msg => 'OK', nt_user_session => '' };

}

sub populate_groups
{ # return true on successful population of @$data->{'groups'}, otherwise return false
    my $self = shift;

    my $data = $self->{'client'}->data();
    my $dbh  = $self->{'dbh'};

    $data->{'groups'} = [];

    my $sql;
    if ( $data->{'username'} =~ /(.+)\@(.+)/ ) {
        $data->{'username'} = $1;
        my $g = $2;
        $sql
            = "SELECT nt_group_id FROM nt_group WHERE deleted = '0' AND name = "
            . $dbh->quote($g);
    }
    else {
        return 0 unless @NicToolServer::default_groups;
        my @groups;
        foreach (@NicToolServer::default_groups) {
            push( @groups, $dbh->quote($_) );
        }
        $sql
            = "SELECT nt_group_id FROM nt_group WHERE deleted = '0' AND name IN ( "
            . join( ',', @groups ) . ')';
    }

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_session_sql;
    $sth->execute || warn $dbh->errstr;

    my $i = 0;
    while ( my @row = $sth->fetchrow ) {
        push( @{ $data->{'groups'} }, $row[0] );
        $i++;
    }

    # if no group found, return false, else return true
    $i < 1 ? return 0 : return 1;
}

sub timeout_sessions {
    my $self = shift;

    my $dbh         = $self->{'dbh'};
    my $valid_until = time() - $NicToolServer::session_timeout;
    my $sql
        = "SELECT nt_user_id, last_access, nt_user_session_id FROM nt_user_session WHERE last_access < $valid_until";

    my $sth = $dbh->prepare($sql);
    warn "$sql\n" if $self->debug_session_sql;
    $sth->execute;
    while ( my $s = $sth->fetchrow_hashref ) {

        # delete the dead session
        $sql
            = "DELETE FROM nt_user_session WHERE nt_user_session_id = $s->{'nt_user_session_id'}";
        $dbh->do($sql);
        warn "$sql\n" if $self->debug_session_sql;

        # log that the session was auto_logged out
        $sql
            = "INSERT INTO nt_user_session_log(nt_user_id, action, timestamp, nt_user_session, nt_user_session_id) VALUES ( "
            . $dbh->quote( $s->{'nt_user_id'} )
            . ",'timeout',"
            . time() . ','
            . $dbh->quote( $s->{'nt_user_session'} ) . ','
            . $dbh->quote( $s->{'nt_user_session_id'} ) . ')';

        my $sth2 = $dbh->prepare($sql);
        warn "$sql\n" if $self->debug_session_sql;
        $sth2->execute;
    }
}

sub clean_user_data
{    # delete unused and password data from DB-returned user hash
    my $self = shift;

    my $data = $self->{'client'}->data();

    my @fields = qw(password deleted nt_user_session_id last_access);

    foreach my $f (@fields) {
        delete( $data->{'user'}->{$f} )
            if ( exists( $data->{'user'}->{$f} ) );
    }

}

sub auth_error {
    my ( $self, $msg ) = @_;
    return { error_code => '403', error_msg => $msg };
}

sub session_id {
    my $self = shift;

    return $ENV{UNIQUE_ID} if ( $ENV{UNIQUE_ID} );    # mod_uniqeid sets this

    warn "mod_uniqueid not available - building my own unique ID.\n"
        if $self->debug;

    srand( $$ | time );
    my $session = int( rand(60000) );
    $session = unpack( "H*", pack( "Nnn", time, $$, $session ) );
    return $session;

}

1;
