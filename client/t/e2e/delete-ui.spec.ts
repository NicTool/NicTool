import { test, expect } from '@playwright/test';
import {
  apiLogin, cookieString, authGet, authPost,
  createGroup, createZone, createRecord, createUser, createNameserver,
  deleteGroup, deleteZone, deleteRecord, deleteUser, deleteNameserver,
  uniqueName, uniqueNsName, extractCsrf, BASE,
} from './helpers';

// ---------------------------------------------------------------------------
// These tests verify that the delete icons rendered in the UI actually work.
// They fetch the listing page, extract the real delete link/form as rendered
// in the HTML, follow it exactly as the browser would, and confirm the delete
// succeeds (no CSRF error, entity is removed).
//
// This catches the bug where <a href> trash-icon links omit csrf_token.
// ---------------------------------------------------------------------------

// ---- Helpers to extract delete links/forms from rendered HTML ----

/** Extract the trash-icon delete href for a group from group.cgi HTML */
function extractGroupDeleteHref(html: string, gid: string): string | null {
  // Pattern: <a href="group.cgi?nt_group_id=PARENT&amp;delete=GID" ...><img ...trash.gif...>
  const re = new RegExp(`<a\\s+href="(group\\.cgi\\?[^"]*delete=${gid}[^"]*)"[^>]*>\\s*<img[^>]*trash\\.gif`);
  const m = html.match(re);
  return m ? m[1].replace(/&amp;/g, '&') : null;
}

/** Extract the trash-icon delete href for a user from group_users.cgi HTML */
function extractUserDeleteHref(html: string, uid: string): string | null {
  const re = new RegExp(`<a\\s+href="(group_users\\.cgi\\?[^"]*delete=1[^"]*obj_list=${uid}[^"]*)"[^>]*>\\s*<img[^>]*trash\\.gif`);
  const m = html.match(re);
  if (m) return m[1].replace(/&amp;/g, '&');
  // Try alternate order: obj_list before delete
  const re2 = new RegExp(`<a\\s+href="(group_users\\.cgi\\?[^"]*obj_list=${uid}[^"]*delete=1[^"]*)"[^>]*>\\s*<img[^>]*trash\\.gif`);
  const m2 = html.match(re2);
  return m2 ? m2[1].replace(/&amp;/g, '&') : null;
}

/** Extract the trash-icon delete href for a nameserver from group_nameservers.cgi HTML */
function extractNameserverDeleteHref(html: string, nsid: string): string | null {
  const re = new RegExp(`<a\\s+href="(group_nameservers\\.cgi\\?[^"]*delete=1[^"]*nt_nameserver_id=${nsid}[^"]*)"[^>]*>\\s*<img[^>]*trash\\.gif`);
  const m = html.match(re);
  if (m) return m[1].replace(/&amp;/g, '&');
  const re2 = new RegExp(`<a\\s+href="(group_nameservers\\.cgi\\?[^"]*nt_nameserver_id=${nsid}[^"]*delete=1[^"]*)"[^>]*>\\s*<img[^>]*trash\\.gif`);
  const m2 = html.match(re2);
  return m2 ? m2[1].replace(/&amp;/g, '&') : null;
}

/** Extract the trash-icon delete href for a zone from group_zones.cgi HTML */
function extractZoneDeleteHref(html: string, zid: string): string | null {
  const re = new RegExp(`<a\\s+href="(group_zones\\.cgi\\?[^"]*delete=1[^"]*zone_list=${zid}[^"]*)"[^>]*>\\s*<img[^>]*trash\\.gif`);
  const m = html.match(re);
  if (m) return m[1].replace(/&amp;/g, '&');
  const re2 = new RegExp(`<a\\s+href="(group_zones\\.cgi\\?[^"]*zone_list=${zid}[^"]*delete=1[^"]*)"[^>]*>\\s*<img[^>]*trash\\.gif`);
  const m2 = html.match(re2);
  return m2 ? m2[1].replace(/&amp;/g, '&') : null;
}

/** Extract the delete form for a record from zone.cgi HTML */
function extractRecordDeleteForm(html: string, rrid: string): { action: string; fields: Record<string, string> } | null {
  // Look for a form containing delete_record with the given rrid
  const formRe = new RegExp(
    `<form[^>]*method="post"[^>]*action="([^"]*)"[^>]*>([\\s\\S]*?)</form>`,
    'gi'
  );
  let match;
  while ((match = formRe.exec(html)) !== null) {
    const [, action, formBody] = match;
    if (formBody.includes(`name="delete_record"`) && formBody.includes(`value="${rrid}"`)) {
      const fields: Record<string, string> = {};
      const inputRe = /name="([^"]+)"\s+value="([^"]*)"/g;
      let im;
      while ((im = inputRe.exec(formBody)) !== null) {
        fields[im[1]] = im[2];
      }
      // Also check value="..." name="..." order
      const inputRe2 = /value="([^"]*)"\s+name="([^"]+)"/g;
      while ((im = inputRe2.exec(formBody)) !== null) {
        if (!fields[im[2]]) fields[im[2]] = im[1];
      }
      return { action: action.replace(/&amp;/g, '&'), fields };
    }
  }
  return null;
}


