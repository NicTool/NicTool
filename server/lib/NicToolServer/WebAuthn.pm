package NicToolServer::WebAuthn;

# ABSTRACT: WebAuthn/passkey credential management for NicTool

use strict;
use warnings;

use Authen::WebAuthn;
use JSON;
use MIME::Base64 qw(encode_base64url decode_base64url);

@NicToolServer::WebAuthn::ISA = 'NicToolServer';

my $CHALLENGE_EXPIRY_SECONDS = 300;    # 5 minutes

sub generate_registration_options {
    my ( $self, $data ) = @_;
    return $self->_disabled_error() if !$self->_is_enabled();

    my $uid = $data->{nt_user_id}
        or return $self->error_response( 301, 'nt_user_id required' );

    my $rp_id  = $self->_get_rp_id();
    my $origin = $self->_get_origin();
    return $self->error_response( 600,
        'WebAuthn not configured: set webauthn_rp_id and ' . 'webauthn_origin in nt_options' )
        if !$rp_id || !$origin;

    my $user = $self->_get_webauthn_user($uid)
        or return $self->error_response( 404, 'User not found' );

    $self->_cleanup_expired_challenges();

    my $challenge = $self->_generate_challenge();
    my $now       = time();

    $self->exec_query(
        'INSERT INTO nt_user_webauthn_challenge
            (nt_user_id, challenge, ceremony_type, created_at, expires_at)
            VALUES (??)',
        [ $uid, $challenge, 'registration', $now, $now + $CHALLENGE_EXPIRY_SECONDS ]
    );

    my $exclude = $self->_get_active_credential_ids($uid);

    my @exclude_creds;
    for my $cred (@$exclude) {
        push @exclude_creds,
            {
            type => 'public-key',
            id   => $cred->{credential_id},
            };
    }

    my $user_handle = encode_base64url( pack( 'N', $uid ), '' );

    return {
        error_code => 200,
        error_msg  => 'OK',
        options    => encode_json(
            {   challenge => $challenge,
                rp        => {
                    name => 'NicTool',
                    id   => $rp_id,
                },
                user => {
                    id          => $user_handle,
                    name        => $user->{username},
                    displayName =>
                        join( ' ', grep {$_} ( $user->{first_name}, $user->{last_name} ) )
                        || $user->{username},
                },
                pubKeyCredParams => [
                    { type => 'public-key', alg => -7 },      # ES256
                    { type => 'public-key', alg => -257 },    # RS256
                ],
                timeout                => 60000,
                attestation            => 'none',
                excludeCredentials     => \@exclude_creds,
                authenticatorSelection => {
                    residentKey      => 'preferred',
                    userVerification => 'preferred',
                },
            }
        ),
    };
}

sub verify_registration {
    my ( $self, $data ) = @_;
    return $self->_disabled_error() if !$self->_is_enabled();

    my $uid = $data->{nt_user_id}
        or return $self->error_response( 301, 'nt_user_id required' );

    my $rp_id  = $self->_get_rp_id();
    my $origin = $self->_get_origin();
    return $self->error_response( 600, 'WebAuthn not configured' )
        if !$rp_id || !$origin;

    for my $f (qw(challenge_b64 client_data_json_b64 attestation_object_b64)) {
        return $self->error_response( 301, "$f required" )
            if !$data->{$f};
    }

    my $challenge_row = $self->_consume_challenge( $data->{challenge_b64}, 'registration', $uid );
    return $self->error_response( 403, 'Invalid or expired challenge' )
        if !$challenge_row;

    my $webauthn = Authen::WebAuthn->new(
        rp_id  => $rp_id,
        origin => $origin,
    );

    my $result;
    eval {
        $result = $webauthn->validate_registration(
            challenge_b64          => $data->{challenge_b64},
            requested_uv           => 'preferred',
            client_data_json_b64   => $data->{client_data_json_b64},
            attestation_object_b64 => $data->{attestation_object_b64},
        );
    };
    if ($@) {
        warn "WebAuthn registration verification failed: $@";
        return $self->error_response( 403, 'Registration verification failed' );
    }

    my $now = time();
    $self->exec_query(
        'INSERT INTO nt_user_webauthn_credential
            (nt_user_id, credential_id, credential_pubkey,
             signature_count, friendly_name, transports,
             created_at)
            VALUES (??)',
        [   $uid, $result->{credential_id},
            $result->{credential_pubkey}, $result->{signature_count} || 0,
            $data->{friendly_name} || undef, $data->{transports} || undef,
            $now,
        ]
    );

    return {
        error_code    => 200,
        error_msg     => 'OK',
        credential_id => $result->{credential_id},
    };
}

