package NicToolServer::Session;
# ABSTRACT: manage nictool login sessions

use strict;
use warnings;

@NicToolServer::Session::ISA = qw/NicToolServer NicToolServer::User/;

sub debug_session_sql {0}

### public methods
sub verify {

    # return of 0 = sucess, return of anything else = error
    my $self = shift;

    my $data = $self->{client}->data();
    $data->{action} = uc $data->{action};

    my $vcheck = $self->ver_check;
    return $vcheck if $vcheck;

    #warn "action is ".$data->{action};
    return $self->verify_login if $data->{action} eq 'LOGIN';
    return $self->verify_session;    # just verify the session
}

### private methods
sub verify_login {
    my $self = shift;

    # timeout_sessions could be called from a cron job every
    # $NicToolServer::session_timeout. This is easier to setup
    $self->timeout_sessions;

    my $data = $self->{client}->data();
    my $dbh  = $self->{dbh};

    my $error_msg = 'Invalid username and/or password.';

    return $self->auth_error('invalid group(s)')
        if !$self->populate_groups;    # sets $data->nt_group_id

    my ($err, $user) = $self->_get_user($data->{username}, $data->{groups});
    return $err if $err;

    my $pass_attempt = delete $data->{password};

    $data->{user} = $user;

    return $self->auth_error('invalid password')
        if (! $self->valid_password( $pass_attempt, $user->{password},
              $data->{username}, $user->{pass_salt} ));

    $self->clean_user_data;

    $user->{nt_user_session} = $self->session_id;

    my $uid = $user->{nt_user_id};

    my ($user_perm, $groupperm);
    ($err, $user_perm) = $self->_get_user_perms($uid);
    return $err if $err;
    ($err, $groupperm) = $self->_get_group_perms($uid);
    return $err if $err;

    if ( !$user_perm ) {
        $user_perm = $groupperm;
        $user_perm->{inherit_group_permissions} = 1;
    }
    else {
        $user_perm->{inherit_group_permissions} = 0;

        # usable_ns settings are always inherited from the group
        $user_perm->{usable_ns} = $groupperm->{usable_ns};
    }

    if ( !$user_perm ) {
        return $self->error_response( 507,
                  "Could not find permissions for user ($uid)" );
    }

    $self->clean_perm_data($user_perm);

    foreach ( keys %$user_perm ) {
        $data->{user}{$_} = $user_perm->{$_};
    }

    my $session = $user->{nt_user_session};
    my $session_id = $self->exec_query(
        'INSERT INTO nt_user_session(nt_user_id, nt_user_session,
            last_access) VALUES (??)',
        [ $uid, $session, time() ]
    ) or return;

    $self->_insert_session_log($session_id, $uid, $session, 'login');

    return 0;
}

sub _get_user {
    my ($self, $user, $groups) = @_;

# nt_user_id|nt_group_id|first_name|last_name|username|password|email      |is_admin|deleted|groupname|
#         1 |         1 | Root     | User    | root   |50aaa...|user@domain|    NULL|      0|NicTool  |
    my $sql = "SELECT nt_user.*, nt_group.name AS groupname
    FROM nt_user, nt_group
    WHERE nt_user.nt_group_id = nt_group.nt_group_id
      AND nt_user.deleted=0
      AND nt_user.nt_group_id IN (" . join( ',', @$groups ) . ")
      AND nt_user.username = ?";

    my $users = $self->exec_query( $sql, $user )
        or return $self->error_response( 505, $self->{dbh}->errstr );

    return $self->auth_error('no such username') if scalar @$users == 0;
    return $self->auth_error('invalid username') if scalar @$users  > 1;
    return (undef, $users->[0]);
};

sub _get_user_perms {
    my ($self, $nt_uid) = @_;

    my $perms = $self->exec_query(
        "SELECT * FROM nt_perm WHERE deleted=0 AND nt_user_id = ?",
        $nt_uid
    ) or return $self->error_response( 505, $self->{dbh}->errstr );
    return (undef, $perms->[0]);
};

sub _get_group_perms {
    my ($self, $nt_uid) = @_;

    my $sql = "SELECT nt_perm.*
    FROM nt_perm
    INNER JOIN nt_user ON nt_perm.nt_group_id = nt_user.nt_group_id
    WHERE ( nt_perm.deleted=0
            AND nt_user.deleted=0
            AND nt_user.nt_user_id = ?
           )";
    my $perms = $self->exec_query( $sql, $nt_uid )
        or return $self->error_response( 505, $self->{dbh}->errstr );
    return (undef, $perms->[0]);
};

