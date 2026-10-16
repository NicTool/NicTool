import { test, expect } from '@playwright/test';
import {
  BASE,
  authGet, authPost,
  createGroup, deleteGroup, createZone, deleteZone,
  createRecord, deleteRecord, createUser, deleteUser,
  uniqueName, extractCsrf,
  apiCookies,
} from './helpers';

test.describe('Delegation', () => {
  const WRITE_PERMS = 'perm_write=1&perm_delete=0&perm_delegate=0&zone_perm_add_records=1&zone_perm_delete_records=1';
  const NO_PERMS = 'perm_write=0&perm_delete=0&perm_delegate=0&zone_perm_add_records=0&zone_perm_delete_records=0';

  let cookies: string;
  let csrfToken: string;
  let parentGid: string;
  let childGid: string;
  let childGroupName: string;
  let zid: string;
  let zoneName: string;

  test.beforeAll(async ({ playwright }) => {
    cookies = await apiCookies(playwright);
    csrfToken = extractCsrf(cookies);

    parentGid = await createGroup(playwright, cookies, 1, uniqueName('e2e_deleg_parent'));
    childGroupName = uniqueName('e2e_deleg_child');
    childGid = await createGroup(playwright, cookies, parentGid, childGroupName);
    zoneName = `${uniqueName('e2e-deleg')}.test`;
    zid = await createZone(playwright, cookies, parentGid, zoneName);
  });

  test.afterAll(async ({ playwright }) => {
    await deleteZone(playwright, cookies, parentGid, zid);
    await deleteGroup(playwright, cookies, parentGid, childGid);
    await deleteGroup(playwright, cookies, 1, parentGid);
  });

  // Save delegates the zone to the child group; Modify changes that delegation
  function delegateZone(playwright: any, action: 'Save' | 'Modify', perms: string) {
    const target = action === 'Save' ? `group_list=${childGid}` : `nt_group_id=${childGid}`;
    return authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `${action}=${action}&${target}&obj_list=${zid}&type=zone&${perms}&csrf_token=${csrfToken}`);
  }

  test('delegate zone to child group', async ({ playwright }) => {
    const { body } = await delegateZone(playwright, 'Save', WRITE_PERMS);
    expect(body.toLowerCase()).not.toContain('error_code');
  });

  test('delegated zone appears in child group zone list', async ({ playwright }) => {
    const { body } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${childGid}`, cookies);
    expect(body).toContain(zoneName);
  });

  test('delegated zone shows delegation info', async ({ playwright }) => {
    const { body } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${childGid}`, cookies);
    const row = body.match(new RegExp(`<tr[^>]*id="zoneID${zid}"[\\s\\S]*?</tr>`));
    expect(row, 'the child group lists the zone').toBeTruthy();
    expect(row![0]).toContain('zone-delegated.gif');
    expect(row![0]).toContain('perm-write.gif');
  });

  test('edit zone delegation permissions', async ({ playwright }) => {
    const { body } = await delegateZone(playwright, 'Modify', NO_PERMS);
    expect(body.toLowerCase()).not.toContain('error_code');
  });

  test('remove zone delegation', async ({ playwright }) => {
    // Re-delegate first
    await delegateZone(playwright, 'Save', WRITE_PERMS);

    // Remove=Remove
    const { body } = await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
      `Remove=Remove&nt_group_id=${childGid}&nt_zone_id=${zid}&csrf_token=${csrfToken}`);
    expect(body.toLowerCase()).not.toContain('error_code');

    // Re-delegate for subsequent tests
    await delegateZone(playwright, 'Save', WRITE_PERMS);
  });

  test('delegate record to child group', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, parentGid, zid,
      { name: 'deleg-rec', type: 'A', address: '192.0.2.30' });

    try {
      const { body } = await authPost(playwright, `${BASE}/delegate_zones.cgi`, cookies,
        `Save=Save&group_list=${childGid}&obj_list=${rrid}&type=record&perm_write=1&perm_delete=0&perm_delegate=0&csrf_token=${csrfToken}`);
      expect(body.toLowerCase()).not.toContain('error_code');
    } finally {
      await deleteRecord(playwright, cookies, parentGid, zid, rrid);
    }
  });

  test('delegation with write perm allows editing', async ({ playwright }) => {
    const username = uniqueName('e2e_deleg_user');
    const uid = await createUser(playwright, cookies, childGid, { username, password: 'delegtest123!' });

    try {
      // Ensure zone is delegated with write + add_records permission
      await delegateZone(playwright, 'Save', WRITE_PERMS);

      // Login as child user
      const childCookies = await apiCookies(playwright, `${username}@${childGroupName}`, 'delegtest123!');

      // Should be able to create a record in the delegated zone
      const rrid = await createRecord(playwright, childCookies, childGid, zid,
        { name: 'deleg-write', type: 'A', address: '192.0.2.31' });

      await deleteRecord(playwright, cookies, parentGid, zid, rrid);
    } finally {
      await deleteUser(playwright, cookies, childGid, uid);
    }
  });

  test('delegation without write perm prevents editing', async ({ playwright }) => {
    const username = uniqueName('e2e_deleg_nowrite');
    const uid = await createUser(playwright, cookies, childGid, { username, password: 'delegtest123!' });

    try {
      // Delegate zone with NO write, NO add_records permission
      await delegateZone(playwright, 'Modify', NO_PERMS);

      // Login as child user
      const childCookies = await apiCookies(playwright, `${username}@${childGroupName}`, 'delegtest123!');

      // Trying to add a record should fail
      const { body } = await authPost(playwright, `${BASE}/zone.cgi`, childCookies,
        `nt_group_id=${childGid}&nt_zone_id=${zid}&new_record=1&Create=Create&name=nowrite&type=A&address=192.0.2.32&ttl=3600&csrf_token=${extractCsrf(childCookies)}`);
      expect(body.toLowerCase()).toMatch(/error|permission|denied|not allowed|access/i);
    } finally {
      await deleteUser(playwright, cookies, childGid, uid);
      // Restore delegation with write
      await delegateZone(playwright, 'Modify', WRITE_PERMS);
    }
  });
});
