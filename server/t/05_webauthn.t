use strict;
use warnings;

use lib 't';
use NicToolTest;
use Test::More;
use JSON;
use MIME::Base64 qw(decode_base64url);

BEGIN {
    use_ok('NicToolServer');
    use_ok('NicToolServer::WebAuthn');
}

# -- DB setup (same pattern as 01_data.t) --

$NicToolServer::dsn     = Config('dsn');
$NicToolServer::db_user = Config('db_user');
$NicToolServer::db_pass = Config('db_pass');

my $dbh = NicToolServer->dbh();
ok( $dbh, 'dbh handle' ) or BAIL_OUT('no database connection');

my $wa = NicToolServer::WebAuthn->new( undef, undef, $dbh );
ok( $wa, 'WebAuthn instance' );

my $test_uid    = 1;              # root user, always exists
my $test_prefix = "test_wa_$$";

# Save and clear WebAuthn options for clean test state
my $orig_enabled = $wa->get_option('webauthn_enabled');
my $orig_rp_id   = $wa->get_option('webauthn_rp_id');
my $orig_origin  = $wa->get_option('webauthn_origin');

$wa->exec_query( 'DELETE FROM nt_options WHERE option_name = ?', 'webauthn_enabled' );
$wa->exec_query( 'DELETE FROM nt_options WHERE option_name = ?', 'webauthn_rp_id' );
$wa->exec_query( 'DELETE FROM nt_options WHERE option_name = ?', 'webauthn_origin' );

# =====================================================================
# T1: Unconfigured returns error 600
# =====================================================================
subtest 'T1: default disabled' => sub {

    # No webauthn_enabled row — default is disabled
    ok( !$wa->get_option('webauthn_enabled'), 'no webauthn_enabled row by default' );

    my $r1 = $wa->generate_registration_options( { nt_user_id => $test_uid } );
    is( $r1->{error_code}, 600, 'registration: disabled returns 600' );
    like( $r1->{error_msg}, qr/disabled/i, 'registration: message says disabled' );

    my $r2 = $wa->generate_authentication_options( {} );
    is( $r2->{error_code}, 600, 'auth: disabled returns 600' );

    my $r3 = $wa->get_user_credentials( { nt_user_id => $test_uid } );
    is( $r3->{error_code}, 600, 'list creds: disabled returns 600' );
};

# =====================================================================
# T1b: webauthn_enabled toggle
# =====================================================================
subtest 'T1b: enable toggle + unconfigured' => sub {

    # Enable, but rp_id/origin not yet set — should get "not configured"
    $wa->exec_query(
        'INSERT INTO nt_options (option_name, option_value) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE option_value = VALUES(option_value)',
        [ 'webauthn_enabled', '1' ] );

    my $r1 = $wa->generate_registration_options( { nt_user_id => $test_uid } );
    is( $r1->{error_code}, 600, 'enabled but unconfigured: returns 600' );
    like( $r1->{error_msg}, qr/not configured/i, 'enabled: message says unconfigured' );

    # Explicitly disable
    $wa->exec_query( 'UPDATE nt_options SET option_value = ? WHERE option_name = ?',
        [ '0', 'webauthn_enabled' ] );

    my $r2 = $wa->generate_registration_options( { nt_user_id => $test_uid } );
    is( $r2->{error_code}, 600, 'disabled: returns 600' );
    like( $r2->{error_msg}, qr/disabled/i, 'disabled: message says disabled' );

    # Re-enable for remaining tests
    $wa->exec_query( 'UPDATE nt_options SET option_value = ? WHERE option_name = ?',
        [ '1', 'webauthn_enabled' ] );
};

# Insert test options for remaining tests
my $test_rp_id  = 'localhost';
my $test_origin = 'https://localhost:8443';

$wa->exec_query( 'INSERT INTO nt_options (option_name, option_value) VALUES (?, ?)',
    [ 'webauthn_rp_id', $test_rp_id ] );
$wa->exec_query( 'INSERT INTO nt_options (option_name, option_value) VALUES (?, ?)',
    [ 'webauthn_origin', $test_origin ] );