sub get_user_credentials {
    my ( $self, $data ) = @_;
    return $self->_disabled_error() if !$self->_is_enabled();

    my $uid = $data->{nt_user_id}
        or return $self->error_response( 301, 'nt_user_id required' );

    my $rows = $self->exec_query(
        'SELECT nt_webauthn_credential_id, credential_id,
                friendly_name, transports, created_at,
                last_used_at, revoked
           FROM nt_user_webauthn_credential
          WHERE nt_user_id = ? AND revoked = 0',
        $uid
    );

    return {
        error_code  => 200,
        error_msg   => 'OK',
        credentials => $rows || [],
    };
}

sub revoke_credential {
    my ( $self, $data ) = @_;
    return $self->_disabled_error() if !$self->_is_enabled();

    my $uid = $data->{nt_user_id}
        or return $self->error_response( 301, 'nt_user_id required' );
    my $cred_id = $data->{nt_webauthn_credential_id}
        or return $self->error_response( 301, 'nt_webauthn_credential_id required' );

    $self->exec_query(
        'UPDATE nt_user_webauthn_credential
            SET revoked = 1
          WHERE nt_webauthn_credential_id = ?
            AND nt_user_id = ?',
        [ $cred_id, $uid ]
    );

    return { error_code => 200, error_msg => 'OK' };
}

sub rename_credential {
    my ( $self, $data ) = @_;
    return $self->_disabled_error() if !$self->_is_enabled();

    my $uid = $data->{nt_user_id}
        or return $self->error_response( 301, 'nt_user_id required' );
    my $cred_id = $data->{nt_webauthn_credential_id}
        or return $self->error_response( 301, 'nt_webauthn_credential_id required' );

    return $self->error_response( 301, 'friendly_name required' )
        if !defined $data->{friendly_name};

    $self->exec_query(
        'UPDATE nt_user_webauthn_credential
            SET friendly_name = ?
          WHERE nt_webauthn_credential_id = ?
            AND nt_user_id = ?',
        [ $data->{friendly_name}, $cred_id, $uid ]
    );

    return { error_code => 200, error_msg => 'OK' };
}

sub generate_authentication_options {
    my ( $self, $data ) = @_;
    return $self->_disabled_error() if !$self->_is_enabled();

    my $rp_id  = $self->_get_rp_id();
    my $origin = $self->_get_origin();
    return $self->error_response( 600, 'WebAuthn not configured' )
        if !$rp_id || !$origin;

    $self->_cleanup_expired_challenges();

    my $username = $data->{username};
    my ( $uid, @allow );

    if ($username) {
        my $auth_error = 'Authentication failed.';
        my $users      = $self->exec_query(
            'SELECT nt_user_id FROM nt_user
              WHERE username = ? AND deleted = 0',
            $username
        );
        return $self->error_response( 403, $auth_error )
            if !$users || !$users->[0];

        $uid = $users->[0]{nt_user_id};
        my $creds = $self->_get_active_credential_ids($uid);

        return $self->error_response( 403, $auth_error )
            if !@$creds;

        for my $c (@$creds) {
            my $entry = {
                type => 'public-key',
                id   => $c->{credential_id},
            };
            if ( $c->{transports} ) {
                $entry->{transports} =
                    [ split /,/, $c->{transports} ];
            }
            push @allow, $entry;
        }
    }

    # Usernameless flow: uid is undef, allowCredentials is empty
    # — the browser shows its resident credential picker

    my $challenge = $self->_generate_challenge();
    my $now       = time();

    $self->exec_query(
        'INSERT INTO nt_user_webauthn_challenge
            (nt_user_id, challenge, ceremony_type,
             created_at, expires_at)
            VALUES (??)',
        [ $uid, $challenge, 'authentication', $now, $now + $CHALLENGE_EXPIRY_SECONDS ]
    );

    return {
        error_code => 200,
        error_msg  => 'OK',
        options    => encode_json(
            {   challenge        => $challenge,
                rpId             => $rp_id,
                timeout          => 60000,
                allowCredentials => \@allow,
                userVerification => 'preferred',
            }
        ),
    };
}

