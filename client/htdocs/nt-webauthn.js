/**
 * NicTool WebAuthn/Passkey support
 *
 * Provides browser-side WebAuthn ceremony helpers for passkey
 * registration and authentication. ES5-compatible, uses jQuery
 * for AJAX calls (consistent with existing NicTool JS).
 */

/* global jQuery, navigator, Uint8Array, document, window */

(function ($) {
    'use strict';

    // --- Base64URL helpers ---

    function base64urlToBytes(str) {
        // Pad to multiple of 4
        var pad = str.length % 4;
        if (pad === 2) str += '==';
        else if (pad === 3) str += '=';
        // Convert base64url to base64
        str = str.replace(/-/g, '+').replace(/_/g, '/');
        var raw = atob(str);
        var bytes = new Uint8Array(raw.length);
        for (var i = 0; i < raw.length; i++) {
            bytes[i] = raw.charCodeAt(i);
        }
        return bytes.buffer;
    }

    function bytesToBase64url(buffer) {
        var bytes = new Uint8Array(buffer);
        var str = '';
        for (var i = 0; i < bytes.length; i++) {
            str += String.fromCharCode(bytes[i]);
        }
        return btoa(str)
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=+$/, '');
    }

    // --- Feature detection ---

    function isSupported() {
        return !!(
            window.PublicKeyCredential &&
            navigator.credentials &&
            navigator.credentials.create &&
            navigator.credentials.get
        );
    }

    // --- AJAX helper ---

    function webauthnPost(action, payload, csrfToken) {
        return $.ajax({
            url: 'webauthn.cgi',
            method: 'POST',
            contentType: 'application/json',
            data: JSON.stringify({
                action: action,
                csrf_token: csrfToken,
                data: payload
            }),
            dataType: 'json'
        });
    }

    // --- Registration ceremony ---

    function register(csrfToken, ntUserId, friendlyName) {
        if (!isSupported()) {
            alert('Your browser does not support passkeys.');
            return $.Deferred().reject('unsupported').promise();
        }

        var deferred = $.Deferred();

        // Step 1: Get registration options from server
        webauthnPost(
            'webauthn_get_registration_options',
            { nt_user_id: ntUserId },
            csrfToken
        ).done(function (resp) {
            if (resp.error_code && +resp.error_code !== 200) {
                deferred.reject(resp.error_msg || 'Server error');
                return;
            }

            var options = JSON.parse(resp.options);

            // Convert base64url fields to ArrayBuffer
            options.challenge = base64urlToBytes(options.challenge);
            options.user.id = base64urlToBytes(options.user.id);

            if (options.excludeCredentials) {
                for (var i = 0; i < options.excludeCredentials.length; i++) {
                    options.excludeCredentials[i].id =
                        base64urlToBytes(options.excludeCredentials[i].id);
                }
            }

            // Step 2: Browser ceremony
            navigator.credentials
                .create({ publicKey: options })
                .then(function (credential) {
                    // Step 3: Send attestation to server
                    var response = credential.response;
                    var transports = [];
                    if (response.getTransports) {
                        transports = response.getTransports();
                    }

                    webauthnPost(
                        'webauthn_verify_registration',
                        {
                            nt_user_id: ntUserId,
                            challenge_b64: bytesToBase64url(
                                options.challenge
                            ),
                            client_data_json_b64: bytesToBase64url(
                                response.clientDataJSON
                            ),
                            attestation_object_b64: bytesToBase64url(
                                response.attestationObject
                            ),
                            friendly_name:
                                friendlyName || 'Passkey',
                            transports: transports.join(',')
                        },
                        csrfToken
                    )
                        .done(function (verifyResp) {
                            if (
                                verifyResp.error_code &&
                                +verifyResp.error_code !== 200
                            ) {
                                deferred.reject(
                                    verifyResp.error_msg
                                );
                            } else {
                                deferred.resolve(verifyResp);
                            }
                        })
                        .fail(function () {
                            deferred.reject(
                                'Failed to verify registration'
                            );
                        });
                })
                .catch(function (err) {
                    deferred.reject(
                        err.message || 'Passkey creation cancelled'
                    );
                });
        }).fail(function () {
            deferred.reject('Failed to get registration options');
        });

        return deferred.promise();
    }

    // --- Authentication ceremony ---

    function authenticate(csrfToken, username) {
        if (!isSupported()) {
            alert('Your browser does not support passkeys.');
            return $.Deferred().reject('unsupported').promise();
        }

        var deferred = $.Deferred();

        // Step 1: Get authentication options (username optional)
        var optionsPayload = {};
        if (username) optionsPayload.username = username;

        webauthnPost(
            'webauthn_get_auth_options',
            optionsPayload,
            csrfToken
        ).done(function (resp) {
            if (resp.error_code && +resp.error_code !== 200) {
                deferred.reject(resp.error_msg || 'Server error');
                return;
            }

            var options = JSON.parse(resp.options);

            // Convert base64url fields to ArrayBuffer
            options.challenge = base64urlToBytes(options.challenge);

            if (options.allowCredentials) {
                for (var i = 0; i < options.allowCredentials.length; i++) {
                    options.allowCredentials[i].id =
                        base64urlToBytes(options.allowCredentials[i].id);
                }
            }

            // Step 2: Browser ceremony
            navigator.credentials
                .get({ publicKey: options })
                .then(function (assertion) {
                    var response = assertion.response;

                    // Step 3: Send assertion to server
                    var verifyPayload = {
                        challenge_b64: bytesToBase64url(
                            options.challenge
                        ),
                        credential_id_b64: bytesToBase64url(
                            assertion.rawId
                        ),
                        client_data_json_b64: bytesToBase64url(
                            response.clientDataJSON
                        ),
                        authenticator_data_b64: bytesToBase64url(
                            response.authenticatorData
                        ),
                        signature_b64: bytesToBase64url(
                            response.signature
                        )
                    };
                    if (response.userHandle &&
                        response.userHandle.byteLength > 0) {
                        verifyPayload.user_handle_b64 =
                            bytesToBase64url(response.userHandle);
                    }
                    webauthnPost(
                        'webauthn_verify_auth',
                        verifyPayload,
                        csrfToken
                    )
                        .done(function (verifyResp) {
                            if (
                                verifyResp.error_code &&
                                +verifyResp.error_code !== 200
                            ) {
                                deferred.reject(
                                    verifyResp.error_msg
                                );
                            } else {
                                deferred.resolve(verifyResp);
                            }
                        })
                        .fail(function () {
                            deferred.reject(
                                'Failed to verify authentication'
                            );
                        });
                })
                .catch(function (err) {
                    deferred.reject(
                        err.message || 'Passkey authentication cancelled'
                    );
                });
        }).fail(function () {
            deferred.reject('Failed to get authentication options');
        });

        return deferred.promise();
    }

    // --- Credential management ---

    function revokeCredential(csrfToken, ntUserId, credentialId) {
        return webauthnPost(
            'webauthn_revoke_credential',
            {
                nt_user_id: ntUserId,
                nt_webauthn_credential_id: credentialId
            },
            csrfToken
        );
    }

    function renameCredential(csrfToken, ntUserId, credentialId, name) {
        return webauthnPost(
            'webauthn_rename_credential',
            {
                nt_user_id: ntUserId,
                nt_webauthn_credential_id: credentialId,
                friendly_name: name
            },
            csrfToken
        );
    }

    function listCredentials(csrfToken, ntUserId) {
        return webauthnPost(
            'webauthn_get_user_credentials',
            { nt_user_id: ntUserId },
            csrfToken
        );
    }

    // --- Public API ---

    window.NtWebAuthn = {
        isSupported: isSupported,
        register: register,
        authenticate: authenticate,
        revokeCredential: revokeCredential,
        renameCredential: renameCredential,
        listCredentials: listCredentials
    };
})(jQuery);