# =====================================================================
# T2: Challenge generation
# =====================================================================
subtest 'T2: challenge generation' => sub {
    my $c = $wa->_generate_challenge();
    ok( defined $c,       'challenge is defined' );
    ok( length($c) >= 40, 'challenge >= 40 chars (32 bytes base64url)' );
    unlike( $c, qr/[+\/=]/, 'valid base64url (no +/= chars)' );

    my $decoded = decode_base64url($c);
    is( length($decoded), 32, 'decoded challenge is 32 bytes' );

    my %seen;
    my $all_unique = 1;
    for ( 1 .. 100 ) {
        my $ch = $wa->_generate_challenge();
        if ( $seen{$ch}++ ) { $all_unique = 0; last; }
    }
    ok( $all_unique, '100 challenges are all unique' );
};

# =====================================================================
# T3: Challenge lifecycle
# =====================================================================
subtest 'T3: challenge lifecycle' => sub {
    my $now = time();

    # Valid challenge — consume succeeds
    my $ch1 = "${test_prefix}_life1";
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_challenge
            (nt_user_id, challenge, ceremony_type,
             created_at, expires_at) VALUES (??)',
        [ $test_uid, $ch1, 'authentication', $now, $now + 300 ]
    );
    my $row = $wa->_consume_challenge( $ch1, 'authentication', $test_uid );
    ok( $row, 'valid challenge consumed' );
    is( $row->{challenge}, $ch1, 'returned row matches' );

    # Replay rejected
    ok( !$wa->_consume_challenge( $ch1, 'authentication', $test_uid ), 'replay rejected' );

    # Expired challenge
    my $ch2 = "${test_prefix}_expired";
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_challenge
            (nt_user_id, challenge, ceremony_type,
             created_at, expires_at) VALUES (??)',
        [ $test_uid, $ch2, 'authentication', $now - 600, $now - 300 ]
    );
    ok( !$wa->_consume_challenge( $ch2, 'authentication', $test_uid ),
        'expired challenge rejected' );

    # Wrong ceremony type
    my $ch3 = "${test_prefix}_wrongtype";
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_challenge
            (nt_user_id, challenge, ceremony_type,
             created_at, expires_at) VALUES (??)',
        [ $test_uid, $ch3, 'registration', $now, $now + 300 ]
    );
    ok( !$wa->_consume_challenge( $ch3, 'authentication', $test_uid ),
        'wrong ceremony type rejected' );

    # Wrong user ID
    my $ch4 = "${test_prefix}_wronguid";
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_challenge
            (nt_user_id, challenge, ceremony_type,
             created_at, expires_at) VALUES (??)',
        [ $test_uid, $ch4, 'authentication', $now, $now + 300 ]
    );
    ok( !$wa->_consume_challenge( $ch4, 'authentication', 99999 ), 'wrong user ID rejected' );

    # NULL user ID (usernameless flow)
    my $ch5 = "${test_prefix}_nulluid";
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_challenge
            (nt_user_id, challenge, ceremony_type,
             created_at, expires_at) VALUES (??)',
        [ undef, $ch5, 'authentication', $now, $now + 300 ]
    );
    my $null_row = $wa->_consume_challenge( $ch5, 'authentication', undef );
    ok( $null_row, 'NULL uid challenge consumed (usernameless)' );
    is( $null_row->{challenge}, $ch5, 'NULL uid row matches' );

    # Cleanup removes expired
    $wa->_cleanup_expired_challenges();
    my $remaining = $wa->exec_query(
        'SELECT COUNT(*) AS cnt
           FROM nt_user_webauthn_challenge
          WHERE challenge = ?', $ch2
    );
    is( $remaining->[0]{cnt}, 0, 'cleanup removed expired row' );
};

