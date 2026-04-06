import { test, expect } from '@playwright/test';
import {
  BASE, USERNAME, PASSWORD,
  freshCtx, getLoginCsrf, apiLogin, cookieString, extractCsrf,
  webauthnPost, listPasskeys, revokeAllPasskeys,
  browserLogin, setupVirtualAuthenticator, teardownVirtualAuthenticator,
} from './helpers';

// Base64url helpers injected into browser context via page.addScriptTag.
// page.evaluate callbacks run in an isolated browser scope and cannot import
// Node modules, so we inject these once per page instead of duplicating them
// inside every evaluate call.
const B64U_HELPERS = `
function b64u2buf(s) {
  var b = s.replace(/-/g, '+').replace(/_/g, '/');
  while (b.length % 4) b += '=';
  var r = atob(b);
  var a = new Uint8Array(r.length);
  for (var i = 0; i < r.length; i++) a[i] = r.charCodeAt(i);
  return a.buffer;
}
function buf2b64u(b) {
  var u = new Uint8Array(b);
  var s = '';
  for (var i = 0; i < u.length; i++) s += String.fromCharCode(u[i]);
  return btoa(s).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
}
`;

/** Inject b64u helpers into every frame of the page. */
async function injectB64UHelpers(page: import('@playwright/test').Page) {
  await page.addScriptTag({ content: B64U_HELPERS });
  for (const frame of page.frames()) {
    try { await frame.addScriptTag({ content: B64U_HELPERS }); }
    catch { /* frame may not accept scripts */ }
  }
}

/** Wait for the NicTool frameset to finish loading after login. */
async function waitForFrameset(page: import('@playwright/test').Page) {
  await page.waitForFunction(
    () => window.frames.length > 0,
    { timeout: 10000 },
  );
}

/** Wait for the login page to be ready after navigation. */
async function waitForLoginPage(page: import('@playwright/test').Page) {
  await page.waitForSelector(
    'input[name="username"]',
    { timeout: 10000 },
  );
}

// -------------------------------------------------------------------------
// W1: CSRF protection on webauthn.cgi
// -------------------------------------------------------------------------
test.describe('W1: WebAuthn CSRF protection', () => {
  test('POST with wrong csrf_token rejected', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const { csrfCookie } = await getLoginCsrf(ctx);

    const res = await ctx.post(`${BASE}/webauthn.cgi`, {
      headers: {
        'Content-Type': 'application/json',
        Cookie: `NicTool_csrf=${csrfCookie}`,
      },
      data: JSON.stringify({
        action: 'webauthn_get_auth_options',
        csrf_token: '0000000000000000000000000000000000000000',
        data: {},
      }),
    });

    const json = JSON.parse(await res.text());
    expect(json.error_code).toBe(403);
    expect(json.error_msg).toContain('CSRF');
    await ctx.dispose();
  });

  test('POST with missing csrf_token rejected', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const { csrfCookie } = await getLoginCsrf(ctx);

    const res = await ctx.post(`${BASE}/webauthn.cgi`, {
      headers: {
        'Content-Type': 'application/json',
        Cookie: `NicTool_csrf=${csrfCookie}`,
      },
      data: JSON.stringify({
        action: 'webauthn_get_auth_options',
        data: {},
      }),
    });

    const json = JSON.parse(await res.text());
    expect(json.error_code).toBe(403);
    await ctx.dispose();
  });

  test('GET request rejected with 405', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const res = await ctx.get(`${BASE}/webauthn.cgi`);
    const json = JSON.parse(await res.text());
    expect(json.error_code).toBe(405);
    await ctx.dispose();
  });
});

// -------------------------------------------------------------------------
// W2: Authenticated endpoints require session
// -------------------------------------------------------------------------
test.describe('W2: WebAuthn session requirement', () => {
  test('get_user_credentials without session returns 403', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const { csrfCookie } = await getLoginCsrf(ctx);
    await ctx.dispose();

    const { json } = await webauthnPost(
      playwright, 'webauthn_get_user_credentials',
      { nt_user_id: 1 }, csrfCookie
    );
    expect(json.error_code).toBe(403);
  });
});

