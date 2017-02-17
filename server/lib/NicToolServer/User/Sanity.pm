package NicToolServer::User::Sanity;
# ABSTRACT: sanity tests for nictool users

use strict;

use parent 'NicToolServer::User';

### public methods
sub new_user {
    my ( $self, $data ) = @_;

    $self->error( 'nt_group_id', 'Cannot add user to a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{nt_group_id} );

    $self->_valid_username($data);
    $self->_valid_email($data);
    $self->_valid_password($data);

    return $self->throw_sanity_error if $self->{errors};
    $self->SUPER::new_user($data);
}

sub edit_user {
    my ( $self, $data ) = @_;

    $self->error( 'nt_user_id', 'Cannot edit deleted user!' )
        if $self->check_object_deleted( 'user', $data->{nt_user_id} );

    my $dataobj = $self->get_user($data);
    return $dataobj if $self->is_error_response($dataobj);

    $self->error( 'nt_user_id', 'Cannot edit user in a deleted group!' )
        if $self->check_object_deleted( 'group', $dataobj->{nt_group_id} );

    $self->_valid_email($data)    if exists $data->{email};
    $self->_valid_username($data) if exists $data->{username};

    if ( exists $data->{password} && $data->{password} ne '' ) {

        if ( ! $data->{user}{is_admin} ) {  # logged in user (not form user)
            if (! exists $data->{current_password} ) {
                $self->error('current_password', "Current password is required.");
            }
            elsif ( $self->valid_password(
                    $data->{current_password},
                    $dataobj->{password},
                    $dataobj->{username},
                    $dataobj->{pass_salt})) {
                $self->error('current_password', "Current password is incorrect.");
            }
        };

        $self->_valid_password($data);
    }

    return $self->throw_sanity_error if $self->{errors};
    $self->SUPER::edit_user($data);
}

sub move_users {
    my ( $self, $data ) = @_;
    my $me = 0;
    foreach ( split( /,/, $data->{user_list} ) ) {
        $me = 1 if $_ eq $self->{user}{nt_user_id};
    }
    $self->error( 'user_list', 'Cannot move yourself to another group!' )
        if $me;

    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::move_users($data);
}

sub get_user_list {
    my ( $self, $data ) = @_;
    $self->error( 'user_list', 'user_list cannot be empty' )
        if $data->{user_list} eq '';

    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::get_user_list($data);
}

sub get_group_users {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(username first_name last_name email) );
    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::get_group_users($data);
}

sub get_user_global_log {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(timestamp title action object description) );
    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::get_user_global_log($data);
}

### private methods
sub _username_exists {
    my ( $self, $data ) = @_;

    my ( $sql, $groups );

    if ( exists $data->{nt_user_id} ) {
        $sql = "SELECT name FROM nt_group
        INNER JOIN nt_user ON nt_user.nt_group_id=nt_group.nt_group_id
          WHERE nt_user.nt_user_id = ?";
        $groups = $self->exec_query( $sql, $data->{nt_user_id} );
    }
    else {
        $sql = "SELECT name FROM nt_group WHERE nt_group_id = ?";
        $groups = $self->exec_query( $sql, $data->{nt_group_id} );
    }

    $data->{groupname} = $groups->[0]{name};

    $sql = "SELECT nt_group_id FROM nt_group WHERE name = ? AND deleted=0";
    $groups = $self->exec_query( $sql, $groups->[0]{name} );

    my @groups;
    foreach my $row (@$groups) {
        push( @groups, $row->{nt_group_id} );
    }

    return 0 if ! scalar @groups;
    if ( $data->{nt_user_id} ) {
        $sql
            = "SELECT nt_user_id FROM nt_user WHERE deleted=0 AND nt_group_id IN ("
            . join( ',', @groups )
            . ") AND nt_user_id != $data->{nt_user_id} AND username=?";
    }
    else {
        $sql
            = "SELECT nt_user_id FROM nt_user WHERE deleted=0 AND nt_group_id IN ("
            . join( ',', @groups )
            . ") AND username=?";
    }

    my $users = $self->exec_query( $sql, $data->{username} );

    return ref( $users->[0] ) ? 1 : 0;
}

sub _valid_username {
    my ( $self, $data ) = @_;

    my $username = $data->{username};

    if ( length($username) < 3 ) {
        $self->error( 'username', "Username must be at least 3 characters." );
    }

    if ( length($username) > 50 ) {
        $self->error( 'username', "Username cannot exceed 50 characters." );
    }

    if ( $username =~ /([^a-zA-Z0-9 \-\_\.])/ ) {
        $self->error( 'username',
            "Username contains an invalid character - \"$1\". Only A-Z, 0-9, _, -, . and [space] are allowed."
        );
    }

    if ( $self->_username_exists($data) ) {
        $self->error( 'username',
            "Username $data->{username}\@$data->{groupname} is not unique. Please choose a different username or put the user in a different group."
        );
    }
}

sub _valid_email {
    my ( $self, $data ) = @_;

    if ( $data->{email} !~ /^[^@]+@[^@.]+\..+$/ ) {
        $self->error( 'email', "Email must be a valid email address.");
    }
}

sub _valid_password {
    my ( $self, $data ) = @_;

    if ( length( $data->{password} ) < 8 ) {
        $self->error( 'password',
            "Password too short, must be 8-30 characters long."
        );
    }

    if ( length( $data->{password} ) > 30 ) {
        $self->error( 'password',
            "Password too long, must be 8-30 characters long."
        );
    }

    my $username = $data->{username};
    if ( !$username ) {
        $self->error( 'password',
            "Internal error. Missing username in password update request."
        );
    }
    else {
        if ( $data->{password} eq $username ) {
            $self->error( 'password',
                "Password cannot be the same as username!"
            );
        }

        if ( $data->{password} =~ m/$username/ ) {
            $self->error( 'password',
                "Password cannot contain your username!"
            );
        }
    }

    if ( $data->{password} ne $data->{password2} ) {
        $self->{errors}{password} = $self->{errors}{password2} = 1;
        push( @{ $self->{error_messages} }, 'Passwords must match.' );
    }
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::User::Sanity - sanity tests for nictool users

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