# =====================================================================
# T4: generate_registration_options
# =====================================================================
subtest 'T4: registration options' => sub {

    # Missing nt_user_id
    is( $wa->generate_registration_options( {} )->{error_code}, 301, 'missing uid returns 301' );

    # Nonexistent user
    is( $wa->generate_registration_options( { nt_user_id => 99999 } )->{error_code},
        404, 'nonexistent user returns 404' );

    # Valid call
    my $r = $wa->generate_registration_options( { nt_user_id => $test_uid } );
    is( $r->{error_code}, 200, 'valid call returns 200' );
    ok( $r->{options}, 'options field present' );

    my $opts = decode_json( $r->{options} );
    ok( $opts->{challenge}, 'has challenge' );
    is( $opts->{rp}{id}, $test_rp_id, 'correct rp.id' );
    ok( $opts->{user}{id},                        'has user.id' );
    ok( ref $opts->{pubKeyCredParams} eq 'ARRAY', 'pubKeyCredParams is array' );

    # user.id decodes to packed uid
    my $decoded_uid =
        unpack( 'N', decode_base64url( $opts->{user}{id} ) );
    is( $decoded_uid, $test_uid, 'user.id encodes uid' );
};

# =====================================================================
# T5: generate_authentication_options WITH username
# =====================================================================
subtest 'T5: auth options with username' => sub {

    # Nonexistent user
    is( $wa->generate_authentication_options( { username => 'nonexistent_xyzzy_999' } )
            ->{error_code},
        403,
        'nonexistent user returns 403'
    );

    # User with no credentials
    is( $wa->generate_authentication_options( { username => 'root' } )->{error_code},
        403, 'no credentials returns 403' );

    # Insert a test credential
    my $cred_id = "${test_prefix}_auth_cred";
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_credential
            (nt_user_id, credential_id, credential_pubkey,
             signature_count, friendly_name, transports,
             created_at) VALUES (??)',
        [ $test_uid, $cred_id, 'fake_pubkey_b64', 0, 'Test Auth Key', 'internal,hybrid', time() ]
    );

    my $r = $wa->generate_authentication_options( { username => 'root' } );
    is( $r->{error_code}, 200, 'with credential returns 200' );

    my $opts = decode_json( $r->{options} );
    is( ref $opts->{allowCredentials}, 'ARRAY', 'allowCredentials is array' );
    ok( scalar @{ $opts->{allowCredentials} } >= 1, 'at least one credential' );

    my ($match) = grep { $_->{id} eq $cred_id } @{ $opts->{allowCredentials} };
    ok( $match, 'test credential in allowCredentials' );
    is( ref $match->{transports}, 'ARRAY', 'transports parsed to array' );
};

# =====================================================================
# T6: generate_authentication_options WITHOUT username (usernameless)
# =====================================================================
subtest 'T6: auth options usernameless' => sub {
    my $r = $wa->generate_authentication_options( {} );
    is( $r->{error_code}, 200, 'no username returns 200' );

    my $opts = decode_json( $r->{options} );
    is( ref $opts->{allowCredentials},         'ARRAY', 'allowCredentials is array' );
    is( scalar @{ $opts->{allowCredentials} }, 0,       'allowCredentials is empty' );
    ok( $opts->{challenge}, 'challenge present' );

    # Stored with NULL uid
    my $rows = $wa->exec_query(
        'SELECT * FROM nt_user_webauthn_challenge
          WHERE challenge = ? AND nt_user_id IS NULL',
        $opts->{challenge}
    );
    ok( $rows && $rows->[0], 'challenge stored with NULL nt_user_id' );

    # Consumable with undef
    ok( $wa->_consume_challenge( $opts->{challenge}, 'authentication', undef ),
        'NULL uid challenge consumable' );
};

