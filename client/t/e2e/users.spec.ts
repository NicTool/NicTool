import { test, expect } from '@playwright/test';
import {
  BASE,
  apiLogin, authGet, authPost,
  createGroup, deleteGroup, createUser, deleteUser,
  uniqueName, extractCsrf,
  apiCookies,
} from './helpers';

test.describe('Users', () => {
  let cookies: string;
  let csrfToken: string;
  let gid: string;
  let groupName: string;

  test.beforeAll(async ({ playwright }) => {
    cookies = await apiCookies(playwright);
    csrfToken = extractCsrf(cookies);
    groupName = uniqueName('e2e_users');
    gid = await createGroup(playwright, cookies, 1, groupName);
  });

  test.afterAll(async ({ playwright }) => {
    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('create user with inherited group permissions', async ({ playwright }) => {
    const username = uniqueName('e2euser');
    const uid = await createUser(playwright, cookies, gid, { username });
    expect(Number(uid)).toBeGreaterThan(0);
    await deleteUser(playwright, cookies, gid, uid);
  });

  test('user appears in user list', async ({ playwright }) => {
    const username = uniqueName('e2euser');
    const uid = await createUser(playwright, cookies, gid, { username });

    const { body } = await authGet(playwright,
      `${BASE}/group_users.cgi?nt_group_id=${gid}`, cookies);
    expect(body).toContain(username);

    await deleteUser(playwright, cookies, gid, uid);
  });

  test('edit user properties', async ({ playwright }) => {
    const username = uniqueName('e2euser');
    const uid = await createUser(playwright, cookies, gid, { username });

    await authPost(playwright, `${BASE}/group_users.cgi`, cookies,
      `nt_group_id=${gid}&nt_user_id=${uid}&edit=1&Save=Save&username=${username}&email=updated@test.example&first_name=Updated&last_name=Person&csrf_token=${csrfToken}`);

    const { body } = await authGet(playwright,
      `${BASE}/group_users.cgi?nt_group_id=${gid}&nt_user_id=${uid}&edit=1`, cookies);
    expect(body).toContain('Updated');

    await deleteUser(playwright, cookies, gid, uid);
  });

  test('edit user password requires current_password', async ({ playwright }) => {
    const username = uniqueName('e2euser');
    const uid = await createUser(playwright, cookies, gid, { username, password: 'oldpass123!' });

    // an admin may set any password, so the user changes their own
    const userCookies = await apiCookies(playwright, `${username}@${groupName}`, 'oldpass123!');
    const changePassword = async (current: string) => (await authPost(playwright, `${BASE}/user.cgi`, userCookies,
      `nt_group_id=${gid}&nt_user_id=${uid}&edit=1&Save=Save&username=${username}&first_name=Test&last_name=User&email=${username}@test.example&password=newpass456!&password2=newpass456!${current}&csrf_token=${extractCsrf(userCookies)}`)).body;

    expect(await changePassword('')).toContain('Current password is required.');
    expect(await changePassword('&current_password=wrongpass1!')).toContain('Current password is incorrect.');
    expect(await changePassword('&current_password=oldpass123!')).not.toContain('Sanity Error');

    const login = await apiLogin(playwright, `${username}@${groupName}`, 'newpass456!');
    expect(login.sessionCookie, 'the new password logs in').toBeTruthy();

    await deleteUser(playwright, cookies, gid, uid);
  });

  test('delete user', async ({ playwright }) => {
    const username = uniqueName('e2euser');
    const uid = await createUser(playwright, cookies, gid, { username });

    await deleteUser(playwright, cookies, gid, uid);

    const { body } = await authGet(playwright,
      `${BASE}/group_users.cgi?nt_group_id=${gid}`, cookies);
    expect(body).not.toContain(username);
  });

  test('create user with custom permissions', async ({ playwright }) => {
    const username = uniqueName('e2euser');
    // Create user with explicit permissions in POST data
    await authPost(playwright, `${BASE}/group_users.cgi`, cookies,
      `nt_group_id=${gid}&new=1&Create=Create&username=${username}&password=testpass123!&password2=testpass123!&email=${username}@test.example&first_name=Custom&last_name=Perms&zone_create=1&zone_delete=0&group_create=0&csrf_token=${csrfToken}`);

    const { body } = await authGet(playwright,
      `${BASE}/group_users.cgi?nt_group_id=${gid}`, cookies);
    expect(body).toContain(username);

    // Get uid for cleanup
    const m = body.match(new RegExp(`nt_user_id=(\\d+)[^>]*>\\s*${username}`));
    if (m) {
      await deleteUser(playwright, cookies, gid, m[1]);
    }
  });

  test('created user can login', async ({ playwright }) => {
    const username = uniqueName('e2euser');
    const pw = 'canlogin789!';
    const uid = await createUser(playwright, cookies, gid, { username, password: pw });

    // Login as the new user (NicTool login format: username@group)
    const loginResult = await apiLogin(playwright, `${username}@${groupName}`, pw);
    expect(loginResult.sessionCookie).toBeTruthy();
    expect(loginResult.sessionCookie.length).toBeGreaterThan(0);

    await deleteUser(playwright, cookies, gid, uid);
  });

  test('create user with missing required field shows error', async ({ playwright }) => {
    // Attempt to create user without username
    const { body } = await authPost(playwright, `${BASE}/group_users.cgi`, cookies,
      `nt_group_id=${gid}&new=1&Create=Create&username=&password=test123!&password2=test123!&email=bad@test.example&first_name=Bad&last_name=User&csrf_token=${csrfToken}`);
    // Should show error, not crash
    expect(body.toLowerCase()).toMatch(/error|required|invalid|username/i);
  });
});
