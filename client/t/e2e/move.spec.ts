import { test, expect } from '@playwright/test';
import {
  BASE,
  authGet, authPost,
  createGroup, deleteGroup, createZone, deleteZone,
  createUser, deleteUser, createNameserver, deleteNameserver,
  uniqueName, uniqueNsName, extractCsrf,
  apiCookies,
} from './helpers';

test.describe('Move Operations', () => {
  let cookies: string;
  let csrfToken: string;
  let groupA: string;
  let groupB: string;

  test.beforeAll(async ({ playwright }) => {
    cookies = await apiCookies(playwright);
    csrfToken = extractCsrf(cookies);

    groupA = await createGroup(playwright, cookies, 1, uniqueName('e2e_moveA'));
    groupB = await createGroup(playwright, cookies, 1, uniqueName('e2e_moveB'));
  });

  test.afterAll(async ({ playwright }) => {
    await deleteGroup(playwright, cookies, 1, groupA);
    await deleteGroup(playwright, cookies, 1, groupB);
  });

  const ZONES = { move: 'move_zones.cgi', list: 'group_zones.cgi', remove: deleteZone };
  const USERS = { move: 'move_users.cgi', list: 'group_users.cgi', remove: deleteUser };
  const NAMESERVERS = { move: 'move_nameservers.cgi', list: 'group_nameservers.cgi', remove: deleteNameserver };

  // moves the object from groupA to groupB; with checkSource the move's own
  // response goes unchecked and groupA must no longer list it
  async function movedOk(playwright: any, kind: typeof ZONES, id: string, name: string, checkSource: boolean) {
    const listed = async (gid: string) =>
      (await authGet(playwright, `${BASE}/${kind.list}?nt_group_id=${gid}`, cookies)).body;

    try {
      const { body } = await authPost(playwright, `${BASE}/${kind.move}`, cookies,
        `Save=Save&group_list=${groupB}&obj_list=${id}&csrf_token=${csrfToken}`);
      if (checkSource) {
        expect(await listed(groupA)).not.toContain(name);
      } else {
        expect(body.toLowerCase()).not.toContain('error_code');
      }
      expect(await listed(groupB)).toContain(name);
    } finally {
      await kind.remove(playwright, cookies, groupB, id).catch(() =>
        kind.remove(playwright, cookies, groupA, id).catch(() => {}));
    }
  }

  test('move zone to different group', async ({ playwright }) => {
    const zone = `${uniqueName('e2e-move')}.test`;
    const zid = await createZone(playwright, cookies, groupA, zone);
    await movedOk(playwright, ZONES, zid, zone, false);
  });

  test('moved zone absent from source, present in target', async ({ playwright }) => {
    const zone = `${uniqueName('e2e-move2')}.test`;
    const zid = await createZone(playwright, cookies, groupA, zone);
    await movedOk(playwright, ZONES, zid, zone, true);
  });

  test('move user to different group', async ({ playwright }) => {
    const username = uniqueName('e2emoveuser');
    const uid = await createUser(playwright, cookies, groupA, { username });
    await movedOk(playwright, USERS, uid, username, false);
  });

  test('moved user absent from source, present in target', async ({ playwright }) => {
    const username = uniqueName('e2emoveuser2');
    const uid = await createUser(playwright, cookies, groupA, { username });
    await movedOk(playwright, USERS, uid, username, true);
  });

  test('move nameserver to different group', async ({ playwright }) => {
    const nsName = `${uniqueNsName('ns-move')}.e2e.test.`;
    const nsid = await createNameserver(playwright, cookies, groupA,
      { name: nsName, address: '192.0.2.70' });
    await movedOk(playwright, NAMESERVERS, nsid, nsName, false);
  });

  test('moved nameserver absent from source, present in target', async ({ playwright }) => {
    const nsName = `${uniqueNsName('ns-move2')}.e2e.test.`;
    const nsid = await createNameserver(playwright, cookies, groupA,
      { name: nsName, address: '192.0.2.71' });
    await movedOk(playwright, NAMESERVERS, nsid, nsName, true);
  });
});
