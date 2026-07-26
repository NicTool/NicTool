import { test, expect } from '@playwright/test';
import {
  apiLogin, cookieString, authGet, authPost,
  createGroup, createZone, createRecord, createUser, createNameserver,
  deleteGroup, deleteZone, deleteUser, deleteNameserver,
  uniqueName, uniqueNsName, extractCsrf, BASE,
} from './helpers';

// ---------------------------------------------------------------------------
// The other half of the CSRF pincer. csrf-links.spec.ts proves every rendered
// link and form carries a token; this file proves every mutating endpoint
// refuses to act without one. A handler someone forgets to guard passes the
// rendering sweep (its form dutifully carries a token) but fails here.
//
// Every request below rides a real session — exactly what a cross-site
// forgery has (the browser attaches cookies) and doesn't have (the token).
// Some endpoints answer with a CSRF error page, some silently skip the
// action, so the one assertion made everywhere is the one that matters:
// the state did not change.
// ---------------------------------------------------------------------------

test.describe('Mutating endpoints reject requests without a csrf_token', () => {
  let cookies: string;
  let gid: string;        // scratch group under root
  let childGid: string;   // child of gid, receives the delegation
  let uid: string;
  let zid: string;
  let rrid: string;
  let nsid: string;
  let username: string;
  let zoneName: string;
  let nsName: string;

  test.beforeAll(async ({ playwright }) => {
    const login = await apiLogin(playwright);
    cookies = cookieString(login.sessionCookie, login.csrfCookie);

    gid = await createGroup(playwright, cookies, 1);
    childGid = await createGroup(playwright, cookies, gid);
    username = uniqueName('csrfenf');
    uid = await createUser(playwright, cookies, gid, { username });
    zoneName = `${uniqueName('csrfenf')}.test`;
    zid = await createZone(playwright, cookies, gid, zoneName);
    rrid = await createRecord(playwright, cookies, gid, zid, {
      name: 'enforce', type: 'A', address: '192.0.2.99',
    });
    nsName = uniqueNsName('csrfenf') + '.example.com.';
    nsid = await createNameserver(playwright, cookies, 1, { name: nsName });
    await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Save=Save&group_list=${childGid}&obj_list=${zid}&type=zone&perm_write=1&perm_delete=1&perm_delegate=1&zone_perm_add_records=1&zone_perm_delete_records=1&csrf_token=${extractCsrf(cookies)}`);
  });

  test.afterAll(async ({ playwright }) => {
    const token = extractCsrf(cookies);
    await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Remove=Remove&nt_group_id=${childGid}&nt_zone_id=${zid}&type=zone&csrf_token=${token}`);
    await deleteZone(playwright, cookies, gid, zid);
    await deleteNameserver(playwright, cookies, 1, nsid);
    await deleteUser(playwright, cookies, gid, uid);
    await deleteGroup(playwright, cookies, gid, childGid);
    await deleteGroup(playwright, cookies, 1, gid);
  });

  async function pageHas(playwright: any, path: string, needle: string): Promise<boolean> {
    const { body } = await authGet(playwright, `${BASE}/${path}`, cookies);
    return body.includes(needle);
  }

  // --- deletes ---

  test('group delete via GET', async ({ playwright }) => {
    await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${gid}&delete=${childGid}`, cookies);
    expect(await pageHas(playwright, `group.cgi?nt_group_id=${gid}`, `nt_group_id=${childGid}"`)).toBe(true);
  });

  test('group delete with a wrong token', async ({ playwright }) => {
    const forged = 'deadbeef'.repeat(5);
    await authGet(playwright,
      `${BASE}/group.cgi?nt_group_id=${gid}&delete=${childGid}&csrf_token=${forged}`, cookies);
    expect(await pageHas(playwright, `group.cgi?nt_group_id=${gid}`, `nt_group_id=${childGid}"`)).toBe(true);
  });

  test('zone delete via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=${gid}&delete=1&zone_list=${zid}`);
    expect(await pageHas(playwright, `group_zones.cgi?nt_group_id=${gid}`, zoneName)).toBe(true);
  });

  test('user delete via GET', async ({ playwright }) => {
    await authGet(playwright,
      `${BASE}/group_users.cgi?nt_group_id=${gid}&delete=1&obj_list=${uid}`, cookies);
    expect(await pageHas(playwright, `group_users.cgi?nt_group_id=${gid}`, username)).toBe(true);
  });

  test('nameserver delete via GET', async ({ playwright }) => {
    await authGet(playwright,
      `${BASE}/group_nameservers.cgi?nt_group_id=1&delete=1&nt_nameserver_id=${nsid}`, cookies);
    expect(await pageHas(playwright, `group_nameservers.cgi?nt_group_id=1`, nsName)).toBe(true);
  });

  test('record delete via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&delete_record=${rrid}`);
    expect(await pageHas(playwright,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, `nt_zone_record_id=${rrid}`)).toBe(true);
  });

  // --- creates ---

  test('group create via POST', async ({ playwright }) => {
    const name = uniqueName('csrfforged');
    await authPost(playwright, `${BASE}/group.cgi`, cookies,
      `nt_group_id=1&new=1&Create=Create&name=${name}`);
    // The search page echoes the searched value in its own form, so look for
    // the name as rendered link text, which only a real row produces.
    expect(await pageHas(playwright,
      `group.cgi?nt_group_id=1&quick_search=1&search_value=${name}&exact_match=1`, `>${name}<`)).toBe(false);
  });

  test('zone create via POST', async ({ playwright }) => {
    const name = `${uniqueName('csrfforged')}.test`;
    await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=${gid}&new=1&Create=Create&zone=${name}&mailaddr=admin.${name}&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560`);
    expect(await pageHas(playwright, `group_zones.cgi?nt_group_id=${gid}`, name)).toBe(false);
  });

  test('user create via POST', async ({ playwright }) => {
    const name = uniqueName('csrfforged');
    await authPost(playwright, `${BASE}/group_users.cgi`, cookies,
      `nt_group_id=${gid}&new=1&Create=Create&username=${name}&password=testpass123!&password2=testpass123!&email=f@test.example&first_name=F&last_name=U&group_defaults=1`);
    expect(await pageHas(playwright, `group_users.cgi?nt_group_id=${gid}`, name)).toBe(false);
  });

  test('record create via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&new_record=1&Create=Create&name=forgedrec&type=A&address=192.0.2.66&ttl=3600`);
    expect(await pageHas(playwright,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, 'forgedrec')).toBe(false);
  });

  test('nameserver create via POST', async ({ playwright }) => {
    const name = uniqueNsName('csrfforged') + '.example.com.';
    await authPost(playwright, `${BASE}/group_nameservers.cgi`, cookies,
      `nt_group_id=1&new=1&Create=Create&name=${name}&address=192.0.2.67&description=forged&export_format=bind&export_interval=120&ttl=3600`);
    expect(await pageHas(playwright, `group_nameservers.cgi?nt_group_id=1`, name)).toBe(false);
  });

  test('bulk zone add via zones.cgi', async ({ playwright }) => {
    const name = `${uniqueName('csrfforged')}.test`;
    await authPost(playwright, `${BASE}/zones.cgi`, cookies,
      `nt_group_id=${gid}&action=add&zone_list=${name}&nameservers=1`);
    expect(await pageHas(playwright, `group_zones.cgi?nt_group_id=${gid}`, name)).toBe(false);
  });

  // --- edits ---

  test('zone edit via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&edit_zone=1&Save=Save&zone=${zoneName}&description=FORGED_EDIT&mailaddr=admin.${zoneName}&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560&nameservers=1`);
    expect(await pageHas(playwright,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, 'FORGED_EDIT')).toBe(false);
  });

  test('user edit via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/group_users.cgi`, cookies,
      `nt_group_id=${gid}&edit=1&Save=Save&nt_user_id=${uid}&username=${username}&first_name=FORGEDNAME&last_name=U&email=f@test.example`);
    expect(await pageHas(playwright,
      `user.cgi?nt_group_id=${gid}&nt_user_id=${uid}`, 'FORGEDNAME')).toBe(false);
  });

  // --- delegation and moves ---

  test('delegation save via POST', async ({ playwright }) => {
    // Forge a record delegation to a fresh group with no other tie to this
    // record; its id showing up anywhere on the record view would mean the
    // delegation was created. (childGid can't be used — the zone-level
    // delegation from setup legitimately puts it on the page.)
    const sibGid = await createGroup(playwright, cookies, gid);
    await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Save=Save&group_list=${sibGid}&obj_list=${rrid}&type=record&perm_write=1&perm_delete=1&perm_delegate=0`);
    const { body } = await authGet(playwright,
      `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}&type=record&nt_zone_record_id=${rrid}`, cookies);
    expect(body).not.toContain(`delegate_group_id=${sibGid}`);
    expect(body).not.toContain(`nt_group_id=${sibGid}`);
    await deleteGroup(playwright, cookies, gid, sibGid);
  });

  test('delegation remove via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Remove=Remove&nt_group_id=${childGid}&nt_zone_id=${zid}&type=zone`);
    // The zone delegation to childGid must still exist.
    expect(await pageHas(playwright,
      `group_zones.cgi?nt_group_id=${childGid}`, `nt_zone_id=${zid}`)).toBe(true);
  });

  test('zone move via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/move_zones.cgi`, cookies,
      `Save=Save&group_list=${childGid}&obj_list=${zid}`);
    // The zone must still live in its original group.
    expect(await pageHas(playwright, `group_zones.cgi?nt_group_id=${gid}`, zoneName)).toBe(true);
  });
});