# =====================================================================
# T7: Credential CRUD
# =====================================================================
subtest 'T7: credential CRUD' => sub {

    # Clean slate
    $wa->exec_query(
        'DELETE FROM nt_user_webauthn_credential
          WHERE credential_id LIKE ?', "${test_prefix}_crud%"
    );

    # Missing uid
    is( $wa->get_user_credentials( {} )->{error_code}, 301, 'get: missing uid returns 301' );
    is( $wa->revoke_credential( { nt_user_id => 1 } )->{error_code},
        301, 'revoke: missing cred_id returns 301' );
    is( $wa->rename_credential( { nt_user_id => 1 } )->{error_code},
        301, 'rename: missing cred_id returns 301' );
    is(
        $wa->rename_credential(
            {   nt_user_id                => 1,
                nt_webauthn_credential_id => 1
            }
        )->{error_code},
        301,
        'rename: missing name returns 301'
    );

    # Insert credential
    my $cred_id = "${test_prefix}_crud1";
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_credential
            (nt_user_id, credential_id, credential_pubkey,
             signature_count, friendly_name, created_at)
            VALUES (??)',
        [ $test_uid, $cred_id, 'fake_pk', 0, 'My Key', time() ]
    );

    # List includes it
    my $list = $wa->get_user_credentials( { nt_user_id => $test_uid } );
    is( $list->{error_code}, 200, 'list returns 200' );
    my ($found) = grep { $_->{credential_id} eq $cred_id } @{ $list->{credentials} };
    ok( $found, 'credential in list' );
    is( $found->{friendly_name}, 'My Key', 'name correct' );
    my $db_id = $found->{nt_webauthn_credential_id};

    # Rename
    is(
        $wa->rename_credential(
            {   nt_user_id                => $test_uid,
                nt_webauthn_credential_id => $db_id,
                friendly_name             => 'Renamed',
            }
        )->{error_code},
        200,
        'rename returns 200'
    );
    my $list2 = $wa->get_user_credentials( { nt_user_id => $test_uid } );
    my ($renamed) = grep { $_->{credential_id} eq $cred_id } @{ $list2->{credentials} };
    is( $renamed->{friendly_name}, 'Renamed', 'rename took effect' );

    # Revoke
    is(
        $wa->revoke_credential(
            {   nt_user_id                => $test_uid,
                nt_webauthn_credential_id => $db_id,
            }
        )->{error_code},
        200,
        'revoke returns 200'
    );
    my $list3 = $wa->get_user_credentials( { nt_user_id => $test_uid } );
    my ($gone) = grep { $_->{credential_id} eq $cred_id } @{ $list3->{credentials} };
    ok( !$gone, 'revoked credential gone from list' );
};

# =====================================================================
# T8: verify_registration error paths
# =====================================================================
subtest 'T8: verify_registration errors' => sub {
    is( $wa->verify_registration( {} )->{error_code}, 301, 'missing uid returns 301' );
    is( $wa->verify_registration( { nt_user_id => $test_uid } )->{error_code},
        301, 'missing attestation fields returns 301' );
    is(
        $wa->verify_registration(
            {   nt_user_id             => $test_uid,
                challenge_b64          => 'nonexistent',
                client_data_json_b64   => 'fake',
                attestation_object_b64 => 'fake',
            }
        )->{error_code},
        403,
        'invalid challenge returns 403'
    );
};

# =====================================================================
# T9: verify_authentication error paths
# =====================================================================
subtest 'T9: verify_authentication errors' => sub {
    is( $wa->verify_authentication( {} )->{error_code}, 301, 'missing fields returns 301' );
    is(
        $wa->verify_authentication(
            {   challenge_b64          => 'fake',
                credential_id_b64      => 'nonexistent_cred',
                client_data_json_b64   => 'fake',
                authenticator_data_b64 => 'fake',
                signature_b64          => 'fake',
            }
        )->{error_code},
        403,
        'unknown credential returns 403'
    );

    # Revoked credential
    my $rev_cred = "${test_prefix}_rev_auth";
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_credential
            (nt_user_id, credential_id, credential_pubkey,
             signature_count, revoked, created_at)
            VALUES (??)',
        [ $test_uid, $rev_cred, 'fake', 0, 1, time() ]
    );
    is(
        $wa->verify_authentication(
            {   challenge_b64          => 'fake',
                credential_id_b64      => $rev_cred,
                client_data_json_b64   => 'fake',
                authenticator_data_b64 => 'fake',
                signature_b64          => 'fake',
            }
        )->{error_code},
        403,
        'revoked credential returns 403'
    );
};

