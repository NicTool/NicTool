import { test, expect } from '@playwright/test';
import {
  BASE, USERNAME, PASSWORD, GROUP_DEFAULTS,
  freshCtx, getLoginCsrf, apiLogin, authGet, authPost,
  expectSecurityHeaders, browserLogin, collectViolations,
} from './helpers';

// ---------------------------------------------------------------------------
// T1: Security Headers
// ---------------------------------------------------------------------------
test.describe('T1: Security Headers', () => {
  test('login page has all security headers', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const res = await ctx.get(`${BASE}/index.cgi`);
    expect(res.status()).toBe(200);
    expectSecurityHeaders(res.headers());
    await ctx.dispose();
  });

  test('authenticated page has all security headers', async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    const cookies = `NicTool=${sessionCookie}; NicTool_csrf=${csrfCookie}`;
    const { res } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=1`, cookies);
    expect(res.status()).toBe(200);
    expectSecurityHeaders(res.headers());
  });
});

// ---------------------------------------------------------------------------
// T2: Cookie Flags
// ---------------------------------------------------------------------------
test.describe('T2: Cookie Flags', () => {
  test('NicTool session cookie has HttpOnly, Secure, SameSite=Strict', async ({ playwright }) => {
    const { setCookieHeaders } = await apiLogin(playwright);
    const sessionHeader = setCookieHeaders.find(h => /^NicTool=[^;]/.test(h.value) && !h.value.startsWith('NicTool_csrf'));
    expect(sessionHeader).toBeTruthy();
    const val = sessionHeader!.value.toLowerCase();
    expect(val).toContain('httponly');
    expect(val).toContain('samesite=strict');
    expect(val).toContain('secure');
  });

  test('NicTool_csrf cookie: no HttpOnly, SameSite=Strict, 40-char hex', async ({ playwright }) => {
    const { setCookieHeaders } = await apiLogin(playwright);
    const csrfHeader = setCookieHeaders.find(h => h.value.startsWith('NicTool_csrf='));
    expect(csrfHeader).toBeTruthy();
    const val = csrfHeader!.value;
    expect(val.toLowerCase()).not.toContain('httponly');
    expect(val.toLowerCase()).toContain('samesite=strict');
    const m = val.match(/NicTool_csrf=([^;]+)/);
    expect(m).toBeTruthy();
    expect(m![1]).toMatch(/^[0-9a-f]{40}$/);
  });
});

// ---------------------------------------------------------------------------
// T3: Login Page Link URLs
// ---------------------------------------------------------------------------
test.describe('T3: Login Page Links', () => {
  test('License and Source links have correct URLs', async ({ page }) => {
    await page.goto(`${BASE}/index.cgi`);
    const licenseLink = page.locator('a:has-text("License")');
    await expect(licenseLink).toHaveAttribute('href', 'https://www.gnu.org/licenses/agpl-3.0.html');
    const sourceLink = page.locator('a:has-text("Source")');
    await expect(sourceLink).toHaveAttribute('href', 'https://github.com/NicTool/NicTool');
  });
});

// ---------------------------------------------------------------------------
// T4: CSRF Token Present in Login Form
// ---------------------------------------------------------------------------
test.describe('T4: CSRF in Login Form', () => {
  test('login form has csrf_token hidden field matching cookie', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const { csrfToken, csrfCookie } = await getLoginCsrf(ctx);
    await ctx.dispose();

    expect(csrfToken).toBeTruthy();
    expect(csrfToken.length).toBe(40);
    expect(csrfToken).toMatch(/^[0-9a-f]{40}$/);
    expect(csrfCookie).toBeTruthy();
    expect(csrfCookie).toBe(csrfToken);
  });
});

// ---------------------------------------------------------------------------
// T5: CSRF Blocks Forged Login
// ---------------------------------------------------------------------------
test.describe('T5: CSRF Blocks Forged Login', () => {
  test('login rejected with wrong csrf_token', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const { csrfCookie } = await getLoginCsrf(ctx);
    const res = await ctx.post(`${BASE}/index.cgi`, {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': `NicTool_csrf=${csrfCookie}` },
      data: `username=${USERNAME}&password=${PASSWORD}&login=Enter&csrf_token=0000000000000000000000000000000000000000`,
    });
    const body = await res.text();
    expect(body).toContain('Session expired');
    expect(body.toLowerCase()).not.toContain('<frameset');
    await ctx.dispose();
  });

  test('login rejected with missing csrf_token', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const { csrfCookie } = await getLoginCsrf(ctx);
    const res = await ctx.post(`${BASE}/index.cgi`, {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': `NicTool_csrf=${csrfCookie}` },
      data: `username=${USERNAME}&password=${PASSWORD}&login=Enter`,
    });
    const body = await res.text();
    expect(body).toContain('Session expired');
    expect(body.toLowerCase()).not.toContain('<frameset');
    await ctx.dispose();
  });
});

// ---------------------------------------------------------------------------
// T6: CSRF Blocks Forged POST (Authenticated)
// ---------------------------------------------------------------------------
test.describe('T6: CSRF Blocks Forged Authenticated POST', () => {
  test('group create rejected without csrf_token', async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    const cookies = `NicTool=${sessionCookie}; NicTool_csrf=${csrfCookie}`;
    const { body } = await authPost(playwright, `${BASE}/group.cgi`, cookies,
      `nt_group_id=1&new=1&Create=Create&name=csrf_test_group&${GROUP_DEFAULTS}`);
    expect(body).toContain('CSRF validation failed');
  });
});

// ---------------------------------------------------------------------------
// T7: Normal CRUD Operations (Regression)
// ---------------------------------------------------------------------------
test.describe('T7: CRUD Regression', () => {
  test('full lifecycle: create group, zone, record; edit record; delete all', async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    const cookies = `NicTool=${sessionCookie}; NicTool_csrf=${csrfCookie}`;

    // --- Create a sub-group ---
    const groupName = `e2e_test_${Date.now()}`;
    await authPost(playwright, `${BASE}/group.cgi`, cookies,
      `nt_group_id=1&new=1&Create=Create&name=${groupName}&${GROUP_DEFAULTS}&csrf_token=${csrfCookie}`);

    // Fetch the group list to find the new group ID
    let { body } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=1`, cookies);
    const groupIdMatch = body.match(new RegExp(`nt_group_id=(\\d+)">${groupName}`));
    expect(groupIdMatch).toBeTruthy();
    const gid = groupIdMatch![1];

    // --- Create a zone ---
    const zoneName = `e2e-${Date.now()}.test`;
    await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=${gid}&new=1&Create=Create&zone=${zoneName}&mailaddr=admin.${zoneName}&description=e2e&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560&csrf_token=${csrfCookie}`);

    // Fetch zone list to find zone ID
    ({ body } = await authGet(playwright, `${BASE}/group_zones.cgi?nt_group_id=${gid}`, cookies));
    const zoneIdMatch = body.match(/nt_zone_id=(\d+)/);
    expect(zoneIdMatch).toBeTruthy();
    const zid = zoneIdMatch![1];

    // --- Create an A record ---
    ({ body } = await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&new_record=1&Create=Create&name=testhost&type=A&address=192.0.2.1&ttl=3600&csrf_token=${csrfCookie}`));
    expect(body).not.toContain('CSRF validation failed');
    expect(body).toContain('testhost');

    // Find record ID
    const recordIdMatch = body.match(/nt_zone_record_id=(\d+)/);
    expect(recordIdMatch).toBeTruthy();
    const rrid = recordIdMatch![1];

    // --- Edit the record ---
    ({ body } = await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&edit_record=${rrid}&Save=Save&name=testhost&type=A&address=192.0.2.2&ttl=3600&csrf_token=${csrfCookie}`));
    expect(body).not.toContain('CSRF validation failed');
    expect(body).toContain('192.0.2.2');

    // --- Delete the record (POST) ---
    ({ body } = await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&delete_record=${rrid}&csrf_token=${csrfCookie}`));
    expect(body).not.toContain('CSRF validation failed');

    // --- Delete the zone ---
    await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=${gid}&delete=1&zone_list=${zid}&csrf_token=${csrfCookie}`);

    // --- Delete the group (include csrf_token in query string) ---
    ({ body } = await authGet(playwright,
      `${BASE}/group.cgi?nt_group_id=1&delete=${gid}&csrf_token=${csrfCookie}`, cookies));
    expect(body).not.toContain(groupName);
  });
});

// ---------------------------------------------------------------------------
// T8: XSS in Login Error Message
// ---------------------------------------------------------------------------
test.describe('T8: XSS Protection', () => {
  test('script tag in message param is escaped or stripped', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const res = await ctx.get(`${BASE}/index.cgi?message=<script>alert(1)</script>`);
    const body = await res.text();
    expect(body).not.toContain('<script>alert(1)</script>');
    expect(body).not.toMatch(/<script>/i);
    await ctx.dispose();
  });
});

// ---------------------------------------------------------------------------
// T9: Delete Record is POST (not GET link)
// ---------------------------------------------------------------------------
test.describe('T9: Delete Record is POST', () => {
  test('delete button is inside a POST form with csrf_token', async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    const cookies = `NicTool=${sessionCookie}; NicTool_csrf=${csrfCookie}`;

    // Create a temp zone in root group
    const zoneName = `e2e-del-${Date.now()}.test`;
    await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=1&new=1&Create=Create&zone=${zoneName}&mailaddr=admin.${zoneName}&description=e2e&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560&csrf_token=${csrfCookie}`);

    // Find zone ID
    let { body } = await authGet(playwright, `${BASE}/group_zones.cgi?nt_group_id=1`, cookies);
    const zoneIdMatch = body.match(/nt_zone_id=(\d+)/);
    expect(zoneIdMatch).toBeTruthy();
    const zoneId = zoneIdMatch![1];

    // Create an A record
    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=1&nt_zone_id=${zoneId}&new_record=1&Create=Create&name=deltest&type=A&address=192.0.2.99&ttl=3600&csrf_token=${csrfCookie}`);

    // Fetch zone page and verify delete form structure
    ({ body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=1&nt_zone_id=${zoneId}`, cookies));

    expect(body).toContain('method="post"');
    expect(body).toContain('name="delete_record"');
    expect(body).toContain('name="csrf_token"');
    expect(body).not.toMatch(/<a\s[^>]*href="[^"]*delete_record/i);

    // Cleanup
    const recordIdMatch = body.match(/name="delete_record"\s+value="(\d+)"/);
    if (recordIdMatch) {
      await authPost(playwright, `${BASE}/zone.cgi`, cookies,
        `nt_group_id=1&nt_zone_id=${zoneId}&nt_zone_record_id=${recordIdMatch[1]}&delete_record=${recordIdMatch[1]}&csrf_token=${csrfCookie}`);
    }
    await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=1&delete=1&zone_list=${zoneId}&csrf_token=${csrfCookie}`);
  });
});

// ---------------------------------------------------------------------------
// T10: Password Field Attributes
// ---------------------------------------------------------------------------
test.describe('T10: Password Field', () => {
  test('password input has autocomplete="current-password"', async ({ page }) => {
    await page.goto(`${BASE}/index.cgi`);
    const pwInput = page.locator('input[name="password"]');
    await expect(pwInput).toHaveAttribute('type', 'password');
    await expect(pwInput).toHaveAttribute('autocomplete', 'current-password');
  });
});

// ---------------------------------------------------------------------------
// T11: CSP and Headers Don't Break the App (Browser-level)
// ---------------------------------------------------------------------------
test.describe('T11: Browser Enforcement', () => {
  test('login page renders without CSP violations', async ({ page }) => {
    const violations = collectViolations(page);
    await page.goto(`${BASE}/index.cgi`);
    await page.waitForTimeout(500);
    expect(violations).toEqual([]);
  });

  test('login, frameset, and navigation work without CSP violations', async ({ page }) => {
    const violations = collectViolations(page);

    await browserLogin(page);

    const frames = page.frames();
    expect(frames.length).toBeGreaterThan(1);

    const navFrame = frames.find((f) => f.url().includes('nav.cgi'));
    const bodyFrame = frames.find((f) => f.url().includes('group.cgi'));
    expect(navFrame).toBeTruthy();
    expect(bodyFrame).toBeTruthy();

    const bodyContent = await bodyFrame!.content();
    expect(bodyContent).toContain('NicTool');

    const zonesLink = bodyFrame!.locator('a:has-text("Zones")');
    if (await zonesLink.count() > 0) {
      await zonesLink.first().click();
      await page.waitForTimeout(1500);
    }

    const usersLink = bodyFrame!.locator('a:has-text("Users")');
    if (await usersLink.count() > 0) {
      await usersLink.first().click();
      await page.waitForTimeout(1500);
    }

    const logLink = bodyFrame!.locator('a:has-text("Log")');
    if (await logLink.count() > 0) {
      await logLink.first().click();
      await page.waitForTimeout(1500);
    }

    expect(violations).toEqual([]);
  });

  test('CRUD operations in browser produce no CSP violations', async ({ page }) => {
    const violations = collectViolations(page);

    await browserLogin(page);

    const bodyFrame = page.frames().find((f) => f.url().includes('group.cgi'));
    expect(bodyFrame).toBeTruthy();

    const newGroupLink = bodyFrame!.locator('a:has-text("New Sub-Group")');
    if (await newGroupLink.count() > 0) {
      await newGroupLink.first().click();
      await page.waitForTimeout(1500);
    }

    const zonesLink = bodyFrame!.locator('a:has-text("Zones")');
    if (await zonesLink.count() > 0) {
      await zonesLink.first().click();
      await page.waitForTimeout(1500);

      const zonesFrame = page.frames().find((f) => f.url().includes('group_zones.cgi'));
      if (zonesFrame) {
        const newZoneLink = zonesFrame.locator('a:has-text("New Zone")');
        if (await newZoneLink.count() > 0) {
          await newZoneLink.first().click();
          await page.waitForTimeout(1500);
        }
      }
    }

    expect(violations).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// T12: Apache denies dotfiles and source/config artifacts
// ---------------------------------------------------------------------------
test.describe('T12: Docroot Hardening', () => {
  const denied = [
    '/.git/config',
    '/.env',
    '/.htaccess',
    '/index.pm',
    '/nictoolclient.conf',
    '/nictoolclient.conf.dist',
    '/setup.pl',
    '/schema.sql',
    '/config.yaml',
    '/config.yml',
    '/notes.md',
    '/Makefile.PL.bak',
    '/index.cgi.swp',
    '/server.orig',
  ];

  for (const path of denied) {
    test(`denies ${path}`, async ({ playwright }) => {
      const ctx = await freshCtx(playwright);
      const res = await ctx.get(`${BASE}${path}`);
      // Apache returns 403 from the FilesMatch / DirectoryMatch deny rules,
      // regardless of whether the file actually exists in the docroot.
      expect(res.status()).toBe(403);
      await ctx.dispose();
    });
  }

  test('still serves index.cgi normally', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const res = await ctx.get(`${BASE}/index.cgi`);
    expect(res.status()).toBe(200);
    await ctx.dispose();
  });
});
