import { test, expect } from '@playwright/test';
import {
  BASE, GROUP_DEFAULTS,
  apiLogin, authGet, authPost, deleteGroup, uniqueName,
} from './helpers';

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
    const bodyFrame = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=1`, sessionOnly);
    const navFrame  = await authGet(playwright, `${BASE}/nav.cgi?nt_group_id=1`, sessionOnly);

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
      `nt_group_id=1&new=1&Create=Create&name=${name}&${GROUP_DEFAULTS}&csrf_token=${groupFormToken}`);
    expect(post.body).not.toContain('CSRF validation failed');

    // Prove the POST actually took effect, then clean up.
    const cookies = `NicTool=${sessionCookie}; NicTool_csrf=${navCookieToken}`;
    const { body: listing } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=1`, cookies);
    const gid = listing.match(new RegExp(`nt_group_id=(\\d+)">${name}`))?.[1];
    expect(gid, 'created group appears in listing').toBeTruthy();
    await deleteGroup(playwright, cookies, 1, gid!);
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
