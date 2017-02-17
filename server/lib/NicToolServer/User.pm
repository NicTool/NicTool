package NicToolServer::User;
# ABSTRACT: NicTool user management

use strict;
use Crypt::Mac::HMAC;
use Crypt::KeyDerivation;

@NicToolServer::User::ISA = 'NicToolServer';

sub perm_fields_select {
    qq/
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

    nt_perm.usable_ns
    /;
}

sub perm_fields {
    qw/ group_create group_delete group_write
        zone_create zone_delegate zone_delete zone_write
        zonerecord_create zonerecord_delegate zonerecord_delete zonerecord_write
        user_create user_delete user_write self_write
        nameserver_create nameserver_delete nameserver_write/;
}

sub get_user {
    my ( $self, $data ) = @_;

    my $err;
    ($err, my $user) = $self->select_user($data->{nt_user_id});
    return $err if $err;

    my %rv = ( error_code => 200, error_msg  => 'OK', %$user );

    $rv{password} = '' if exists $rv{password};

    ($err, my $user_perm) = $self->_select_user_perm($data->{nt_user_id});
    return $err if $err;

    ($err, my $group_perm) = $self->_select_group_perm($data->{nt_user_id});
    return $err if $err;

    if ( !$user_perm ) {
        $user_perm = $group_perm;
        $user_perm->{inherit_group_permissions} = 1;
    }
    else {
        $user_perm->{inherit_group_permissions} = 0;

        #usable_ns settings are always inherited from the group
        $user_perm->{usable_ns} = $group_perm->{usable_ns};
    }
    if ( !$user_perm ) {
        return $self->error_response( 507,
                  "Could not find permissions for user ("
                . $data->{nt_user_id}
                . ")" );
    }
    $self->clean_perm_data($user_perm);

    foreach ( keys %$user_perm ) {
        $rv{$_} = $$user_perm{$_};
    }

    return \%rv;
}

sub new_user {
    my ( $self, $data ) = @_;

    my $dbh = $self->{dbh};
    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my @columns = qw/nt_group_id first_name last_name username email password pass_salt/;

    $data->{pass_salt} = $self->_get_salt();
    $data->{password} = $self->get_pbkdf2_hash($data->{password}, $data->{pass_salt});

    my $sql
        = "INSERT INTO nt_user("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";

    my $insertid = $self->exec_query($sql);

    if ( defined $insertid ) {
        $error{nt_user_id} = $insertid;
    }
    else {
        $error{error_code} = 600;
        $error{error_msg}  = $dbh->errstr;
    }

    $data->{modified_user_id} = $insertid;
    my @permcols = $self->perm_fields;
    if ( $insertid && @permcols && !$data->{inherit_group_permissions} ) {

        foreach (@permcols) {
            $data->{$_} = 0 unless exists $data->{$_};
            $data->{$_} = 0 unless $self->{user}{$_};
        }

        $sql
            = "INSERT INTO nt_perm("
            . join( ',', 'nt_group_id', 'nt_user_id', @permcols )
            . ") VALUES("
            . join( ',', 0, $insertid, map( $dbh->quote( $data->{$_} ), @permcols ) )
            . ')';

        $self->exec_query($sql) or do {
            $error{error_code} = 600;
            $error{error_msg}  = $dbh->errstr;
        };
    }

    $self->log_user( $data, 'added' );

    return \%error;
}

