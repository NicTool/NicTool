import { test, expect } from '@playwright/test';
import {
  BASE, USERNAME, PASSWORD, TEST_GID,
  freshCtx, getLoginCsrf, apiLogin, authGet, cookieString,
} from './helpers';

test.describe('Authentication', () => {
  test('successful login returns frameset with session cookie', async ({ playwright }) => {
    const { sessionCookie, body } = await apiLogin(playwright);
    expect(sessionCookie).toBeTruthy();
    expect(sessionCookie.length).toBeGreaterThan(0);
    expect(body.toLowerCase()).toContain('<frameset');
  });

  test('wrong password shows error, no session cookie', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const { csrfToken, csrfCookie } = await getLoginCsrf(ctx);

    const res = await ctx.post(`${BASE}/index.cgi`, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': `NicTool_csrf=${csrfCookie}`,
      },
      data: `username=${USERNAME}&password=wrongpassword&login=Enter&csrf_token=${csrfToken}`,
    });

    const body = await res.text();
    const setCookies = res.headersArray().filter(h => h.name.toLowerCase() === 'set-cookie');
    const sessionHeader = setCookies.find(h => /^NicTool=[^;]/.test(h.value) && !h.value.startsWith('NicTool_csrf'));

    expect(body.toLowerCase()).not.toContain('<frameset');
    expect(body.toLowerCase()).toContain('invalid');
    expect(sessionHeader).toBeFalsy();
    await ctx.dispose();
  });

  test('empty username and password shows error', async ({ playwright }) => {
    const ctx = await freshCtx(playwright);
    const { csrfToken, csrfCookie } = await getLoginCsrf(ctx);

    const res = await ctx.post(`${BASE}/index.cgi`, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': `NicTool_csrf=${csrfCookie}`,
      },
      data: `username=&password=&login=Enter&csrf_token=${csrfToken}`,
    });

    const body = await res.text();
    expect(body.toLowerCase()).not.toContain('<frameset');
    await ctx.dispose();
  });

  test('logout invalidates session', async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    const cookies = cookieString(sessionCookie, csrfCookie);

    // Verify session works first
    const { body: before } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${TEST_GID}`, cookies);
    expect(before).toContain('NicTool');

    // Logout
    await authGet(playwright,
      `${BASE}/index.cgi?logout=1&csrf_token=${csrfCookie}`, cookies);

    // Session should no longer work - should get login page or redirect
    const { body: after } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${TEST_GID}`, cookies);
    expect(after.toLowerCase()).toMatch(/login|username|password|error|session/);
  });

  test('logout rejects a missing or forged csrf_token', async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    const cookies = cookieString(sessionCookie, csrfCookie);

    // The nav bar's logout link only renders for an authenticated request, so
    // it marks a surviving session. Do not assert on 'NicTool' here: the login
    // page is titled that too, which would pass whether or not logout happened.
    await authGet(playwright, `${BASE}/index.cgi?logout=1`, cookies);
    const { body: afterMissing } = await authGet(playwright,
      `${BASE}/group.cgi?nt_group_id=${TEST_GID}`, cookies);
    expect(afterMissing).toContain('logout=1');

    await authGet(playwright,
      `${BASE}/index.cgi?logout=1&csrf_token=${'f'.repeat(40)}`, cookies);
    const { body: afterForged } = await authGet(playwright,
      `${BASE}/group.cgi?nt_group_id=${TEST_GID}`, cookies);
    expect(afterForged).toContain('logout=1');
  });

  test('invalid session cookie gets no authenticated content', async ({ playwright }) => {
    const cookies = cookieString('invalidsessioncookie123', 'invalidcsrf123');
    const { body } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${TEST_GID}`, cookies);
    expect(body.toLowerCase()).toMatch(/login|username|password|error|session/);
  });

  test('session persists across multiple requests', async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    const cookies = cookieString(sessionCookie, csrfCookie);

    const { body: r1 } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${TEST_GID}`, cookies);
    expect(r1).toContain('NicTool');

    const { body: r2 } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${TEST_GID}`, cookies);
    expect(r2).toContain('NicTool');

    const { body: r3 } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${TEST_GID}`, cookies);
    expect(r3).toContain('NicTool');
  });
});
