import { test, expect } from '@playwright/test';
import {
  BASE, GROUP_DEFAULTS, TEST_GID,
  apiLogin, authGet, authPost, deleteGroup, findInListing, uniqueName,
} from './helpers';

const ROOT_GROUPS = { cgi: 'group.cgi', gid: TEST_GID, idParam: 'nt_group_id' };

// Regression tests for the cross-process CSRF token race (#335, fixed in #353).
//
// The failing state is what a browser restart produces: the NicTool session
// cookie persists (+1M) while the session-scoped NicTool_csrf cookie is gone.
// The frameset then loads nav.cgi and group.cgi concurrently as separate CGI
// processes. Both requests leave with the same jar state, and neither
// response's Set-Cookie reaches the other's request. With per-process random
// tokens, each frame minted its own: the last Set-Cookie won and the other
// frame's forms were stranded with a dead token.
//
// Concurrency is not required to reproduce this — only the cookie
// non-exchange. Two sequential requests that share one initial jar state and
// do not feed responses back are byte-for-byte the same traffic, which is
// what makes this test deterministic rather than a race.

function formToken(body: string): string {
  const m = body.match(/name="csrf_token"\s+value="([^"]+)"/);
  return m ? m[1] : '';
}

function setCookieValue(res: { headersArray(): { name: string; value: string }[] }, name: string): string {
  for (const h of res.headersArray()) {
    if (h.name.toLowerCase() !== 'set-cookie') continue;
    const m = h.value.match(new RegExp(`^${name}=([^;]+)`));
    if (m && m[1]) return m[1];
  }
  return '';
}

test.describe('CSRF token agreement across CGI processes', () => {
  test('form from one frame survives the sibling frame\'s Set-Cookie', async ({ playwright }) => {
    const { sessionCookie } = await apiLogin(playwright);

    // Browser restart: session cookie survives, csrf cookie does not.
    const sessionOnly = `NicTool=${sessionCookie}`;

    // Frameset loads: same initial jar state, responses not exchanged.
    const bodyFrame = await authGet(playwright,
      `${BASE}/group.cgi?nt_group_id=${TEST_GID}&parent_group_id=${TEST_GID}&new=1`, sessionOnly);
    const navFrame  = await authGet(playwright, `${BASE}/nav.cgi?nt_group_id=${TEST_GID}`, sessionOnly);

    const groupFormToken = formToken(bodyFrame.body);
    expect(groupFormToken, 'group.cgi renders a csrf token').toMatch(/^[0-9a-f]{40}$/);

    const navCookieToken = setCookieValue(navFrame.res, 'NicTool_csrf');
    expect(navCookieToken, 'nav.cgi sets a csrf cookie').toMatch(/^[0-9a-f]{40}$/);

    // Both processes must arrive at the same token without coordinating.
    expect(navCookieToken).toBe(groupFormToken);

    // The user-visible symptom: submit group.cgi's form while the jar holds
    // nav.cgi's cookie (last Set-Cookie wins in a real browser).
    const name = uniqueName('e2e_csrf');
    const post = await authPost(playwright, `${BASE}/group.cgi`,
      `NicTool=${sessionCookie}; NicTool_csrf=${navCookieToken}`,
      `nt_group_id=${TEST_GID}&new=1&Create=Create&name=${name}&${GROUP_DEFAULTS}&csrf_token=${groupFormToken}`);
    expect(post.body).not.toContain('CSRF validation failed');

    // Prove the POST actually took effect, then clean up.
    const cookies = `NicTool=${sessionCookie}; NicTool_csrf=${navCookieToken}`;
    const gid = await findInListing(playwright, cookies, ROOT_GROUPS, name);
    expect(gid, 'created group appears in listing').toBeTruthy();
    await deleteGroup(playwright, cookies, TEST_GID, gid!);
  });

  test('form POST validates against the session, not the csrf cookie', async ({ playwright }) => {
    const { sessionCookie } = await apiLogin(playwright);
    const sessionOnly = `NicTool=${sessionCookie}`;

    // A rendered form whose csrf cookie has since vanished (cleared by the
    // browser, eaten by an extension, or simply never re-sent). The form
    // token is derived from the session, so the POST must stand on its own.
    const { body: page } = await authGet(playwright,
      `${BASE}/group.cgi?nt_group_id=${TEST_GID}&parent_group_id=${TEST_GID}&new=1`, sessionOnly);
    const token = formToken(page);
    expect(token, 'group.cgi renders a csrf token').toMatch(/^[0-9a-f]{40}$/);

    const name = uniqueName('e2e_csrf_nocookie');
    const post = await authPost(playwright, `${BASE}/group.cgi`, sessionOnly,
      `nt_group_id=${TEST_GID}&new=1&Create=Create&name=${name}&${GROUP_DEFAULTS}&csrf_token=${token}`);
    expect(post.body).not.toContain('CSRF validation failed');

    const gid = await findInListing(playwright, sessionOnly, ROOT_GROUPS, name);
    expect(gid, 'created group appears in listing').toBeTruthy();
    // deleteGroup reads the token from the jar's csrf cookie; the form token
    // is the same session-derived value, so lend it to the jar for cleanup.
    await deleteGroup(playwright, `${sessionOnly}; NicTool_csrf=${token}`, TEST_GID, gid!);
  });

  test('csrf cookie lifetime matches the session cookie', async ({ playwright }) => {
    const { setCookieHeaders } = await apiLogin(playwright);

    const csrf = setCookieHeaders.find(h => h.value.startsWith('NicTool_csrf='));
    const session = setCookieHeaders.find(h => h.value.startsWith('NicTool='));
    expect(csrf, 'login sets a csrf cookie').toBeTruthy();
    expect(session, 'login sets a session cookie').toBeTruthy();

    // As a browser-session cookie it evaporated on restart while the
    // month-long session cookie stayed valid, stranding every form. Both
    // cookies must now expire together — merely having an Expires of its own
    // is not enough, a shorter-lived csrf cookie still strands whatever
    // outlives it.
    const expiresAt = (h: { value: string }) => {
      const m = h.value.match(/expires=([^;]+)/i);
      return m ? Date.parse(m[1]) : NaN;
    };
    const csrfExpires = expiresAt(csrf!);
    const sessionExpires = expiresAt(session!);
    expect(csrfExpires, 'csrf cookie carries a parseable Expires').not.toBeNaN();
    expect(sessionExpires, 'session cookie carries a parseable Expires').not.toBeNaN();
    expect(Math.abs(csrfExpires - sessionExpires)).toBeLessThanOrEqual(60_000);
  });
});
