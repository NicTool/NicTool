import { test, expect } from '@playwright/test';
import {
  BASE, GROUP_DEFAULTS,
  authGet, authPost,
  createGroup, deleteGroup, createZone, deleteZone,
  createRecord, deleteRecord, createUser, deleteUser,
  uniqueName, extractCsrf,
  apiCookies,
} from './helpers';

test.describe('Permissions', () => {
  let rootCookies: string;
  let rootCsrf: string;
  let gid: string;
  let groupName: string;
  let zid: string;

  test.beforeAll(async ({ playwright }) => {
    rootCookies = await apiCookies(playwright);
    rootCsrf = extractCsrf(rootCookies);
    groupName = uniqueName('e2e_perms');
    gid = await createGroup(playwright, rootCookies, 1, groupName);
    zid = await createZone(playwright, rootCookies, gid, `${uniqueName('e2e')}.test`);
  });

  test.afterAll(async ({ playwright }) => {
    await deleteZone(playwright, rootCookies, gid, zid);
    await deleteGroup(playwright, rootCookies, 1, gid);
  });

  async function createRestrictedUser(playwright: any, overrides: Record<string, string>) {
    const username = uniqueName('e2erestuser');
    const password = 'restricted123!';

    // Build permission string with overrides
    let perms = GROUP_DEFAULTS;
    for (const [key, val] of Object.entries(overrides)) {
      perms = perms.replace(new RegExp(`${key}=\\d`), `${key}=${val}`);
    }

    // Create a restricted sub-group
    const restrictedGroupName = uniqueName('e2e_restricted');
    await authPost(playwright, `${BASE}/group.cgi`, rootCookies,
      `nt_group_id=${gid}&new=1&Create=Create&name=${restrictedGroupName}&${perms}&csrf_token=${rootCsrf}`);

    const { body: groupList } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${gid}`, rootCookies);
    const gm = groupList.match(new RegExp(`nt_group_id=(\\d+)[^>]*>\\s*${restrictedGroupName}`));
    if (!gm) {
      const gm2 = groupList.match(new RegExp(`nt_group_id=(\\d+)">${restrictedGroupName}`));
      if (!gm2) throw new Error(`Failed to find restricted group ${restrictedGroupName}`);
      var restrictedGid = gm2[1];
    } else {
      var restrictedGid = gm[1];
    }

    // Create user in the restricted group
    const uid = await createUser(playwright, rootCookies, restrictedGid, { username, password });

    // Login as restricted user
    const userCookies = await apiCookies(playwright, `${username}@${restrictedGroupName}`, password);

    return { userCookies, userCsrf: extractCsrf(userCookies), restrictedGid, uid, username };
  }

  async function cleanupRestrictedUser(playwright: any, restrictedGid: string, uid: string) {
    await deleteUser(playwright, rootCookies, restrictedGid, uid);
    await deleteGroup(playwright, rootCookies, gid, restrictedGid);
  }

  // POSTs as a fresh restricted user, removed again before the body is checked
  async function restrictedPost(playwright: any, overrides: Record<string, string>, cgi: string,
    data: (u: Awaited<ReturnType<typeof createRestrictedUser>>) => string): Promise<string> {
    const u = await createRestrictedUser(playwright, overrides);
    try {
      const { body } = await authPost(playwright, `${BASE}/${cgi}`, u.userCookies, data(u));
      return body;
    } finally {
      await cleanupRestrictedUser(playwright, u.restrictedGid, u.uid);
    }
  }

  test('user without zone_create cannot create zone', async ({ playwright }) => {
    const body = await restrictedPost(playwright, { zone_create: '0' }, 'group_zones.cgi',
      u => `nt_group_id=${u.restrictedGid}&new=1&Create=Create&zone=noperm.test&mailaddr=admin.noperm.test&description=test&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560&csrf_token=${u.userCsrf}`);
    expect(body.toLowerCase()).toMatch(/error|permission|denied|not allowed|access/i);
  });

  test('user without zone_write cannot edit zone', async ({ playwright }) => {
    const body = await restrictedPost(playwright, { zone_write: '0' }, 'group_zones.cgi',
      u => `nt_group_id=${gid}&nt_zone_id=${zid}&edit=1&Save=Save&zone=hacked.test&mailaddr=admin.hacked.test&description=hacked&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560&csrf_token=${u.userCsrf}`);
    expect(body.toLowerCase()).toMatch(/error|permission|denied|not allowed|access/i);
  });

  test('user without zone_delete cannot delete zone', async ({ playwright }) => {
    const body = await restrictedPost(playwright, { zone_delete: '0' }, 'group_zones.cgi',
      u => `nt_group_id=${gid}&delete=1&zone_list=${zid}&csrf_token=${u.userCsrf}`);
    expect(body.toLowerCase()).toMatch(/error|permission|denied|not allowed|access/i);
  });

  test('user without zonerecord_create cannot create record', async ({ playwright }) => {
    const body = await restrictedPost(playwright, { zonerecord_create: '0' }, 'zone.cgi',
      u => `nt_group_id=${gid}&nt_zone_id=${zid}&new_record=1&Create=Create&name=noperm&type=A&address=192.0.2.99&ttl=3600&csrf_token=${u.userCsrf}`);
    expect(body.toLowerCase()).toMatch(/error|permission|denied|not allowed|access/i);
  });

  test('user without zonerecord_delete cannot delete record', async ({ playwright }) => {
    // Create a record as root to try to delete
    const rrid = await createRecord(playwright, rootCookies, gid, zid,
      { name: 'perm-del-test', type: 'A', address: '192.0.2.98' });

    try {
      const body = await restrictedPost(playwright, { zonerecord_delete: '0' }, 'zone.cgi',
        u => `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&delete_record=${rrid}&csrf_token=${u.userCsrf}`);
      expect(body.toLowerCase()).toMatch(/error|permission|denied|not allowed|access/i);
    } finally {
      await deleteRecord(playwright, rootCookies, gid, zid, rrid);
    }
  });

  test('user without group_create cannot create sub-group', async ({ playwright }) => {
    const body = await restrictedPost(playwright, { group_create: '0' }, 'group.cgi',
      u => `nt_group_id=${u.restrictedGid}&new=1&Create=Create&name=noperm_group&${GROUP_DEFAULTS}&csrf_token=${u.userCsrf}`);
    expect(body.toLowerCase()).toMatch(/error|permission|denied|not allowed|access/i);
  });

  test('user without user_create cannot create user', async ({ playwright }) => {
    const body = await restrictedPost(playwright, { user_create: '0' }, 'group_users.cgi',
      u => `nt_group_id=${u.restrictedGid}&new=1&Create=Create&username=noperm_user&password=test123!&password2=test123!&email=no@test.example&first_name=No&last_name=Perm&csrf_token=${u.userCsrf}`);
    expect(body.toLowerCase()).toMatch(/error|permission|denied|not allowed|access/i);
  });

  test('user with self_write can edit own profile', async ({ playwright }) => {
    const body = await restrictedPost(playwright, { self_write: '1' }, 'group_users.cgi',
      u => `nt_group_id=${u.restrictedGid}&nt_user_id=${u.uid}&edit=1&Save=Save&username=${u.username}&first_name=SelfEdited&last_name=User&email=selfed@test.example&csrf_token=${u.userCsrf}`);
    // Should not show permission error
    expect(body.toLowerCase()).not.toMatch(/permission denied|not allowed/i);
  });
});