sub verify_authentication {
    my ( $self, $data ) = @_;
    return $self->_disabled_error() if !$self->_is_enabled();

    my $rp_id  = $self->_get_rp_id();
    my $origin = $self->_get_origin();
    return $self->error_response( 600, 'WebAuthn not configured' )
        if !$rp_id || !$origin;

    for my $f (
        qw(challenge_b64 credential_id_b64 client_data_json_b64
        authenticator_data_b64 signature_b64)
        )
    {
        return $self->error_response( 301, "$f required" )
            if !$data->{$f};
    }

    # Look up the credential
    my $creds = $self->exec_query(
        'SELECT c.*, u.nt_user_id, u.username
           FROM nt_user_webauthn_credential c
           JOIN nt_user u ON c.nt_user_id = u.nt_user_id
          WHERE c.credential_id = ?
            AND c.revoked = 0
            AND u.deleted = 0',
        $data->{credential_id_b64}
    );
    return $self->error_response( 403, 'Authentication failed.' )
        if !$creds || !$creds->[0];

    my $cred = $creds->[0];

    # Validate userHandle matches credential owner (required for
    # usernameless/discoverable credential flow)
    if ( defined $data->{user_handle_b64} && length $data->{user_handle_b64} ) {
        my $claimed_uid = eval { unpack( 'N', decode_base64url( $data->{user_handle_b64} ) ) };
        return $self->error_response( 403, 'Authentication failed.' )
            if !defined $claimed_uid || $claimed_uid != $cred->{nt_user_id};
    }

    # Try usernameless flow first (challenge stored with NULL uid),
    # then fall back to user-bound challenge (username was provided)
    my $challenge_row =
        $self->_consume_challenge( $data->{challenge_b64}, 'authentication', undef );
    if ( !$challenge_row ) {
        $challenge_row = $self->_consume_challenge( $data->{challenge_b64},
            'authentication', $cred->{nt_user_id} );
    }
    return $self->error_response( 403, 'Invalid or expired challenge' )
        if !$challenge_row;

    my $webauthn = Authen::WebAuthn->new(
        rp_id  => $rp_id,
        origin => $origin,
    );

    my $result;
    eval {
        $result = $webauthn->validate_assertion(
            challenge_b64          => $data->{challenge_b64},
            credential_pubkey_b64  => $cred->{credential_pubkey},
            stored_sign_count      => $cred->{signature_count},
            requested_uv           => 'preferred',
            client_data_json_b64   => $data->{client_data_json_b64},
            authenticator_data_b64 => $data->{authenticator_data_b64},
            signature_b64          => $data->{signature_b64},
        );
    };
    if ($@) {
        warn "WebAuthn authentication verification failed: $@";
        return $self->error_response( 403, 'Authentication verification failed' );
    }

    my $now = time();
    $self->exec_query(
        'UPDATE nt_user_webauthn_credential
            SET signature_count = ?, last_used_at = ?
          WHERE nt_webauthn_credential_id = ?',
        [ $result->{signature_count}, $now, $cred->{nt_webauthn_credential_id} ]
    );

    return {
        error_code => 200,
        error_msg  => 'OK',
        nt_user_id => $cred->{nt_user_id},
        username   => $cred->{username},
    };
}

### internal helpers

sub _is_enabled {
    my ($self) = @_;
    my $val = $self->get_option('webauthn_enabled');
    return 0 if !defined $val;    # default: disabled
    return $val ? 1 : 0;
}

