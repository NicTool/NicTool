import { test, expect } from '@playwright/test';
import {
  apiLogin, cookieString, authGet, authPost,
  createGroup, createZone, createRecord, createUser,
  deleteGroup, deleteZone, deleteUser,
  findInListing, uniqueName, extractCsrf, BASE, TEST_GID,
} from './helpers';

// ---------------------------------------------------------------------------
// Regression tests for #354: the list-view trash icons got csrf_token in #335,
// but the Delete links in the options menus rendered above them did not, so
// every Delete in a nav header failed CSRF validation. delete-ui.spec.ts
// covers the trash icons; these tests cover the options menus, and a final
// sweep asserts that NO rendered page carries a destructive GET link without
// a csrf_token — so the next missed spot fails here even if it is in a menu
// none of the targeted tests know about.
// ---------------------------------------------------------------------------

/** All hrefs in the HTML that trigger a destructive action via GET. */
function destructiveHrefs(html: string): string[] {
  const out: string[] = [];
  const re = /href="([^"]+)"/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    const href = m[1].replace(/&amp;/g, '&');
    if (/[?&](delete|deletedelegate|delete_record|logout)=/.test(href)) out.push(href);
  }
  return out;
}

/** Destructive hrefs that are missing the csrf_token parameter. */
function hrefsMissingToken(html: string): string[] {
  return destructiveHrefs(html).filter(h => !/[?&]csrf_token=/.test(h));
}

/** First destructive href matching every given fragment, &amp;-decoded. */
function findHref(html: string, ...fragments: string[]): string | null {
  return destructiveHrefs(html).find(h => fragments.every(f => h.includes(f))) || null;
}

