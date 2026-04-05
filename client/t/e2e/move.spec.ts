import { test, expect } from '@playwright/test';
import {
  BASE,
  apiLogin, authGet, authPost, cookieString,
  createGroup, deleteGroup, createZone, deleteZone,
  createUser, deleteUser, createNameserver, deleteNameserver,
  uniqueName, uniqueNsName, extractCsrf,
} from './helpers';

test.describe('Move Operations', () => {
  let cookies: string;
  let csrfToken: string;
  let groupA: string;
  let groupB: string;

  test.beforeAll(async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    cookies = cookieString(sessionCookie, csrfCookie);
    csrfToken = csrfCookie;

    groupA = await createGroup(playwright, cookies, 1, uniqueName('e2e_moveA'));
    groupB = await createGroup(playwright, cookies, 1, uniqueName('e2e_moveB'));
  });

  test.afterAll(async ({ playwright }) => {
    await deleteGroup(playwright, cookies, 1, groupA);
    await deleteGroup(playwright, cookies, 1, groupB);
  });

  test('move zone to different group', async ({ playwright }) => {
    const zone = `${uniqueName('e2e-move')}.test`;
    const zid = await createZone(playwright, cookies, groupA, zone);

    try {
      // Move zone: Save=Save, group_list=target, obj_list=zid
      const { body } = await authPost(playwright, `${BASE}/move_zones.cgi`, cookies,
        `Save=Save&group_list=${groupB}&obj_list=${zid}&csrf_token=${csrfToken}`);
      expect(body.toLowerCase()).not.toContain('error_code');

      const { body: bBody } = await authGet(playwright,
        `${BASE}/group_zones.cgi?nt_group_id=${groupB}`, cookies);
      expect(bBody).toContain(zone);
    } finally {
      await deleteZone(playwright, cookies, groupB, zid).catch(() =>
        deleteZone(playwright, cookies, groupA, zid).catch(() => {}));
    }
  });

  test('moved zone absent from source, present in target', async ({ playwright }) => {
    const zone = `${uniqueName('e2e-move2')}.test`;
    const zid = await createZone(playwright, cookies, groupA, zone);

    try {
      await authPost(playwright, `${BASE}/move_zones.cgi`, cookies,
        `Save=Save&group_list=${groupB}&obj_list=${zid}&csrf_token=${csrfToken}`);

      const { body: aBody } = await authGet(playwright,
        `${BASE}/group_zones.cgi?nt_group_id=${groupA}`, cookies);
      expect(aBody).not.toContain(zone);

      const { body: bBody } = await authGet(playwright,
        `${BASE}/group_zones.cgi?nt_group_id=${groupB}`, cookies);
      expect(bBody).toContain(zone);
    } finally {
      await deleteZone(playwright, cookies, groupB, zid).catch(() =>
        deleteZone(playwright, cookies, groupA, zid).catch(() => {}));
    }
  });

  test('move user to different group', async ({ playwright }) => {
    const username = uniqueName('e2emoveuser');
    const uid = await createUser(playwright, cookies, groupA, { username });

    try {
      const { body } = await authPost(playwright, `${BASE}/move_users.cgi`, cookies,
        `Save=Save&group_list=${groupB}&obj_list=${uid}&csrf_token=${csrfToken}`);
      expect(body.toLowerCase()).not.toContain('error_code');

      const { body: bBody } = await authGet(playwright,
        `${BASE}/group_users.cgi?nt_group_id=${groupB}`, cookies);
      expect(bBody).toContain(username);
    } finally {
      await deleteUser(playwright, cookies, groupB, uid).catch(() =>
        deleteUser(playwright, cookies, groupA, uid).catch(() => {}));
    }
  });

  test('moved user absent from source, present in target', async ({ playwright }) => {
    const username = uniqueName('e2emoveuser2');
    const uid = await createUser(playwright, cookies, groupA, { username });

    try {
      await authPost(playwright, `${BASE}/move_users.cgi`, cookies,
        `Save=Save&group_list=${groupB}&obj_list=${uid}&csrf_token=${csrfToken}`);

      const { body: aBody } = await authGet(playwright,
        `${BASE}/group_users.cgi?nt_group_id=${groupA}`, cookies);
      expect(aBody).not.toContain(username);

      const { body: bBody } = await authGet(playwright,
        `${BASE}/group_users.cgi?nt_group_id=${groupB}`, cookies);
      expect(bBody).toContain(username);
    } finally {
      await deleteUser(playwright, cookies, groupB, uid).catch(() =>
        deleteUser(playwright, cookies, groupA, uid).catch(() => {}));
    }
  });

  test('move nameserver to different group', async ({ playwright }) => {
    const nsName = `${uniqueNsName('ns-move')}.e2e.test.`;
    const nsid = await createNameserver(playwright, cookies, groupA,
      { name: nsName, address: '192.0.2.70' });

    try {
      const { body } = await authPost(playwright, `${BASE}/move_nameservers.cgi`, cookies,
        `Save=Save&group_list=${groupB}&obj_list=${nsid}&csrf_token=${csrfToken}`);
      expect(body.toLowerCase()).not.toContain('error_code');

      const { body: bBody } = await authGet(playwright,
        `${BASE}/group_nameservers.cgi?nt_group_id=${groupB}`, cookies);
      expect(bBody).toContain(nsName);
    } finally {
      await deleteNameserver(playwright, cookies, groupB, nsid).catch(() =>
        deleteNameserver(playwright, cookies, groupA, nsid).catch(() => {}));
    }
  });

  test('moved nameserver absent from source, present in target', async ({ playwright }) => {
    const nsName = `${uniqueNsName('ns-move2')}.e2e.test.`;
    const nsid = await createNameserver(playwright, cookies, groupA,
      { name: nsName, address: '192.0.2.71' });

    try {
      await authPost(playwright, `${BASE}/move_nameservers.cgi`, cookies,
        `Save=Save&group_list=${groupB}&obj_list=${nsid}&csrf_token=${csrfToken}`);

      const { body: aBody } = await authGet(playwright,
        `${BASE}/group_nameservers.cgi?nt_group_id=${groupA}`, cookies);
      expect(aBody).not.toContain(nsName);

      const { body: bBody } = await authGet(playwright,
        `${BASE}/group_nameservers.cgi?nt_group_id=${groupB}`, cookies);
      expect(bBody).toContain(nsName);
    } finally {
      await deleteNameserver(playwright, cookies, groupB, nsid).catch(() =>
        deleteNameserver(playwright, cookies, groupA, nsid).catch(() => {}));
    }
  });
});