sub edit_user {
    my ( $self, $data ) = @_;

    my $dbh = $self->{dbh};
    my %error = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my @columns = grep { exists $data->{$_} }
        qw/ nt_group_id first_name last_name username email /;

    # only update the password when defined
    if (exists $data->{password} && $data->{password} ne '') {
        push @columns, 'password', 'pass_salt';
        $data->{pass_salt} = $self->_get_salt();
        $data->{password} = $self->get_pbkdf2_hash($data->{password}, $data->{pass_salt});
    }

    my ( $sql, $action );

    my $prev_data = $self->get_user( { nt_user_id => $data->{nt_user_id} } );
    return $prev_data if $self->is_error_response($prev_data);

    if (@columns) {
        $sql
            = "UPDATE nt_user SET "
            . join( ',', map( "$_ = " . $dbh->quote( $data->{$_} ), @columns ) )
            . " WHERE nt_user_id = ?";
        $action = 'modified';
        if ( $self->exec_query( $sql, $data->{nt_user_id} ) ) {
            $error{nt_user_id} = $data->{nt_user_id};
        }
        else {
            $error{error_code} = 600;
            $error{error_msg}  = $dbh->errstr;
        }
    }

    #XXX may want to let this happen ?
    #prevent user from modifying their own permissions (since all they could do is remove perms)
    if ( $data->{nt_user_id} eq $self->{user}{nt_user_id} ) {
        delete @$data{ $self->perm_fields, 'usable_nameservers' };
    }

    #permissions are independent from other user-data,
    #so we will not rollback if something goes wrong now

    #perms the current user doesn't have.
    my %nonperm
        = map { $_ => 1 } grep { !$data->{user}{$_} } $self->perm_fields;
    my @permcols = grep { exists $data->{$_} && $data->{user}{$_} }
        $self->perm_fields;

    if ( !$prev_data->{inherit_group_permissions} ) {

        #the user has some explicit permissions
        if ( $data->{inherit_group_permissions} ) {

            # make sure moving from explicit perms to inherited perms doesn't
            # restrict a permission that the executing user doesn't have the right to modify
            $sql
                = "SELECT nt_perm.*,nt_user.nt_group_id as group_id"
                . " FROM nt_perm"
                . " INNER JOIN nt_user ON nt_perm.nt_group_id = nt_user.nt_group_id"
                . " AND nt_user.nt_user_id = ?";
            my $perms = $self->exec_query( $sql, $data->{nt_user_id} )
                or return $self->error_response( 505, $dbh->errstr );

            if ( my $group = $perms->[0] ) {
                foreach my $k ( keys %nonperm ) {
                    return $self->error_response( 404,
                        "You do not have permission to restrict the $k permission of that user."
                    ) if !$group->{$k} && $prev_data->{$k};
                }

                #things are good, we will now delete the user perms and perms will then be
                # inherited automatically.
                $sql = "DELETE FROM nt_perm WHERE nt_user_id = " . $data->{nt_user_id};
            }
            else {

                #this would be bad
                return $self->error_response( 507,
                    "No group permissions were found (!!) for the user's group: USER : $data->{nt_user_id} (YOUR DB HAS A PROBLEM)"
                );
            }
        }
        else {

            #ok, update the user perms which are allowed
            if ( @permcols ) {
                $sql = "UPDATE nt_perm SET "
                    . join( ',', map( "$_ = " . $dbh->quote( $data->{$_} ), @permcols ) )
                    . " WHERE nt_user_id = " . $data->{nt_user_id};
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
                $error{error_code} = 600;
                $error{error_msg}  = $dbh->errstr;
            }
        }
    }
    elsif ( !$data->{inherit_group_permissions} && ( @permcols ) ) {

        #no preexisting permissions. insert into db
        $sql
            = "INSERT INTO nt_perm("
            . join( ',', 'nt_group_id', 'nt_user_id', @permcols )
            . ") VALUES("
            . join( ',', 0, $data->{nt_user_id},
            map( $dbh->quote( $data->{$_} ), @permcols ),)
            . ")";

        warn "$sql\n" if $self->debug_sql;

        if ( $dbh->do($sql) ) {
            $action = 'modified';
        }
        else {
            $error{error_code} = 600;
            $error{error_msg}  = $dbh->errstr;
        }
    }
    else {

        # perms are inherited and inherit_group_permissions is 1: do nothing
    }

    $data->{nt_group_id} = $prev_data->{nt_group_id} unless $data->{nt_group_id};
    if ($action) {
        $self->log_user( $data, $action, $prev_data );
    }

    return \%error;
}