test.describe('Options-menu delete links carry CSRF (#354)', () => {
  let cookies: string;
  let csrfToken: string;

  test.beforeAll(async ({ playwright }) => {
    const login = await apiLogin(playwright);
    cookies = cookieString(login.sessionCookie, login.csrfCookie);
    csrfToken = extractCsrf(cookies);
  });

  test('group tree Delete link works', async ({ playwright }) => {
    const groupName = uniqueName('csrflnk');
    const gid = await createGroup(playwright, cookies, TEST_GID, groupName);

    // The group tree is rendered in the nav header of the group's own pages.
    const { body } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${gid}`, cookies);

    const href = findHref(body, 'group.cgi?', `delete=${gid}`);
    expect(href, 'group tree should render a Delete link').toBeTruthy();
    expect(href, 'Delete link must include csrf_token').toContain('csrf_token=');

    const { body: after } = await authGet(playwright, `${BASE}/${href}`, cookies);
    expect(after).not.toContain('CSRF validation failed');

    expect(await findInListing(playwright, cookies,
      { cgi: 'group.cgi', gid: TEST_GID, idParam: 'nt_group_id' }, groupName)).toBeNull();
  });

  test('zone options menu Delete link works', async ({ playwright }) => {
    const gid = await createGroup(playwright, cookies, TEST_GID);
    const zid = await createZone(playwright, cookies, gid);

    // The options menu is rendered above the zone detail view.
    const { body } = await authGet(playwright,
      `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);

    const href = findHref(body, 'group_zones.cgi?', `zone_list=${zid}`, 'delete=1');
    expect(href, 'zone options menu should render a Delete link').toBeTruthy();
    expect(href, 'Delete link must include csrf_token').toContain('csrf_token=');

    const { body: after } = await authGet(playwright, `${BASE}/${href}`, cookies);
    expect(after).not.toContain('CSRF validation failed');

    const { body: list } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${gid}`, cookies);
    expect(list).not.toContain(`nt_zone_id=${zid}"`);

    await deleteGroup(playwright, cookies, TEST_GID, gid);
  });

  test('user page Delete link works', async ({ playwright }) => {
    const gid = await createGroup(playwright, cookies, TEST_GID);
    const username = uniqueName('csrflnk');
    const uid = await createUser(playwright, cookies, gid, { username });

    const { body } = await authGet(playwright,
      `${BASE}/user.cgi?nt_group_id=${gid}&nt_user_id=${uid}`, cookies);

    const href = findHref(body, 'group_users.cgi?', `obj_list=${uid}`, 'delete=1');
    expect(href, 'user page should render a Delete link').toBeTruthy();
    expect(href, 'Delete link must include csrf_token').toContain('csrf_token=');

    const { body: after } = await authGet(playwright, `${BASE}/${href}`, cookies);
    expect(after).not.toContain('CSRF validation failed');

    const { body: list } = await authGet(playwright,
      `${BASE}/group_users.cgi?nt_group_id=${gid}`, cookies);
    expect(list).not.toContain(username);

    await deleteGroup(playwright, cookies, TEST_GID, gid);
  });

  test('zone Remove Delegation link works', async ({ playwright }) => {
    const groupName = uniqueName('csrfdlg');
    const childGid = await createGroup(playwright, cookies, TEST_GID, groupName);
    const zid = await createZone(playwright, cookies, TEST_GID);

    // Remove Delegation only renders for a user whose own group received the
    // delegation, so create a user inside the child group and log in as them.
    // Users outside the default group authenticate as username@groupname.
    const username = uniqueName('csrfdel');
    const password = 'Valid#E2e#Pass44';
    const uid = await createUser(playwright, cookies, childGid, { username, password });
    await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Save=Save&group_list=${childGid}&obj_list=${zid}&type=zone&perm_write=1&perm_delete=1&perm_delegate=0&zone_perm_add_records=1&zone_perm_delete_records=1&csrf_token=${csrfToken}`);

    const childLogin = await apiLogin(playwright, `${username}@${groupName}`, password);
    const childCookies = cookieString(childLogin.sessionCookie, childLogin.csrfCookie);

    const { body } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${childGid}`, childCookies);

    const href = findHref(body, 'group_zones.cgi?', `nt_zone_id=${zid}`, 'deletedelegate=1');
    expect(href, 'delegated zone should render a Remove Delegation link').toBeTruthy();
    expect(href, 'Remove Delegation link must include csrf_token').toContain('csrf_token=');

    const { body: after } = await authGet(playwright, `${BASE}/${href}`, childCookies);
    expect(after).not.toContain('CSRF validation failed');

    // The delegation is gone from the child group's zone list.
    const { body: list } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${childGid}`, childCookies);
    expect(list).not.toContain(`nt_zone_id=${zid}"`);

    await deleteZone(playwright, cookies, TEST_GID, zid);
    await deleteUser(playwright, cookies, childGid, uid);
    await deleteGroup(playwright, cookies, TEST_GID, childGid);
  });

  test('no rendered page carries a tokenless destructive link or POST form', async ({ playwright }) => {
    // Build enough state that every options menu, list view, edit form, and
    // popup renders its markup, then sweep the pages a browser session
    // touches. Two invariants: destructive GET links carry csrf_token in the
    // URL, and every POST form embeds a well-formed csrf_token field — a form
    // without one renders fine and then dies in verify_csrf on submit, which
    // is precisely how #354 escaped the list-view fixes.
    const gid = await createGroup(playwright, cookies, TEST_GID);
    const childGid = await createGroup(playwright, cookies, gid);
    const username = uniqueName('csrfswp');
    const uid = await createUser(playwright, cookies, gid, { username });
    const zid = await createZone(playwright, cookies, gid);
    const rrid = await createRecord(playwright, cookies, gid, zid, {
      name: 'sweep', type: 'A', address: '192.0.2.53',
    });
    await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Save=Save&group_list=${childGid}&obj_list=${zid}&type=zone&perm_write=1&perm_delete=1&perm_delegate=1&zone_perm_add_records=1&zone_perm_delete_records=1&csrf_token=${csrfToken}`);
    await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Save=Save&group_list=${childGid}&obj_list=${rrid}&type=record&perm_write=1&perm_delete=1&perm_delegate=0&csrf_token=${csrfToken}`);

    const pages = [
      // list and detail views
      `group.cgi?nt_group_id=${TEST_GID}`,
      `group.cgi?nt_group_id=${gid}`,
      `nav.cgi?nt_group_id=${gid}`,
      `group_users.cgi?nt_group_id=${gid}`,
      `user.cgi?nt_group_id=${gid}&nt_user_id=${uid}`,
      `group_zones.cgi?nt_group_id=${gid}`,
      `group_zones.cgi?nt_group_id=${childGid}`,
      `group_nameservers.cgi?nt_group_id=${TEST_GID}`,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`,
      `zone.cgi?nt_group_id=${childGid}&nt_zone_id=${zid}`,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}&type=record&nt_zone_record_id=${rrid}`,
      `zone.cgi?nt_group_id=${childGid}&nt_zone_id=${zid}&type=record&nt_zone_record_id=${rrid}`,
      `group_log.cgi?nt_group_id=${gid}`,
      // new/edit forms
      `group.cgi?nt_group_id=${TEST_GID}&new=1`,
      `group.cgi?nt_group_id=${gid}&edit=1`,
      `group_users.cgi?nt_group_id=${gid}&new=1`,
      `group_users.cgi?nt_group_id=${gid}&edit=1&nt_user_id=${uid}`,
      `group_nameservers.cgi?nt_group_id=${TEST_GID}&new=1`,
      `group_zones.cgi?nt_group_id=${gid}&new=1`,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}&edit_zone=1`,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}&new_record=1`,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}&edit_record=1&nt_zone_record_id=${rrid}`,
      `zones.cgi?nt_group_id=${TEST_GID}`,
      // popup windows, including the delegation edit/remove second step
      `delegate_zones.cgi?obj_list=${zid}`,
      `delegate_zones.cgi?obj_list=${zid}&type=zone&edit=1&nt_group_id=${childGid}`,
      `delegate_zones.cgi?obj_list=${zid}&type=zone&delete=1&nt_group_id=${childGid}`,
      `move_zones.cgi?obj_list=${zid}`,
      `move_users.cgi?obj_list=${uid}`,
    ];

    const missing: string[] = [];
    let destructiveSeen = 0;
    let formsSeen = 0;
    for (const path of pages) {
      const { body } = await authGet(playwright, `${BASE}/${path}`, cookies);
      destructiveSeen += destructiveHrefs(body).length;
      for (const href of hrefsMissingToken(body)) {
        missing.push(`${path}: ${href}`);
      }
      for (const form of body.split(/(?=<form\b)/i)) {
        if (!/^<form\b[^>]*\bmethod=["']?post/i.test(form)) continue;
        formsSeen++;
        const block = form.slice(0, form.search(/<\/form/i) + 1 || undefined);
        if (!/<input[^>]*name="csrf_token"[^>]*value="[0-9a-f]{40}"/.test(block)) {
          missing.push(`${path}: POST form ${form.slice(0, 80).replace(/\s+/g, ' ')}`);
        }
      }
    }

    expect(missing, `tokenless destructive markup:\n${missing.join('\n')}`).toHaveLength(0);
    // Guard against a vacuous pass: the sweep must actually have seen both.
    expect(destructiveSeen).toBeGreaterThan(5);
    expect(formsSeen).toBeGreaterThan(10);

    await deleteZone(playwright, cookies, gid, zid);
    await deleteUser(playwright, cookies, gid, uid);
    await deleteGroup(playwright, cookies, gid, childGid);
    await deleteGroup(playwright, cookies, TEST_GID, gid);
  });
});