sub _disabled_error {
    my ($self) = @_;
    return $self->error_response( 600, 'WebAuthn is disabled by administrator' );
}

sub _get_rp_id {
    my $self = shift;
    return $self->get_option('webauthn_rp_id');
}

sub _get_origin {
    my $self = shift;
    return $self->get_option('webauthn_origin');
}

sub _generate_challenge {
    my $self = shift;

    if ( open my $fh, '<:raw', '/dev/urandom' ) {
        my $bytes = q{};
        my $read  = read( $fh, $bytes, 32 );
        close $fh;
        return encode_base64url( $bytes, '' )
            if defined $read && $read == 32;
    }

    die "Failed to read /dev/urandom for WebAuthn challenge\n";
}

sub _cleanup_expired_challenges {
    my $self = shift;

    $self->exec_query(
        'DELETE FROM nt_user_webauthn_challenge
          WHERE expires_at < ?',
        time()
    );
}

sub _consume_challenge {
    my ( $self, $challenge, $ceremony_type, $uid ) = @_;

    # Atomic UPDATE avoids TOCTOU race: two concurrent requests with the
    # same challenge cannot both succeed because only one UPDATE will
    # match consumed = 0.
    my ( $update_sql, $select_sql, @bind );
    if ( defined $uid ) {
        $update_sql = 'UPDATE nt_user_webauthn_challenge
            SET consumed = 1
          WHERE challenge = ?
            AND ceremony_type = ?
            AND nt_user_id = ?
            AND consumed = 0
            AND expires_at >= ?';
        $select_sql = 'SELECT * FROM nt_user_webauthn_challenge
          WHERE challenge = ?
            AND ceremony_type = ?
            AND nt_user_id = ?
            AND consumed = 1
          ORDER BY nt_webauthn_challenge_id DESC LIMIT 1';
        @bind = ( $challenge, $ceremony_type, $uid, time() );
    }
    else {
        $update_sql = 'UPDATE nt_user_webauthn_challenge
            SET consumed = 1
          WHERE challenge = ?
            AND ceremony_type = ?
            AND nt_user_id IS NULL
            AND consumed = 0
            AND expires_at >= ?';
        $select_sql = 'SELECT * FROM nt_user_webauthn_challenge
          WHERE challenge = ?
            AND ceremony_type = ?
            AND nt_user_id IS NULL
            AND consumed = 1
          ORDER BY nt_webauthn_challenge_id DESC LIMIT 1';
        @bind = ( $challenge, $ceremony_type, time() );
    }

    my $affected = $self->exec_query( $update_sql, \@bind );

    # exec_query returns arrayref for SELECT, but for UPDATE it returns
    # the DBI execute() result.  If no rows matched, the challenge was
    # already consumed, expired, or nonexistent.
    return if !$affected || $affected eq '0E0';

    # Fetch the row we just consumed (for caller to inspect)
    my @sel_bind =
        defined $uid
        ? ( $challenge, $ceremony_type, $uid )
        : ( $challenge, $ceremony_type );
    my $rows = $self->exec_query( $select_sql, \@sel_bind );
    return if !$rows || !$rows->[0];
    return $rows->[0];
}

sub _get_webauthn_user {
    my ( $self, $uid ) = @_;

    my $users = $self->exec_query(
        'SELECT nt_user_id, username, first_name, last_name
           FROM nt_user WHERE nt_user_id = ? AND deleted = 0',
        $uid
    );
    return if !$users || !$users->[0];
    return $users->[0];
}

sub _get_active_credential_ids {
    my ( $self, $uid ) = @_;

    return $self->exec_query(
        'SELECT credential_id, transports
           FROM nt_user_webauthn_credential
          WHERE nt_user_id = ? AND revoked = 0',
        $uid
    ) || [];
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::WebAuthn - WebAuthn/passkey credential management

=head1 VERSION

version 2.44

=head1 SYNOPSIS

Provides server-side WebAuthn registration and authentication
for NicTool passkey support.

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
