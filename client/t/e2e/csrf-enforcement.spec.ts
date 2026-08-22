import { test, expect } from '@playwright/test';
import {
  apiLogin, cookieString, authGet, authPost,
  createGroup, createZone, createRecord, createUser, createNameserver,
  deleteGroup, deleteZone, deleteRecord, deleteUser, deleteNameserver,
  findInListing, uniqueName, uniqueNsName, extractCsrf, BASE, GROUP_DEFAULTS, TEST_GID,
} from './helpers';

// ---------------------------------------------------------------------------
// csrf-links.spec.ts checks rendered links and forms; these state-based tests
// exercise each distinct mutation shape so a rendered token cannot conceal an
// unguarded handler branch.
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
  let groupName: string;
  let username: string;
  let zoneName: string;
  let nsName: string;

  test.beforeAll(async ({ playwright }) => {
    const login = await apiLogin(playwright);
    cookies = cookieString(login.sessionCookie, login.csrfCookie);

    groupName = uniqueName('csrfenf');
    gid = await createGroup(playwright, cookies, TEST_GID, groupName);
    childGid = await createGroup(playwright, cookies, gid);
    username = uniqueName('csrfenf');
    uid = await createUser(playwright, cookies, gid, { username });
    zoneName = `${uniqueName('csrfenf')}.test`;
    zid = await createZone(playwright, cookies, gid, zoneName);
    rrid = await createRecord(playwright, cookies, gid, zid, {
      name: 'enforce', type: 'A', address: '192.0.2.99',
    });
    nsName = uniqueNsName('csrfenf') + '.example.com.';
    nsid = await createNameserver(playwright, cookies, TEST_GID, { name: nsName });
    await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Save=Save&group_list=${childGid}&obj_list=${zid}&type=zone&perm_write=1&perm_delete=1&perm_delegate=1&zone_perm_add_records=1&zone_perm_delete_records=1&csrf_token=${extractCsrf(cookies)}`);
  });

  test.afterAll(async ({ playwright }) => {
    const token = extractCsrf(cookies);
    await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Remove=Remove&nt_group_id=${childGid}&nt_zone_id=${zid}&type=zone&csrf_token=${token}`);
    await deleteZone(playwright, cookies, gid, zid);
    await deleteNameserver(playwright, cookies, TEST_GID, nsid);
    await deleteUser(playwright, cookies, gid, uid);
    await deleteGroup(playwright, cookies, gid, childGid);
    await deleteGroup(playwright, cookies, TEST_GID, gid);
  });

  async function pageHas(playwright: any, path: string, needle: string): Promise<boolean> {
    const { body } = await authGet(playwright, `${BASE}/${path}`, cookies);
    return body.includes(needle);
  }

  // pageHas only works on a listing scoped to a group this run owns, which
  // holds a handful of rows. Root is shared with every other run, and
  // group.cgi shows 10 subgroups per page, so use a filtered lookup there.
  async function rootRow(playwright: any, cgi: string, idParam: string,
    name: string): Promise<string | null> {
    return findInListing(playwright, cookies, { cgi, gid: TEST_GID, idParam }, name);
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
      `${BASE}/group_nameservers.cgi?nt_group_id=${TEST_GID}&delete=1&nt_nameserver_id=${nsid}`, cookies);
    expect(await rootRow(playwright, 'group_nameservers.cgi', 'nt_nameserver_id', nsName)).toBeTruthy();
  });

  test('record delete via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&delete_record=${rrid}`);
    expect(await pageHas(playwright,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, `nt_zone_record_id=${rrid}`)).toBe(true);
  });

  test('zone recovery via POST', async ({ playwright }) => {
    const name = `${uniqueName('csrfrecover')}.test`;
    const deletedZid = await createZone(playwright, cookies, gid, name);
    await deleteZone(playwright, cookies, gid, deletedZid);
    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${deletedZid}&edit_zone=1&undelete=1&Save=Save&zone=${name}&mailaddr=admin.${name}&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560`);
    expect(await pageHas(playwright, `group_zones.cgi?nt_group_id=${gid}`, name)).toBe(false);
  });

  test('record recovery via POST', async ({ playwright }) => {
    const deletedRrid = await createRecord(playwright, cookies, gid, zid, {
      name: 'forgedrecovery', type: 'A', address: '192.0.2.111',
    });
    await deleteRecord(playwright, cookies, gid, zid, deletedRrid);
    const { body } = await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${deletedRrid}&edit_record=1&deleted=0&Save=Save&name=forgedrecovery&type=A&address=192.0.2.111&ttl=3600`);
    expect(body).toContain('CSRF validation failed');
  });

  // --- creates ---

  test('group create via POST', async ({ playwright }) => {
    const name = uniqueName('csrfforged');
    await authPost(playwright, `${BASE}/group.cgi`, cookies,
      `nt_group_id=${TEST_GID}&new=1&Create=Create&name=${name}`);
    expect(await rootRow(playwright, 'group.cgi', 'nt_group_id', name)).toBeNull();
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
      `nt_group_id=${gid}&new=1&Create=Create&username=${name}&password=Valid%23E2e%23Pass44&password2=Valid%23E2e%23Pass44&email=f@example.com&first_name=F&last_name=U&group_defaults=1`);
    expect(await pageHas(playwright, `group_users.cgi?nt_group_id=${gid}`, name)).toBe(false);
  });

  test('record create via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&new_record=1&Create=Create&name=blockedcreate&type=A&address=192.0.2.66&ttl=3600`);
    expect(await pageHas(playwright,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, 'blockedcreate')).toBe(false);
  });

  test('nameserver create via POST', async ({ playwright }) => {
    const name = uniqueNsName('csrfforged') + '.example.com.';
    await authPost(playwright, `${BASE}/group_nameservers.cgi`, cookies,
      `nt_group_id=${TEST_GID}&new=1&Create=Create&name=${name}&address=192.0.2.67&description=forged&export_format=bind&export_interval=120&ttl=3600`);
    expect(await rootRow(playwright, 'group_nameservers.cgi', 'nt_nameserver_id', name)).toBeNull();
  });

  test('bulk zone add via zones.cgi', async ({ playwright }) => {
    const name = `${uniqueName('csrfforged')}.test`;
    await authPost(playwright, `${BASE}/zones.cgi`, cookies,
      `nt_group_id=${gid}&action=add&zone_list=${name}&nameservers=1`);
    expect(await pageHas(playwright, `group_zones.cgi?nt_group_id=${gid}`, name)).toBe(false);
  });

  test('zone create via zone.cgi POST', async ({ playwright }) => {
    const name = `${uniqueName('csrfforged')}.test`;
    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&new_zone=1&Create=Create&zone=${name}&mailaddr=admin.${name}&description=forged&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560`);
    expect(await pageHas(playwright, `group_zones.cgi?nt_group_id=${gid}`, name)).toBe(false);
  });

  test('user create via user.cgi POST', async ({ playwright }) => {
    const name = uniqueName('csrfforged');
    await authPost(playwright, `${BASE}/user.cgi`, cookies,
      `nt_group_id=${gid}&new=1&Create=Create&username=${name}&password=Valid%23E2e%23Pass44&password2=Valid%23E2e%23Pass44&email=f@example.com&first_name=F&last_name=U&group_defaults=1`);
    expect(await pageHas(playwright, `group_users.cgi?nt_group_id=${gid}`, name)).toBe(false);
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
      `nt_group_id=${gid}&edit=1&Save=Save&nt_user_id=${uid}&username=${username}&first_name=FORGEDNAME&last_name=U&email=f@example.com`);
    expect(await pageHas(playwright,
      `user.cgi?nt_group_id=${gid}&nt_user_id=${uid}`, 'FORGEDNAME')).toBe(false);
  });

  test('zone edit via group_zones.cgi POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&edit=1&Save=Save&zone=${zoneName}&mailaddr=admin.${zoneName}&description=FORGED_LIST_EDIT&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560`);
    expect(await pageHas(playwright,
      `group_zones.cgi?nt_group_id=${gid}&nt_zone_id=${zid}&edit=1`,
      'FORGED_LIST_EDIT')).toBe(false);
  });

  test('user edit via user.cgi POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/user.cgi`, cookies,
      `nt_group_id=${gid}&nt_user_id=${uid}&edit=1&Save=Save&username=${username}&first_name=FORGED_DETAIL_EDIT&last_name=U&email=f@example.com&group_defaults=1`);
    expect(await pageHas(playwright,
      `user.cgi?nt_group_id=${gid}&nt_user_id=${uid}`, 'FORGED_DETAIL_EDIT')).toBe(false);
  });

  test('group edit via POST', async ({ playwright }) => {
    const forgedName = uniqueName('csrfforged');
    await authPost(playwright, `${BASE}/group.cgi`, cookies,
      `nt_group_id=${gid}&edit=1&Save=Save&name=${forgedName}&${GROUP_DEFAULTS}`);
    expect(await rootRow(playwright, 'group.cgi', 'nt_group_id', groupName)).toBeTruthy();
    expect(await rootRow(playwright, 'group.cgi', 'nt_group_id', forgedName)).toBeNull();
  });

  test('nameserver edit via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/group_nameservers.cgi`, cookies,
      `nt_group_id=${TEST_GID}&nt_nameserver_id=${nsid}&edit=1&Save=Save&name=${encodeURIComponent(nsName)}&address=192.0.2.1&description=FORGED_NS_EDIT&export_format=bind&export_interval=120&ttl=3600`);
    expect(await pageHas(playwright,
      `group_nameservers.cgi?nt_group_id=${TEST_GID}&nt_nameserver_id=${nsid}&edit=1`,
      'FORGED_NS_EDIT')).toBe(false);
  });

  test('record edit via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&edit_record=1&Save=Save&name=enforce&type=A&address=192.0.2.200&ttl=3600`);
    expect(await pageHas(playwright,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, '192.0.2.200')).toBe(false);
    expect(await pageHas(playwright,
      `zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, '192.0.2.99')).toBe(true);
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

  test('delegation modify via POST', async ({ playwright }) => {
    const { body } = await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Modify=Modify&nt_group_id=${childGid}&obj_list=${zid}&type=zone&perm_write=0&perm_delete=0&perm_delegate=0&zone_perm_add_records=0&zone_perm_delete_records=0`);
    expect(body).toContain('CSRF validation failed');
    expect(await pageHas(playwright,
      `group_zones.cgi?nt_group_id=${childGid}`, `nt_zone_id=${zid}`)).toBe(true);
  });

  test('delegation removal via group_zones.cgi GET', async ({ playwright }) => {
    await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${childGid}&nt_zone_id=${zid}&deletedelegate=1`,
      cookies);
    expect(await pageHas(playwright,
      `group_zones.cgi?nt_group_id=${childGid}`, `nt_zone_id=${zid}`)).toBe(true);
  });

  test('delegation removal via zone.cgi GET', async ({ playwright }) => {
    await authGet(playwright,
      `${BASE}/zone.cgi?nt_group_id=${childGid}&nt_zone_id=${zid}&delegate_group_id=${childGid}&deletedelegate=1&type=zone`,
      cookies);
    expect(await pageHas(playwright,
      `group_zones.cgi?nt_group_id=${childGid}`, `nt_zone_id=${zid}`)).toBe(true);
  });

  test('zone move via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/move_zones.cgi`, cookies,
      `Save=Save&group_list=${childGid}&obj_list=${zid}`);
    // The zone must still live in its original group.
    expect(await pageHas(playwright, `group_zones.cgi?nt_group_id=${gid}`, zoneName)).toBe(true);
  });

  test('user move via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/move_users.cgi`, cookies,
      `Save=Save&group_list=${childGid}&obj_list=${uid}`);
    expect(await pageHas(playwright,
      `group_users.cgi?nt_group_id=${gid}`, username)).toBe(true);
    expect(await pageHas(playwright,
      `group_users.cgi?nt_group_id=${childGid}`, username)).toBe(false);
  });

  test('nameserver move via POST', async ({ playwright }) => {
    await authPost(playwright, `${BASE}/move_nameservers.cgi`, cookies,
      `Save=Save&group_list=${childGid}&obj_list=${nsid}`);
    expect(await rootRow(playwright, 'group_nameservers.cgi', 'nt_nameserver_id', nsName)).toBeTruthy();
    expect(await pageHas(playwright,
      `group_nameservers.cgi?nt_group_id=${childGid}`, nsName)).toBe(false);
  });
});
