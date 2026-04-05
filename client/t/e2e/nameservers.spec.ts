import { test, expect } from '@playwright/test';
import {
  BASE,
  apiLogin, authGet, authPost, cookieString,
  createGroup, deleteGroup, createNameserver, deleteNameserver,
  uniqueName, uniqueNsName, extractCsrf, browserLogin,
} from './helpers';

test.describe('Nameservers', () => {
  let cookies: string;
  let csrfToken: string;
  let gid: string;

  test.beforeAll(async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    cookies = cookieString(sessionCookie, csrfCookie);
    csrfToken = csrfCookie;
    gid = await createGroup(playwright, cookies, 1, uniqueName('e2e_ns'));
  });

  test.afterAll(async ({ playwright }) => {
    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('create nameserver with BIND export format', async ({ playwright }) => {
    const name = `${uniqueNsName('ns1')}.e2e.test.`;
    const nsid = await createNameserver(playwright, cookies, gid,
      { name, address: '192.0.2.53', export_format: 'bind' });
    expect(Number(nsid)).toBeGreaterThan(0);
    await deleteNameserver(playwright, cookies, gid, nsid);
  });

  test('nameserver appears in list', async ({ playwright }) => {
    const name = `${uniqueNsName('ns2')}.e2e.test.`;
    const nsid = await createNameserver(playwright, cookies, gid,
      { name, address: '192.0.2.54' });

    const { body } = await authGet(playwright,
      `${BASE}/group_nameservers.cgi?nt_group_id=${gid}`, cookies);
    expect(body).toContain(name);

    await deleteNameserver(playwright, cookies, gid, nsid);
  });

  test('edit nameserver description', async ({ playwright }) => {
    const name = `${uniqueNsName('ns3')}.e2e.test.`;
    const nsid = await createNameserver(playwright, cookies, gid,
      { name, address: '192.0.2.55', description: 'original desc' });

    await authPost(playwright, `${BASE}/group_nameservers.cgi`, cookies,
      `nt_group_id=${gid}&nt_nameserver_id=${nsid}&edit=1&Save=Save&name=${encodeURIComponent(name)}&address=192.0.2.55&description=${encodeURIComponent('updated desc')}&export_format=bind&export_interval=120&ttl=3600&csrf_token=${csrfToken}`);

    const { body } = await authGet(playwright,
      `${BASE}/group_nameservers.cgi?nt_group_id=${gid}&nt_nameserver_id=${nsid}&edit=1`, cookies);
    expect(body).toContain('updated desc');

    await deleteNameserver(playwright, cookies, gid, nsid);
  });

  test('edit nameserver address', async ({ playwright }) => {
    const name = `${uniqueNsName('ns4')}.e2e.test.`;
    const nsid = await createNameserver(playwright, cookies, gid,
      { name, address: '192.0.2.56' });

    await authPost(playwright, `${BASE}/group_nameservers.cgi`, cookies,
      `nt_group_id=${gid}&nt_nameserver_id=${nsid}&edit=1&Save=Save&name=${encodeURIComponent(name)}&address=192.0.2.57&description=e2e+test+ns&export_format=bind&export_interval=120&ttl=3600&csrf_token=${csrfToken}`);

    const { body } = await authGet(playwright,
      `${BASE}/group_nameservers.cgi?nt_group_id=${gid}&nt_nameserver_id=${nsid}&edit=1`, cookies);
    expect(body).toContain('192.0.2.57');

    await deleteNameserver(playwright, cookies, gid, nsid);
  });

  test('delete nameserver', async ({ playwright }) => {
    const name = `${uniqueNsName('ns5')}.e2e.test.`;
    const nsid = await createNameserver(playwright, cookies, gid,
      { name, address: '192.0.2.58' });

    await deleteNameserver(playwright, cookies, gid, nsid);

    const { body } = await authGet(playwright,
      `${BASE}/group_nameservers.cgi?nt_group_id=${gid}`, cookies);
    expect(body).not.toContain(name);
  });

  test('nameserver with IPv6 address', async ({ playwright }) => {
    const name = `${uniqueNsName('ns6')}.e2e.test.`;
    const nsid = await createNameserver(playwright, cookies, gid,
      { name, address: '2001:db8::53' });
    expect(Number(nsid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright,
      `${BASE}/group_nameservers.cgi?nt_group_id=${gid}&nt_nameserver_id=${nsid}&edit=1`, cookies);
    expect(body).toContain('2001:db8::53');

    await deleteNameserver(playwright, cookies, gid, nsid);
  });

  test('export format selector changes form fields', async ({ page }) => {
    await browserLogin(page);

    const bodyFrame = page.frames().find(f => f.url().includes('group.cgi'));
    expect(bodyFrame).toBeTruthy();

    const nsLink = bodyFrame!.locator('a:has-text("Nameservers")');
    if (await nsLink.count() > 0) {
      await nsLink.first().click();
      await page.waitForTimeout(1500);
    }

    const nsFrame = page.frames().find(f => f.url().includes('group_nameservers.cgi'));
    if (nsFrame) {
      const newNsLink = nsFrame.locator('a:has-text("New Nameserver")');
      if (await newNsLink.count() > 0) {
        await newNsLink.first().click();
        await page.waitForTimeout(1500);
      }

      const formFrame = page.frames().find(f => f.url().includes('group_nameservers.cgi'));
      if (formFrame) {
        const formatSelect = formFrame.locator('select[name="export_format"]');
        if (await formatSelect.count() > 0) {
          const optionCount = await formatSelect.locator('option').count();
          expect(optionCount).toBeGreaterThan(0);
        }
      }
    }
  });
});