// -------------------------------------------------------------------------
// W3: Login page passkey button
// -------------------------------------------------------------------------
test.describe('W3: Login page passkey UI', () => {
  test('passkey button visible when WebAuthn supported', async ({ page }) => {
    await page.goto(`${BASE}/index.cgi`);
    const btn = page.locator('#nt-passkey-login');
    await expect(btn).toBeVisible();
  });

  test('passkey button clickable without entering username', async ({ page }) => {
    await page.goto(`${BASE}/index.cgi`);
    // Should not show an alert when username is empty (after fix)
    const btn = page.locator('#nt-passkey-login');
    await expect(btn).toBeVisible();
    // We can't complete the ceremony without a virtual authenticator,
    // but we verify no "enter username" alert fires
    page.on('dialog', (dialog) => {
      // If we get a "Please enter your username" alert, the fix failed
      expect(dialog.message()).not.toContain('username');
      dialog.dismiss();
    });
    await btn.click();
    // Give a moment for any alert/dialog to fire
    await page.waitForTimeout(500);
  });
});

// -------------------------------------------------------------------------
// W4-W7: Full WebAuthn ceremonies (virtual authenticator)
// -------------------------------------------------------------------------
test.describe('W4-W7: WebAuthn ceremonies', () => {
  // These tests probe the server first; skip all if WebAuthn is not configured
  let webauthnConfigured = false;

  test.beforeAll(async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    const { json } = await webauthnPost(
      playwright, 'webauthn_get_registration_options',
      { nt_user_id: 1 }, csrfCookie, sessionCookie
    );
    webauthnConfigured = (+json.error_code === 200);
  });

  test('W4: register passkey via virtual authenticator', async ({ page }) => {
    test.skip(!webauthnConfigured, 'WebAuthn not configured on server');

    const { cdpSession, authenticatorId } = await setupVirtualAuthenticator(page);
    try {
      await browserLogin(page);
      await waitForFrameset(page);

      const bodyFrame = page.frames().find(f =>
        f.url().includes('group.cgi'));
      expect(bodyFrame).toBeTruthy();

      await injectB64UHelpers(page);

      // Run registration ceremony inside the frame's browser context
      const result = await bodyFrame!.evaluate(async (baseUrl: string) => {
        const csrf = document.cookie.match(/NicTool_csrf=([^;]+)/)?.[1] || '';

        // Step 1: get options
        const optRes = await fetch(`${baseUrl}/webauthn.cgi`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'webauthn_get_registration_options',
            csrf_token: csrf,
            data: { nt_user_id: '1' },
          }),
        });
        const optData = await optRes.json();
        if (+optData.error_code !== 200)
          return { ok: false, error: optData.error_msg };

        const opts = JSON.parse(optData.options);
        const pkOpts: any = {
          challenge: b64u2buf(opts.challenge),
          rp: opts.rp,
          user: { ...opts.user, id: b64u2buf(opts.user.id) },
          pubKeyCredParams: opts.pubKeyCredParams,
          timeout: opts.timeout,
          attestation: opts.attestation || 'none',
          authenticatorSelection: opts.authenticatorSelection,
        };
        if (opts.excludeCredentials) {
          pkOpts.excludeCredentials = opts.excludeCredentials.map(
            (c: any) => ({ ...c, id: b64u2buf(c.id) })
          );
        }

        // Step 2: create credential (virtual authenticator intercepts)
        const cred = (await navigator.credentials.create({
          publicKey: pkOpts,
        })) as PublicKeyCredential;
        const resp = cred.response as AuthenticatorAttestationResponse;
        const transports = resp.getTransports ? resp.getTransports() : [];

        // Step 3: verify registration
        const verRes = await fetch(`${baseUrl}/webauthn.cgi`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'webauthn_verify_registration',
            csrf_token: csrf,
            data: {
              nt_user_id: '1',
              challenge_b64: buf2b64u(pkOpts.challenge),
              client_data_json_b64: buf2b64u(resp.clientDataJSON),
              attestation_object_b64: buf2b64u(resp.attestationObject),
              friendly_name: 'E2E Virtual Passkey',
              transports: transports.join(','),
            },
          }),
        });
        const verData = await verRes.json();
        return {
          ok: +verData.error_code === 200,
          error: verData.error_msg,
          credential_id: verData.credential_id,
        };
      }, BASE);

      expect(result.ok).toBe(true);
      expect(result.credential_id).toBeTruthy();
    } finally {
      // Cleanup: revoke all passkeys for root
      const { sessionCookie, csrfCookie } = await apiLogin(page.context().request);
      const cookies = cookieString(sessionCookie, csrfCookie);
      await revokeAllPasskeys(page.context().request, cookies, 1);
      await teardownVirtualAuthenticator(cdpSession, authenticatorId);
    }
  });

  test('W5: passkey login without username (usernameless)', async ({ page }) => {
    test.skip(!webauthnConfigured, 'WebAuthn not configured on server');

    const { cdpSession, authenticatorId } = await setupVirtualAuthenticator(page);
    try {
      // --- Phase 1: Register a passkey while logged in ---
      await browserLogin(page);
      await waitForFrameset(page);

      const bodyFrame = page.frames().find(f =>
        f.url().includes('group.cgi'));
      expect(bodyFrame).toBeTruthy();

      await injectB64UHelpers(page);

      const regResult = await bodyFrame!.evaluate(async (baseUrl: string) => {
        const csrf = document.cookie.match(/NicTool_csrf=([^;]+)/)?.[1] || '';
        const optRes = await fetch(`${baseUrl}/webauthn.cgi`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'webauthn_get_registration_options',
            csrf_token: csrf,
            data: { nt_user_id: '1' },
          }),
        });
        const optData = await optRes.json();
        if (+optData.error_code !== 200) return { ok: false, error: optData.error_msg };

        const opts = JSON.parse(optData.options);
        const pkOpts: any = {
          challenge: b64u2buf(opts.challenge),
          rp: opts.rp,
          user: { ...opts.user, id: b64u2buf(opts.user.id) },
          pubKeyCredParams: opts.pubKeyCredParams,
          timeout: opts.timeout,
          attestation: opts.attestation || 'none',
          authenticatorSelection: opts.authenticatorSelection,
        };
        if (opts.excludeCredentials)
          pkOpts.excludeCredentials = opts.excludeCredentials.map(
            (c: any) => ({ ...c, id: b64u2buf(c.id) }));

        const cred = (await navigator.credentials.create({
          publicKey: pkOpts,
        })) as PublicKeyCredential;
        const resp = cred.response as AuthenticatorAttestationResponse;
        const transports = resp.getTransports ? resp.getTransports() : [];

        const verRes = await fetch(`${baseUrl}/webauthn.cgi`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'webauthn_verify_registration',
            csrf_token: csrf,
            data: {
              nt_user_id: '1',
              challenge_b64: buf2b64u(pkOpts.challenge),
              client_data_json_b64: buf2b64u(resp.clientDataJSON),
              attestation_object_b64: buf2b64u(resp.attestationObject),
              friendly_name: 'E2E Login Test Key',
              transports: transports.join(','),
            },
          }),
        });
        const verData = await verRes.json();
        return { ok: +verData.error_code === 200, error: verData.error_msg };
      }, BASE);
      expect(regResult.ok).toBe(true);

      // --- Phase 2: Logout ---
      const cookies = await page.context().cookies();
      const sessionCk = cookies.find(c => c.name === 'NicTool')?.value || '';
      const csrfCk = cookies.find(c => c.name === 'NicTool_csrf')?.value || '';
      await page.goto(`${BASE}/index.cgi?logout=1`, {
        headers: { Cookie: `NicTool=${sessionCk}; NicTool_csrf=${csrfCk}` },
      });
      await waitForLoginPage(page);

      // --- Phase 3: Passkey login without username ---
      await page.goto(`${BASE}/index.cgi`);
      await waitForLoginPage(page);

      await injectB64UHelpers(page);

      const loginResult = await page.evaluate(async (baseUrl: string) => {
        const csrf = document.cookie.match(/NicTool_csrf=([^;]+)/)?.[1]
          || document.querySelector<HTMLInputElement>('input[name="csrf_token"]')?.value
          || '';

        // Step 1: get auth options (no username = usernameless)
        const optRes = await fetch(`${baseUrl}/webauthn.cgi`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'webauthn_get_auth_options',
            csrf_token: csrf,
            data: {},
          }),
        });
        const optData = await optRes.json();
        if (+optData.error_code !== 200)
          return { ok: false, error: optData.error_msg };

        const opts = JSON.parse(optData.options);
        const pkOpts: any = {
          challenge: b64u2buf(opts.challenge),
          rpId: opts.rpId,
          timeout: opts.timeout,
          userVerification: opts.userVerification,
        };
        // allowCredentials should be empty for usernameless
        if (opts.allowCredentials && opts.allowCredentials.length > 0) {
          pkOpts.allowCredentials = opts.allowCredentials.map(
            (c: any) => ({ ...c, id: b64u2buf(c.id) }));
        }

        // Step 2: get assertion (virtual authenticator picks discoverable cred)
        const assertion = (await navigator.credentials.get({
          publicKey: pkOpts,
        })) as PublicKeyCredential;
        const resp = assertion.response as AuthenticatorAssertionResponse;

        // Step 3: verify auth
        const verRes = await fetch(`${baseUrl}/webauthn.cgi`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'webauthn_verify_auth',
            csrf_token: csrf,
            data: {
              challenge_b64: buf2b64u(pkOpts.challenge),
              credential_id_b64: buf2b64u(assertion.rawId),
              client_data_json_b64: buf2b64u(resp.clientDataJSON),
              authenticator_data_b64: buf2b64u(resp.authenticatorData),
              signature_b64: buf2b64u(resp.signature),
            },
          }),
        });
        const verData = await verRes.json();
        return {
          ok: +verData.error_code === 200,
          error: verData.error_msg,
          hasSession: !!verData.nt_user_session,
        };
      }, BASE);

      expect(loginResult.ok).toBe(true);
      expect(loginResult.hasSession).toBe(true);
    } finally {
      // Cleanup
      try {
        const { sessionCookie, csrfCookie } = await apiLogin(page.context().request);
        const ck = cookieString(sessionCookie, csrfCookie);
        await revokeAllPasskeys(page.context().request, ck, 1);
      } catch { /* best effort */ }
      await teardownVirtualAuthenticator(cdpSession, authenticatorId);
    }
  });

  test('W6: credential list', async ({ playwright }) => {
    test.skip(!webauthnConfigured, 'WebAuthn not configured on server');

    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    const cookies = cookieString(sessionCookie, csrfCookie);

    // Verify list endpoint works (may be empty)
    const creds = await listPasskeys(playwright, cookies, 1);
    expect(Array.isArray(creds)).toBe(true);
  });

  test('W7: revoked credential rejected at login', async ({ page }) => {
    test.skip(!webauthnConfigured, 'WebAuthn not configured on server');

    const { cdpSession, authenticatorId } = await setupVirtualAuthenticator(page);
    try {
      // Register a passkey
      await browserLogin(page);
      await waitForFrameset(page);
      const bodyFrame = page.frames().find(f =>
        f.url().includes('group.cgi'));
      expect(bodyFrame).toBeTruthy();

      await injectB64UHelpers(page);

      const regResult = await bodyFrame!.evaluate(async (baseUrl: string) => {
        const csrf = document.cookie.match(/NicTool_csrf=([^;]+)/)?.[1] || '';
        const optRes = await fetch(`${baseUrl}/webauthn.cgi`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'webauthn_get_registration_options',
            csrf_token: csrf,
            data: { nt_user_id: '1' },
          }),
        });
        const optData = await optRes.json();
        if (+optData.error_code !== 200) return { ok: false, error: optData.error_msg };
        const opts = JSON.parse(optData.options);
        const pkOpts: any = {
          challenge: b64u2buf(opts.challenge),
          rp: opts.rp,
          user: { ...opts.user, id: b64u2buf(opts.user.id) },
          pubKeyCredParams: opts.pubKeyCredParams,
          timeout: opts.timeout,
          attestation: opts.attestation || 'none',
          authenticatorSelection: opts.authenticatorSelection,
        };
        if (opts.excludeCredentials)
          pkOpts.excludeCredentials = opts.excludeCredentials.map(
            (c: any) => ({ ...c, id: b64u2buf(c.id) }));
        const cred = (await navigator.credentials.create({
          publicKey: pkOpts,
        })) as PublicKeyCredential;
        const resp = cred.response as AuthenticatorAttestationResponse;
        const verRes = await fetch(`${baseUrl}/webauthn.cgi`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'webauthn_verify_registration',
            csrf_token: csrf,
            data: {
              nt_user_id: '1',
              challenge_b64: buf2b64u(pkOpts.challenge),
              client_data_json_b64: buf2b64u(resp.clientDataJSON),
              attestation_object_b64: buf2b64u(resp.attestationObject),
              friendly_name: 'E2E Revoke Test',
              transports: '',
            },
          }),
        });
        const verData = await verRes.json();
        return { ok: +verData.error_code === 200, credential_id: verData.credential_id };
      }, BASE);
      expect(regResult.ok).toBe(true);

      // Revoke all credentials via API
      const { sessionCookie, csrfCookie } = await apiLogin(page.context().request);
      const cookies = cookieString(sessionCookie, csrfCookie);
      await revokeAllPasskeys(page.context().request, cookies, 1);

      // Logout
      await page.goto(`${BASE}/index.cgi?logout=1`);
      await waitForLoginPage(page);

      // Try passkey login -- should fail because credential is revoked
      // (The virtual authenticator still has the key, but server rejects it)
      await page.goto(`${BASE}/index.cgi`);
      await waitForLoginPage(page);

      await injectB64UHelpers(page);

      const loginResult = await page.evaluate(async (baseUrl: string) => {
        const csrf = document.cookie.match(/NicTool_csrf=([^;]+)/)?.[1]
          || document.querySelector<HTMLInputElement>('input[name="csrf_token"]')?.value
          || '';

        // Get auth options (usernameless — empty allowCredentials)
        const optRes = await fetch(`${baseUrl}/webauthn.cgi`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'webauthn_get_auth_options',
            csrf_token: csrf,
            data: {},
          }),
        });
        const optData = await optRes.json();
        if (+optData.error_code !== 200)
          return { ok: false, error: optData.error_msg };

        const opts = JSON.parse(optData.options);
        const pkOpts: any = {
          challenge: b64u2buf(opts.challenge),
          rpId: opts.rpId,
          timeout: opts.timeout,
          userVerification: opts.userVerification,
        };

        let assertion: PublicKeyCredential;
        try {
          assertion = (await navigator.credentials.get({
            publicKey: pkOpts,
          })) as PublicKeyCredential;
        } catch {
          // Virtual authenticator may refuse if no matching cred
          return { ok: false, error: 'no credential available' };
        }
        const resp = assertion.response as AuthenticatorAssertionResponse;

        const verRes = await fetch(`${baseUrl}/webauthn.cgi`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'webauthn_verify_auth',
            csrf_token: csrf,
            data: {
              challenge_b64: buf2b64u(pkOpts.challenge),
              credential_id_b64: buf2b64u(assertion.rawId),
              client_data_json_b64: buf2b64u(resp.clientDataJSON),
              authenticator_data_b64: buf2b64u(resp.authenticatorData),
              signature_b64: buf2b64u(resp.signature),
            },
          }),
        });
        const verData = await verRes.json();
        return { ok: +verData.error_code === 200, error: verData.error_msg };
      }, BASE);

      // Login should fail — credential was revoked server-side
      expect(loginResult.ok).toBe(false);
    } finally {
      await teardownVirtualAuthenticator(cdpSession, authenticatorId);
    }
  });
});