test.describe('Delete via UI trash icon', () => {
  let cookies: string;
  let csrfCookie: string;

  test.beforeAll(async ({ playwright }) => {
    const login = await apiLogin(playwright);
    cookies = cookieString(login.sessionCookie, login.csrfCookie);
    csrfCookie = login.csrfCookie;
  });

  test('delete group via rendered trash icon link', async ({ playwright }) => {
    const gid = await createGroup(playwright, cookies, 1);

    // Fetch the group listing page as the browser would
    const { body } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=1`, cookies);

    // Extract the actual delete link from the HTML
    const href = extractGroupDeleteHref(body, gid);
    expect(href, 'trash icon link should exist for the group').toBeTruthy();

    // The link MUST contain csrf_token for CSRF protection to pass
    expect(href, 'delete link must include csrf_token').toContain('csrf_token');

    // Follow the link exactly as the browser would
    const { body: afterBody, res } = await authGet(playwright, `${BASE}/${href}`, cookies);

    // Should NOT show CSRF error
    expect(afterBody).not.toContain('CSRF validation failed');

    // Group should be gone from listing
    const { body: listBody } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=1`, cookies);
    expect(listBody).not.toContain(`nt_group_id=${gid}"`);
  });

  test('delete user via rendered trash icon link', async ({ playwright }) => {
    const gid = await createGroup(playwright, cookies, 1);
    const username = uniqueName('deluiusr');
    const uid = await createUser(playwright, cookies, gid, { username });

    // Fetch the user listing page
    const { body } = await authGet(playwright, `${BASE}/group_users.cgi?nt_group_id=${gid}`, cookies);

    // Extract the actual delete link
    const href = extractUserDeleteHref(body, uid);
    expect(href, 'trash icon link should exist for the user').toBeTruthy();
    expect(href, 'delete link must include csrf_token').toContain('csrf_token');

    // Follow the link
    const { body: afterBody } = await authGet(playwright, `${BASE}/${href}`, cookies);
    expect(afterBody).not.toContain('CSRF validation failed');

    // User should be gone
    const { body: listBody } = await authGet(playwright, `${BASE}/group_users.cgi?nt_group_id=${gid}`, cookies);
    expect(listBody).not.toContain(username);

    // Cleanup
    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('delete nameserver via rendered trash icon link', async ({ playwright }) => {
    // Create nameserver in root group (gid=1) which has usable nameservers
    const nsName = uniqueNsName('deluins') + '.example.com.';
    const nsid = await createNameserver(playwright, cookies, 1, { name: nsName });

    // Fetch the nameserver listing page
    const { body } = await authGet(playwright, `${BASE}/group_nameservers.cgi?nt_group_id=1`, cookies);

    // Extract the actual delete link
    const href = extractNameserverDeleteHref(body, nsid);
    expect(href, 'trash icon link should exist for the nameserver').toBeTruthy();
    expect(href, 'delete link must include csrf_token').toContain('csrf_token');

    // Follow the link
    const { body: afterBody } = await authGet(playwright, `${BASE}/${href}`, cookies);
    expect(afterBody).not.toContain('CSRF validation failed');

    // Nameserver should be gone
    const { body: listBody } = await authGet(playwright, `${BASE}/group_nameservers.cgi?nt_group_id=1`, cookies);
    expect(listBody).not.toContain(nsName);
  });

  test('delete zone via rendered trash icon link', async ({ playwright }) => {
    const gid = await createGroup(playwright, cookies, 1);
    const zoneName = `${uniqueName('deluizn')}.test`;
    const zid = await createZone(playwright, cookies, gid, zoneName);

    // Fetch the zone listing page
    const { body } = await authGet(playwright, `${BASE}/group_zones.cgi?nt_group_id=${gid}`, cookies);

    // Extract the actual delete link
    const href = extractZoneDeleteHref(body, zid);
    expect(href, 'trash icon link should exist for the zone').toBeTruthy();
    expect(href, 'delete link must include csrf_token').toContain('csrf_token');

    // Follow the link
    const { body: afterBody } = await authGet(playwright, `${BASE}/${href}`, cookies);
    expect(afterBody).not.toContain('CSRF validation failed');

    // Zone should be gone
    const { body: listBody } = await authGet(playwright, `${BASE}/group_zones.cgi?nt_group_id=${gid}`, cookies);
    expect(listBody).not.toContain(zoneName);

    // Cleanup
    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('delete record via rendered trash form submit', async ({ playwright }) => {
    const gid = await createGroup(playwright, cookies, 1);
    const zoneName = `${uniqueName('deluirr')}.test`;
    const zid = await createZone(playwright, cookies, gid, zoneName);
    const rrid = await createRecord(playwright, cookies, gid, zid, {
      name: 'deltest', type: 'A', address: '10.0.0.99',
    });

    // Fetch the zone detail page (which lists records)
    const { body } = await authGet(playwright,
      `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);

    // Extract the delete form for this record
    const form = extractRecordDeleteForm(body, rrid);
    expect(form, 'delete form should exist for the record').toBeTruthy();
    expect(form!.fields, 'delete form must include csrf_token').toHaveProperty('csrf_token');
    expect(form!.fields['csrf_token']).toBeTruthy();

    // Submit the form exactly as the browser would
    const formData = Object.entries(form!.fields).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join('&');
    const { body: afterBody } = await authPost(playwright,
      `${BASE}/${form!.action}`, cookies, formData);

    expect(afterBody).not.toContain('CSRF validation failed');

    // Record should be gone
    const { body: listBody } = await authGet(playwright,
      `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(listBody).not.toContain(`nt_zone_record_id=${rrid}`);

    // Cleanup
    await deleteZone(playwright, cookies, gid, zid);
    await deleteGroup(playwright, cookies, 1, gid);
  });
});