sub delete_users {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK' );

    my %groups = map { $_, 1 } (
        $data->{user}{nt_group_id},
        @{ $self->get_subgroup_ids( $data->{user}{nt_group_id} ) }
    );

    my @userlist = split( ',', $data->{user_list} );
    my $sql      = "SELECT * FROM nt_user WHERE nt_user_id IN(??)";
    my $users    = $self->exec_query( $sql, [@userlist] )
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

    foreach my $user (@$users) {
        next unless ( $groups{ $user->{nt_group_id} } );

        $sql = "UPDATE nt_user SET deleted=1 WHERE nt_user_id = ?";
        $self->exec_query( $sql, $user->{nt_user_id} ) or next;

        my %user = ( %$user, user => $data->{user} );
        $self->log_user( \%user, 'deleted', $user );
    }

    return \%rv;
}

sub get_group_users {
    my ( $self, $data ) = @_;

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

    $field_map{group_name}
        = { timefield => 0, quicksearch => 0, field => 'nt_group.name' }
        if $data->{include_subgroups};

    my $conditions = $self->format_search_conditions( $data, \%field_map );
    my $sortby = $self->format_sort_conditions( $data, \%field_map,
        "nt_user.username" );

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

    my $sql = "SELECT COUNT(*) AS count FROM nt_user
    INNER JOIN nt_group ON nt_user.nt_group_id = nt_group.nt_group_id
    WHERE nt_user.deleted=0
      AND nt_user.nt_group_id IN("
        . join( ',', @group_list ) . ")"
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $c = $self->exec_query($sql)
        or return $self->error_response( 600, $self->{dbh}->errstr );

    $r_data->{total} = $c->[0]->{count};

    $self->set_paging_vars( $data, $r_data );

    return $r_data if $r_data->{total} == 0;

    $sql = "SELECT nt_user.nt_user_id,
               nt_user.username,
               nt_user.first_name,
               nt_user.last_name,
               nt_user.email,
               nt_user.nt_group_id,
               nt_group.name as group_name
        FROM nt_user
        INNER JOIN nt_group ON nt_user.nt_group_id = nt_group.nt_group_id
        WHERE nt_user.deleted=0
        AND nt_group.nt_group_id IN("
        . join( ',', @group_list ) . ") ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{start} - 1 ) . ", $r_data->{limit}";

    my $group_users = $self->exec_query($sql);
    if ($group_users) {
        my %groups;
        foreach my $u (@$group_users) {
            push( @{ $r_data->{list} }, $u );
            $groups{ $u->{nt_group_id} } = 1;
        }

        $r_data->{group_map} = $self->get_group_map( $data->{nt_group_id},
            [ keys %groups ] );
    }
    else {
        $r_data->{error_code} = '600';
        $r_data->{error_msg}  = $self->{dbh}->errstr;
    }

    return $r_data;
}

sub move_users {
    my ( $self, $data ) = @_;

    my %groups = map { $_, 1 } (
        $data->{user}{nt_group_id},
        @{ $self->get_subgroup_ids( $data->{user}{nt_group_id} ) }
    );

    my $new_group
        = $self->NicToolServer::Group::find_group( $data->{nt_group_id} );

    my $sql = "SELECT nt_user.*, nt_group.name as old_group_name
        FROM nt_user, nt_group
        WHERE nt_user.nt_group_id = nt_group.nt_group_id AND nt_user_id IN("
        . $data->{user_list} . ")";
    my $users = $self->exec_query($sql)
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

    foreach my $row (@$users) {
        next unless ( $groups{ $row->{nt_group_id} } );

        $sql = "UPDATE nt_user SET nt_group_id = ? WHERE nt_user_id = ?";
        $self->exec_query( $sql,
            [ $data->{nt_group_id}, $row->{nt_user_id} ] )
            or next;

        my %user = ( %$row, user => $data->{user} );
        $user{nt_group_id} = $data->{nt_group_id};
        $user{group_name}  = $new_group->{name};

        $self->log_user( \%user, 'moved', $row );
    }

    return {
        'error_code' => 200,
        'error_msg'  => 'OK',
    };
}

sub get_user_list {
    my ( $self, $data ) = @_;

    my %rv = ( 'error_code' => 200, 'error_msg' => 'OK', list => [] );

    my %groups = map { $_, 1 } (
        $data->{user}{nt_group_id},
        @{ $self->get_subgroup_ids( $data->{user}{nt_group_id} ) }
    );

    my $sql
        = "SELECT * FROM nt_user WHERE deleted=0 AND nt_user_id IN("
        . $data->{user_list}
        . ") ORDER BY username";

    my $users = $self->exec_query($sql)
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

    foreach my $row (@$users) {
        next unless ( $groups{ $row->{nt_group_id} } );
        $row->{password} = '' if exists $row->{password};
        push( @{ $rv{list} }, $row );
    }

    return \%rv;
}

sub get_user_global_log {
    my ( $self, $data ) = @_;

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

    my $dbh = $self->{dbh};

    my $sql = "SELECT COUNT(*) AS count FROM nt_user_global_log, nt_user
    WHERE nt_user_global_log.nt_user_id = nt_user.nt_user_id
        AND nt_user.nt_user_id = "
        . $dbh->quote( $data->{nt_user_id} ) . " "
        . ( @$conditions ? ' AND (' . join( ' ', @$conditions ) . ') ' : '' );

    my $c = $self->exec_query($sql);
    $r_data->{total} = $c->[0]->{count};

    $self->set_paging_vars( $data, $r_data );

    if ( $r_data->{total} == 0 ) {
        return $r_data;
    }

    $sql = "SELECT nt_user_global_log.* FROM nt_user_global_log, nt_user
        WHERE nt_user_global_log.nt_user_id = nt_user.nt_user_id AND nt_user.nt_user_id = "
        . $dbh->quote( $data->{nt_user_id} ) . " ";
    $sql .= 'AND (' . join( ' ', @$conditions ) . ') ' if @$conditions;
    $sql .= "ORDER BY " . join( ', ', @$sortby ) . " " if (@$sortby);
    $sql .= "LIMIT " . ( $r_data->{start} - 1 ) . ", $r_data->{limit}";

    my $r = $self->exec_query($sql);
    if ($r) {
        foreach my $row (@$r) {
            push( @{ $r_data->{list} }, $row );
        }
    }
    else {
        $r_data->{error_code} = '600';
        $r_data->{error_msg}  = $self->{dbh}->errstr;
    }

    return $r_data;
}

sub log_user {
    my ( $self, $data, $action, $prev_data ) = @_;

    my $dbh = $self->{dbh};
    my @columns = qw/ nt_group_id nt_user_id action timestamp modified_user_id
        first_name last_name username email password /;

    my $user = $data->{user};
    $data->{modified_user_id} ||= $data->{nt_user_id};
    $data->{nt_user_id} = $prev_data->{nt_user_id} = $user->{nt_user_id};
    $data->{action}    = $action;
    $data->{timestamp} = time();

    my $sql
        = "INSERT INTO nt_user_log("
        . join( ',', @columns )
        . ") VALUES("
        . join( ',', map( $dbh->quote( $data->{$_} ), @columns ) ) . ")";

    warn "$sql\n" if $self->debug_logs;
    my $insertid = $self->exec_query($sql);

    my @g_columns
        = qw(nt_user_id timestamp action object object_id log_entry_id title description);

    $data->{object}       = 'user';
    $data->{log_entry_id} = $insertid;
    $data->{title} = $data->{username}
        || $prev_data->{username}
        || $self->get_title( 'user', $prev_data->{nt_user_id} );
    $data->{object_id} = $data->{modified_user_id};

    if ( $action eq 'modified' ) {
        $data->{description} = $self->diff_changes( $data, $prev_data );
    }
    elsif ( $action eq 'deleted' ) {
        $data->{description} = 'deleted user';
    }
    elsif ( $action eq 'added' ) {
        $data->{description} = 'initial user creation';
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

    warn "$sql\n" if $self->debug_logs;
    $self->exec_query($sql);
}

sub valid_password {
    my ($self, $attempt, $db_pass, $user, $salt) = @_;

    # Check for PBKDF2 password
    if ( $salt ) {
        my $hashed = $self->get_pbkdf2_hash($attempt, $salt);
        return 1 if $hashed eq $db_pass;
    };

    # Check for HMAC SHA-1 password
    if ( $db_pass =~ /[0-9a-f]{40}/ ) {        # DB has HMAC SHA-1 hash
        my $hashed = $self->get_sha1_hash($attempt, $user);
        return 1 if $hashed eq $db_pass;
    }

    # Check for Plain password
    return 1 if ( ! $salt && $attempt eq $db_pass );   # plain password

    # If LDAP is defined - check for LDAP based user
    if ( $NicToolServer::ldap_servers ) {
        return 1 if ( $self->verify_ldap_user( $user, $attempt ));
    }

    return 0;   # No match
};

sub select_user {
    my ( $self, $uid ) = @_;

    my $users = $self->exec_query(
        "SELECT * FROM nt_user WHERE nt_user_id = ?", $uid )
        or return {
        error_code => 600,
        error_msg  => $self->{dbh}->errstr,
        };

    return (undef, $users->[0] || {});
}

sub _select_user_perm {
    my ($self, $uid) = @_;

    my $r = $self->exec_query(
    "SELECT " . $self->perm_fields_select . " FROM nt_perm
     WHERE deleted=0
       AND nt_user_id = ?", $uid )
        or return $self->error_response( 505, $self->{dbh}->errstr );
    return (undef, $r->[0]);
};

sub _select_group_perm {
    my ($self, $uid) = @_;

    my $r = $self->exec_query(
    "SELECT " . $self->perm_fields_select . " FROM nt_perm
     INNER JOIN nt_user ON nt_perm.nt_group_id = nt_user.nt_group_id
       WHERE ( nt_perm.deleted=0
        AND nt_user.deleted=0
        AND nt_user.nt_user_id = ?)", $uid )
    or return $self->error_response( 505, $self->{dbh}->errstr );

    return (undef, $r->[0]);
};

sub get_sha1_hash {
    my ($self, $pass, $user) = @_;
    return Crypt::Mac::HMAC::hmac_hex( 'SHA1', lc $user, $pass);
    # RCC - use hmac to store the password using the username as a key
    #use Digest::HMAC_SHA1;
    #return Digest::HMAC_SHA1::hmac_sha1_hex( $pass, lc($user) );
};

sub get_pbkdf2_hash {
    my ($self, $pass, $salt) = @_;
    $salt ||= $self->_get_salt();
    return unpack("H*", Crypt::KeyDerivation::pbkdf2($pass, $salt, 5000, 'SHA512'));
}

sub _get_salt {
    my $self = shift;
    my $length = shift || 16;
    my $chars = join('', map chr, 40..126); # ASCII 40-126
    my $salt;
    for ( 0..($length-1) ) {
        $salt .= substr($chars, rand((length $chars) - 1),1);
    };
    return $salt;
}

sub verify_ldap_user {
    my ( $self, $user, $attempt ) = @_;

    return 0 unless $attempt;

    eval "require Net::LDAP" or do {
        warn 'LDAP: could not load Net::LDAP module. Skipping LDAP authentication step';
        return 0;
    };

    my $user_dn = '';
    my @servers = split(',', $NicToolServer::ldap_servers );
    my $base_dn = $NicToolServer::ldap_basedn || '';
    my $starttls_required = $NicToolServer::ldap_starttls || 0;
    my $user_mapping = $NicToolServer::ldap_user_mapping || 'uid';

    # If filter is set, search for user, else attempt direct bind
    if ( $NicToolServer::ldap_filter ) {

        # search for user
        $user_dn = $self->locate_ldap_user( $user );
        return 0 if ( $user_dn eq '' );  # Locating user failed. Return failed attempt

    } else {

        # try to bind directly as the user using the base_dn for base and $user_mapping as relative
        $user_dn = sprintf( '%s=%s,%s', $user_mapping, $user, $base_dn );
    }

    # Check $attempt
    my $ldap = Net::LDAP->new(@servers, version => 3);
    unless ( $ldap ) {
        warn 'LDAP: Error in Net::LDAP.' if $self->debug_auth;
        return 0;
    }

    # Initiate starttls if set
    if ( $starttls_required ) {
        my $starttls_reply = $ldap->start_tls();
        if ( $starttls_reply->is_error && $self->debug_auth ) {
            warn "LDAP: server does not accept starttls: " . $starttls_reply->error;
        }
    }

    # Attempt to authenticate user
    my $ldap_result = $ldap->bind( $user_dn, password => $attempt );
    $ldap->unbind();

    return 1 if ( $ldap_result->code == 0 );
    return 0;
};

sub locate_ldap_user {
    my ( $self, $user ) = @_;

    my $user_dn = '';
    my @servers = split(',', $NicToolServer::ldap_servers );
    my $bind_dn = $NicToolServer::ldap_binddn;
    my $bind_dn_password = $NicToolServer::ldap_bindpw || '';
    my $base_dn = $NicToolServer::ldap_basedn || '';
    my $filter = $NicToolServer::ldap_filter || '';
    my $starttls_required = $NicToolServer::ldap_starttls || 0;
    my $user_mapping = $NicToolServer::ldap_user_mapping || 'uid';
    return '' unless ( @servers );

    my $ldap = Net::LDAP->new(@servers, version => 3);
    unless ( $ldap ) {
        warn 'LDAP: Error in Net::LDAP.' if $self->debug_auth;
        return '';
    }

    # Initiate starttls if set
    if ( $starttls_required ) {
        my $starttls_reply = $ldap->start_tls();
        if ( $starttls_reply->is_error && $self->debug_auth ) {
            warn "LDAP: server does not accept starttls: " . $starttls_reply->error;
        }
    }

    my $ldap_result;
    if ( $bind_dn ) {
        $ldap_result = $ldap->bind( $bind_dn, password => $bind_dn_password );
    } else {
        $ldap_result = $ldap->bind; # Anonymous bind
    }
    if ( $ldap_result->code ) {
        warn 'LDAP: cannot bind: ' . $ldap_result->error if $self->debug_auth;
        return '';
    }

    # Search for user
    # Update filter to be more specific, in order to avoid returning too many users.
    $filter = "(&(" . $user_mapping . "=" . $user . ")". $filter . ")";
    # warn "LDAP: updated filter " . $filter . "\n";
    my $ldap_result = $ldap->search( base => $base_dn,
                                     scope => 'sub',
                                     attrs => [ $user_mapping ],
                                     filter => $filter );
    if ( $ldap_result->code ) {
        warn 'LDAP: search failed: ' . $ldap_result->error if $self->debug_auth;
        return '';
    }

    # Check if user exists in filtered LDAP results and get his DN
    foreach my $entry ($ldap_result->entries) {
        if ( $entry->get_value($user_mapping) eq $user ) {
            $user_dn = $entry->dn();
            last;
        }
    }

    $ldap->unbind();
    return $user_dn;
};

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::User - NicTool user management

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