sub verify_session {
    my $self = shift;

    my $data = $self->{client}->data();
    my $dbh  = $self->{dbh};

    my ($err, $user_perm, $groupperm, $session);
    ($err, $session) = $self->_get_session($data->{nt_user_session});
    return $err if $err;

    return $self->auth_error('Your session has expired.') if ! $session;

    $data->{user} = $session;

    # delete session and log logout if LOGOUT
    return $self->logout if $data->{action} eq 'LOGOUT';

    # why is this sometimes not set?
    if ( $data->{user}{last_access} ) {
        my $minutes = $self->get_option('session_timeout') || 45;
        my $max_age = time() - ($minutes * 60);
        if ( $max_age >= $data->{user}{last_access} ) {
            $self->logout('timeout');
            return $self->auth_error('Your session expired.');
        }
    };

    my $uid = $data->{user}{nt_user_id};

    ($err, $user_perm) = $self->_get_user_perms($uid);
    return $err if $err;
    ($err, $groupperm) = $self->_get_group_perms($uid);
    return $err if $err;

    if ( !$user_perm ) {
        $user_perm = $groupperm;
    }
    else {
        # usable_ns settings are always inherited from the group
        $user_perm->{usable_ns} = $groupperm->{usable_ns};
    }

    if ( !$user_perm ) {
        return $self->error_response( 507, "Could not find permissions for user id ($uid)" );
    }
    $self->clean_perm_data($user_perm);

    foreach ( keys %$user_perm ) {
        $data->{user}{$_} = $user_perm->{$_};
    }

    $self->exec_query(
        "UPDATE nt_user_session SET last_access=? WHERE nt_user_session_id=?",
        [ time(), $data->{user}{nt_user_session_id} ]
    );

    $self->clean_user_data;

    return 0;
}

sub logout {
    my $self = shift;
    my $msg  = shift || 'logout';

    #warn "calling Session::logout ... ".join(" ",caller);
    my $user = $self->{client}->data->{user};

    $self->_delete_session($user->{nt_user_session_id});

    if ( ! $user->{nt_user_id} ) {
        warn "calling Session::logout ... ".join(' ',caller);
    }
    else {
        $self->_insert_session_log(
            $user->{nt_user_session_id},
            $user->{nt_user_id},
            $user->{nt_user_session},
            $msg
        );
    };

    my $data = $self->{client}->data();
    foreach my $key ( keys %$data ) { delete( $data->{$key} ); };

    return { 'error_code' => 200, error_msg => 'OK', nt_user_session => '' };
}

sub populate_groups {
    my $self = shift;

# return true on successful population of @$data->{groups}

    my $data = $self->{client}->data();

    my $ids;
    $data->{groups} = [];

    if ( $data->{username} =~ /(.+)\@(.+)/ ) {
        $data->{username} = $1;
        $ids = $self->exec_query(
            "SELECT nt_group_id FROM nt_group WHERE deleted=0 AND name=?",
            $2
        );
    }
    else {
        my $default_group = $self->get_option('default_group') || 'NicTool';

        $ids = $self->exec_query(
            "SELECT nt_group_id FROM nt_group WHERE deleted=0 AND name IN (?)",
            [$default_group],
        );
    }

    foreach (@$ids) {
        push @{ $data->{groups} }, $_->{nt_group_id};
    }

    # if no group found, return false, else return true
    return scalar @{ $data->{groups} } < 1 ? 0 : 1;
}

sub timeout_sessions {
    my $self = shift;

    my $minutes = $self->get_option('session_timeout') || 45;
    my $valid_until = time() - ($minutes * 60);

    my $sessions = $self->exec_query( "SELECT nt_user_id, last_access,
        nt_user_session_id, nt_user_session
        FROM nt_user_session WHERE last_access < ?", $valid_until
    );

    foreach my $s (@$sessions) {
        my $sess_id = $s->{nt_user_session_id};

        $self->_delete_session($sess_id);   # dead session

        next if ! defined $s->{nt_user_id};

        $self->_insert_session_log($sess_id, $s->{nt_user_id}, $s->{nt_user_session}, 'timeout');
    }
}

sub clean_user_data {
    my $self = shift;

    # delete unused and password data from DB-returned user hash
    foreach my $f ( qw/ password deleted nt_user_session_id last_access / ) {
        next if ! exists $self->{client}->data->{user}->{$f};
        delete $self->{client}->data->{user}->{$f};
    }
}

sub auth_error {
    my ( $self, $msg ) = @_;
    return { error_code => '403', error_msg => $msg };
}

sub session_id {
    my $self = shift;

    return $ENV{UNIQUE_ID} if $ENV{UNIQUE_ID};  # mod_uniqueid sets this

    warn "mod_uniqueid not available - building my own unique ID.\n"
        if $self->debug;

    srand( $$ | time );
    my $session = int( rand(60000) );
    $session = unpack( "H*", pack( "Nnn", time, $$, $session ) );
    return $session;
};


sub _get_session {
    my ($self, $id) = @_;

    my $sessions = $self->exec_query( "
SELECT u.*, s.*, g.name AS groupname
  FROM nt_user_session s
   LEFT JOIN nt_user u ON s.nt_user_id = u.nt_user_id
   LEFT JOIN nt_group g ON u.nt_group_id = g.nt_group_id
  WHERE u.deleted=0
    AND s.nt_user_session = ?",
        $id
    ) or return $self->error_response( 505, $self->{dbh}->errstr );
    return (undef, $sessions->[0]);
};

sub _delete_session {
    my ($self, $id) = @_;
    if (! $id) {
        warn "no session ID!\n";
        return;
    };
    $self->exec_query( "DELETE FROM nt_user_session WHERE nt_user_session_id = ?",
        $id
    );
};

sub _insert_session_log {
    my ($self, $sess_id, $uid, $sess, $why) = @_;

    $self->exec_query( "INSERT INTO nt_user_session_log
        (nt_user_id, action, timestamp, nt_user_session, nt_user_session_id) VALUES (??)",
        [ $uid, $why, time(), $sess, $sess_id ]
    );
};

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Session - manage nictool login sessions

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