# =====================================================================
# T10: verify_registration happy path (mocked)
# =====================================================================
subtest 'T10: verify_registration success' => sub {

    my $mock_cred_id = "${test_prefix}_reg_ok";
    my $mock_pubkey  = 'mock_pubkey_b64_value';

    # Insert a valid registration challenge
    my $challenge = "${test_prefix}_regchallenge";
    my $now       = time();
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_challenge
            (nt_user_id, challenge, ceremony_type,
             created_at, expires_at) VALUES (??)',
        [ $test_uid, $challenge, 'registration', $now, $now + 300 ]
    );

    # Mock Authen::WebAuthn so we don't need real crypto
    no warnings 'redefine';
    local *Authen::WebAuthn::new = sub {
        return bless {}, 'Authen::WebAuthn';
    };
    local *Authen::WebAuthn::validate_registration = sub {
        return {
            credential_id     => $mock_cred_id,
            credential_pubkey => $mock_pubkey,
            signature_count   => 0,
        };
    };

    my $r = $wa->verify_registration(
        {   nt_user_id             => $test_uid,
            challenge_b64          => $challenge,
            client_data_json_b64   => 'fake_cdj',
            attestation_object_b64 => 'fake_att',
            friendly_name          => 'Mock Key',
        }
    );
    is( $r->{error_code},    200,           'returns 200 on success' );
    is( $r->{credential_id}, $mock_cred_id, 'returns credential_id' );

    # Verify credential was stored in the DB
    my $rows = $wa->exec_query(
        'SELECT * FROM nt_user_webauthn_credential
          WHERE credential_id = ?', $mock_cred_id
    );
    ok( $rows && $rows->[0], 'credential row exists in DB' );
    is( $rows->[0]{credential_pubkey}, $mock_pubkey, 'pubkey stored correctly' );
    is( $rows->[0]{friendly_name},     'Mock Key',   'friendly_name stored' );
    is( $rows->[0]{nt_user_id},        $test_uid,    'credential bound to correct user' );
};

# =====================================================================
# T11: verify_authentication happy path (mocked)
# =====================================================================
subtest 'T11: verify_authentication success' => sub {

    # Insert a credential for the test user
    my $cred_id = "${test_prefix}_authok_cred";
    my $now     = time();
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_credential
            (nt_user_id, credential_id, credential_pubkey,
             signature_count, friendly_name, created_at)
            VALUES (??)',
        [ $test_uid, $cred_id, 'fake_auth_pk', 0, 'Auth Key', $now ]
    );

    # Insert a valid authentication challenge bound to the user
    my $challenge = "${test_prefix}_authchallenge";
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_challenge
            (nt_user_id, challenge, ceremony_type,
             created_at, expires_at) VALUES (??)',
        [ $test_uid, $challenge, 'authentication', $now, $now + 300 ]
    );

    # Mock Authen::WebAuthn
    no warnings 'redefine';
    local *Authen::WebAuthn::new = sub {
        return bless {}, 'Authen::WebAuthn';
    };
    local *Authen::WebAuthn::validate_assertion = sub {
        return { signature_count => 1 };
    };

    my $r = $wa->verify_authentication(
        {   challenge_b64          => $challenge,
            credential_id_b64      => $cred_id,
            client_data_json_b64   => 'fake_cdj',
            authenticator_data_b64 => 'fake_ad',
            signature_b64          => 'fake_sig',
        }
    );
    is( $r->{error_code}, 200,       'returns 200 on success' );
    is( $r->{nt_user_id}, $test_uid, 'returns correct nt_user_id' );
    is( $r->{username},   'root',    'returns correct username' );

    # Verify signature_count was updated in the DB
    my $rows = $wa->exec_query(
        'SELECT signature_count, last_used_at
           FROM nt_user_webauthn_credential
          WHERE credential_id = ?', $cred_id
    );
    ok( $rows && $rows->[0], 'credential row still exists' );
    is( $rows->[0]{signature_count}, 1, 'signature_count updated to 1' );
    ok( $rows->[0]{last_used_at}, 'last_used_at was set' );
};

