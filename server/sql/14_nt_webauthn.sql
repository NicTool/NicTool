
DROP TABLE IF EXISTS nt_user_webauthn_credential;
CREATE TABLE nt_user_webauthn_credential (
    nt_webauthn_credential_id  INT UNSIGNED AUTO_INCREMENT NOT NULL,
    nt_user_id                 INT UNSIGNED NOT NULL,
    credential_id              VARCHAR(512) NOT NULL,
    credential_pubkey          TEXT NOT NULL,
    signature_count            INT UNSIGNED NOT NULL DEFAULT 0,
    friendly_name              VARCHAR(255) DEFAULT NULL,
    transports                 VARCHAR(255) DEFAULT NULL,
    created_at                 INT UNSIGNED NOT NULL,
    last_used_at               INT UNSIGNED DEFAULT NULL,
    revoked                    TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (nt_webauthn_credential_id),
    UNIQUE KEY uk_credential_id (credential_id),
    KEY idx_user_id (nt_user_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

DROP TABLE IF EXISTS nt_user_webauthn_challenge;
CREATE TABLE nt_user_webauthn_challenge (
    nt_webauthn_challenge_id   INT UNSIGNED AUTO_INCREMENT NOT NULL,
    nt_user_id                 INT UNSIGNED DEFAULT NULL,
    challenge                  VARCHAR(128) NOT NULL,
    ceremony_type              ENUM('registration','authentication') NOT NULL,
    created_at                 INT UNSIGNED NOT NULL,
    expires_at                 INT UNSIGNED NOT NULL,
    consumed                   TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (nt_webauthn_challenge_id),
    UNIQUE KEY uk_challenge (challenge),
    KEY idx_expires (expires_at)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

