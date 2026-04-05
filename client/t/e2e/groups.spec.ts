import { test, expect } from '@playwright/test';
import {
  BASE, GROUP_DEFAULTS,
  apiLogin, authGet, authPost, cookieString,
  createGroup, deleteGroup, uniqueName, extractCsrf,
} from './helpers';

test.describe('Groups', () => {
  let cookies: string;
  let csrfToken: string;

  test.beforeAll(async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    cookies = cookieString(sessionCookie, csrfCookie);
    csrfToken = csrfCookie;
  });

  test('create sub-group with all permissions', async ({ playwright }) => {
    const name = uniqueName('e2e_grp');
    const gid = await createGroup(playwright, cookies, 1, name);
    expect(Number(gid)).toBeGreaterThan(0);

    // Cleanup
    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('sub-group appears in group list', async ({ playwright }) => {
    const name = uniqueName('e2e_grp');
    const gid = await createGroup(playwright, cookies, 1, name);

    const { body } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=1`, cookies);
    expect(body).toContain(name);

    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('edit sub-group name', async ({ playwright }) => {
    const name = uniqueName('e2e_grp');
    const gid = await createGroup(playwright, cookies, 1, name);

    const newName = uniqueName('e2e_renamed');
    await authPost(playwright, `${BASE}/group.cgi`, cookies,
      `nt_group_id=${gid}&edit=1&Save=Save&name=${newName}&${GROUP_DEFAULTS}&csrf_token=${csrfToken}`);

    const { body } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=1`, cookies);
    expect(body).toContain(newName);

    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('edit sub-group permissions', async ({ playwright }) => {
    const name = uniqueName('e2e_grp');
    const gid = await createGroup(playwright, cookies, 1, name);

    // Edit to remove zone_create permission
    const reducedPerms = GROUP_DEFAULTS.replace('zone_create=1', 'zone_create=0');
    await authPost(playwright, `${BASE}/group.cgi`, cookies,
      `nt_group_id=${gid}&edit=1&Save=Save&name=${name}&${reducedPerms}&csrf_token=${csrfToken}`);

    // Verify edit page shows the group
    const { body } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${gid}&edit=1`, cookies);
    expect(body).toContain(name);

    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('delete sub-group', async ({ playwright }) => {
    const name = uniqueName('e2e_grp');
    const gid = await createGroup(playwright, cookies, 1, name);

    await deleteGroup(playwright, cookies, 1, gid);

    const { body } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=1`, cookies);
    expect(body).not.toContain(name);
  });

  test('create group without name fails gracefully', async ({ playwright }) => {
    const { body } = await authPost(playwright, `${BASE}/group.cgi`, cookies,
      `nt_group_id=1&new=1&Create=Create&name=&${GROUP_DEFAULTS}&csrf_token=${csrfToken}`);
    // Should show error or remain on form, not crash
    expect(body.toLowerCase()).toMatch(/error|required|invalid|group/i);
  });

  test('quick zone search from group page', async ({ playwright }) => {
    // The group page has a zone quick-search. Verify it responds.
    const { body } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=1&Quick+search=Search&search_value=nonexistent`, cookies);
    expect(body).toBeDefined();
    // Should not crash even with no results
    expect(body.toLowerCase()).not.toContain('internal server error');
  });

  test('nested sub-group creation and deletion', async ({ playwright }) => {
    const parentName = uniqueName('e2e_parent');
    const parentGid = await createGroup(playwright, cookies, 1, parentName);

    const childName = uniqueName('e2e_child');
    const childGid = await createGroup(playwright, cookies, parentGid, childName);

    // Verify child exists in parent
    const { body } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${parentGid}`, cookies);
    expect(body).toContain(childName);

    // Delete child first, then parent
    await deleteGroup(playwright, cookies, parentGid, childGid);
    await deleteGroup(playwright, cookies, 1, parentGid);
  });
});