# =====================================================================
# T12: cross-user authorization (user A cannot affect user B creds)
# =====================================================================
subtest 'T12: cross-user credential isolation' => sub {

    # Create a credential owned by user 1 (root)
    my $cred_id = "${test_prefix}_xuser";
    my $now     = time();
    $wa->exec_query(
        'INSERT INTO nt_user_webauthn_credential
            (nt_user_id, credential_id, credential_pubkey,
             signature_count, friendly_name, created_at)
            VALUES (??)',
        [ $test_uid, $cred_id, 'xuser_pk', 0, 'Cross User Key', $now ]
    );

    # Get the DB-assigned ID
    my $rows = $wa->exec_query(
        'SELECT nt_webauthn_credential_id
           FROM nt_user_webauthn_credential
          WHERE credential_id = ?', $cred_id
    );
    my $db_id = $rows->[0]{nt_webauthn_credential_id};
    ok( $db_id, 'credential inserted with DB id' );

    my $other_uid = 99999;    # nonexistent user

    # Attempt revoke as wrong user -- should silently not match
    $wa->revoke_credential(
        {   nt_user_id                => $other_uid,
            nt_webauthn_credential_id => $db_id,
        }
    );

    # Verify credential is NOT revoked
    my $after_revoke = $wa->exec_query(
        'SELECT revoked FROM nt_user_webauthn_credential
          WHERE nt_webauthn_credential_id = ?', $db_id
    );
    is( $after_revoke->[0]{revoked}, 0, 'revoke by wrong user did not affect credential' );

    # Attempt rename as wrong user
    $wa->rename_credential(
        {   nt_user_id                => $other_uid,
            nt_webauthn_credential_id => $db_id,
            friendly_name             => 'Hacked Name',
        }
    );

    # Verify name is unchanged
    my $after_rename = $wa->exec_query(
        'SELECT friendly_name FROM nt_user_webauthn_credential
          WHERE nt_webauthn_credential_id = ?', $db_id
    );
    is( $after_rename->[0]{friendly_name},
        'Cross User Key',
        'rename by wrong user did not change name'
    );
};

# =====================================================================
# Cleanup
# =====================================================================
END {
    if ($wa) {
        $wa->exec_query(
            'DELETE FROM nt_user_webauthn_challenge
              WHERE challenge LIKE ?', "${test_prefix}%"
        );
        $wa->exec_query(
            'DELETE FROM nt_user_webauthn_credential
              WHERE credential_id LIKE ?', "${test_prefix}%"
        );

        # Clean generated challenges from registration/auth options
        $wa->exec_query(
            'DELETE FROM nt_user_webauthn_challenge
              WHERE nt_user_id = ? AND consumed = 0', $test_uid
        );
        $wa->exec_query(
            'DELETE FROM nt_user_webauthn_challenge
              WHERE nt_user_id IS NULL AND consumed = 0'
        );

        # Restore original options
        $wa->exec_query( 'DELETE FROM nt_options WHERE option_name = ?', 'webauthn_enabled' );
        $wa->exec_query( 'DELETE FROM nt_options WHERE option_name = ?', 'webauthn_rp_id' );
        $wa->exec_query( 'DELETE FROM nt_options WHERE option_name = ?', 'webauthn_origin' );
        if ($orig_enabled) {
            $wa->exec_query(
                'INSERT INTO nt_options
                    (option_name, option_value) VALUES (?, ?)',
                [ 'webauthn_enabled', $orig_enabled ]
            );
        }
        if ($orig_rp_id) {
            $wa->exec_query(
                'INSERT INTO nt_options
                    (option_name, option_value) VALUES (?, ?)',
                [ 'webauthn_rp_id', $orig_rp_id ]
            );
        }
        if ($orig_origin) {
            $wa->exec_query(
                'INSERT INTO nt_options
                    (option_name, option_value) VALUES (?, ?)',
                [ 'webauthn_origin', $orig_origin ]
            );
        }
    }
}

done_testing();
