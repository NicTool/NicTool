import { test, expect } from '@playwright/test';
import {
  authGet, authPost,
  createGroup, createZone, createRecord, createUser, createNameserver,
  deleteGroup, deleteZone,
  exactListing, findInListing,
  uniqueName, uniqueNsName, BASE,
  apiCookies, zonePage,
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

/**
 * The trash-icon delete href in a listing: a link to `cgi` carrying every
 * param, in either order, wrapped around trash.gif.
 */
function trashHref(html: string, cgi: string, ...params: string[]): string | null {
  const orders = params.length > 1 ? [params, [...params].reverse()] : [params];
  for (const order of orders) {
    const re = new RegExp(`<a\\s+href="(${cgi.replace('.', '\\.')}\\?[^"]*${order.join('[^"]*')}[^"]*)"[^>]*>\\s*<img[^>]*trash\\.gif`);
    const m = html.match(re);
    if (m) return m[1].replace(/&amp;/g, '&');
  }
  return null;
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

  test.beforeAll(async ({ playwright }) => {
    cookies = await apiCookies(playwright);
  });

  test('delete group via rendered trash icon link', async ({ playwright }) => {
    const groupName = uniqueName('deluigrp');
    const gid = await createGroup(playwright, cookies, 1, groupName);
    const body = await exactListing(playwright, cookies, 'group.cgi', 1, groupName);

    // Extract the actual delete link from the HTML
    const href = trashHref(body, 'group.cgi', `delete=${gid}`);
    expect(href, 'trash icon link should exist for the group').toBeTruthy();

    // The link MUST contain csrf_token for CSRF protection to pass
    expect(href, 'delete link must include csrf_token').toContain('csrf_token');

    // Follow the link exactly as the browser would
    const { body: afterBody, res } = await authGet(playwright, `${BASE}/${href}`, cookies);

    // Should NOT show CSRF error
    expect(afterBody).not.toContain('CSRF validation failed');

    // Group should be gone from listing
    expect(await findInListing(playwright, cookies,
      { cgi: 'group.cgi', gid: 1, idParam: 'nt_group_id' },
      groupName)).toBeNull();
  });

  test('delete user via rendered trash icon link', async ({ playwright }) => {
    const gid = await createGroup(playwright, cookies, 1);
    const username = uniqueName('deluiusr');
    const uid = await createUser(playwright, cookies, gid, { username });

    // Fetch the user listing page
    const { body } = await authGet(playwright, `${BASE}/group_users.cgi?nt_group_id=${gid}`, cookies);

    // Extract the actual delete link
    const href = trashHref(body, 'group_users.cgi', 'delete=1', `obj_list=${uid}`);
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

    const body = await exactListing(playwright, cookies,
      'group_nameservers.cgi', 1, nsName);

    // Extract the actual delete link
    const href = trashHref(body, 'group_nameservers.cgi', 'delete=1', `nt_nameserver_id=${nsid}`);
    expect(href, 'trash icon link should exist for the nameserver').toBeTruthy();
    expect(href, 'delete link must include csrf_token').toContain('csrf_token');

    // Follow the link
    const { body: afterBody } = await authGet(playwright, `${BASE}/${href}`, cookies);
    expect(afterBody).not.toContain('CSRF validation failed');

    // Nameserver should be gone
    expect(await findInListing(playwright, cookies,
      { cgi: 'group_nameservers.cgi', gid: 1, idParam: 'nt_nameserver_id' },
      nsName)).toBeNull();
  });

  test('delete zone via rendered trash icon link', async ({ playwright }) => {
    const gid = await createGroup(playwright, cookies, 1);
    const zoneName = `${uniqueName('deluizn')}.test`;
    const zid = await createZone(playwright, cookies, gid, zoneName);

    // Fetch the zone listing page
    const { body } = await authGet(playwright, `${BASE}/group_zones.cgi?nt_group_id=${gid}`, cookies);

    // Extract the actual delete link
    const href = trashHref(body, 'group_zones.cgi', 'delete=1', `zone_list=${zid}`);
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
    const body = await zonePage(playwright, cookies, gid, zid);

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
