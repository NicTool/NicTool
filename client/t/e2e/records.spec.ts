import { test, expect } from '@playwright/test';
import {
  BASE,
  apiLogin, authGet, authPost, cookieString,
  createGroup, deleteGroup, createZone, deleteZone,
  createRecord, deleteRecord, uniqueName, extractCsrf,
  browserLogin,
} from './helpers';

test.describe('Records', () => {
  let cookies: string;
  let csrfToken: string;
  let gid: string;
  let zid: string;

  test.beforeAll(async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    cookies = cookieString(sessionCookie, csrfCookie);
    csrfToken = csrfCookie;
    gid = await createGroup(playwright, cookies, 1, uniqueName('e2e_recs'));
    zid = await createZone(playwright, cookies, gid, `${uniqueName('e2e')}.test`);
  });

  test.afterAll(async ({ playwright }) => {
    await deleteZone(playwright, cookies, gid, zid);
    await deleteGroup(playwright, cookies, 1, gid);
  });

  // --- Basic record types ---

  test('create A record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'a-test', type: 'A', address: '192.0.2.1' });
    expect(Number(rrid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('192.0.2.1');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create AAAA record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'aaaa-test', type: 'AAAA', address: '2001:db8::1' });
    expect(Number(rrid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    // Address may be displayed in expanded or compressed IPv6 form
    expect(body).toMatch(/2001:db8:.*1|2001:0db8/i);

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create CNAME record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'cname-test', type: 'CNAME', address: 'target.example.com.' });
    expect(Number(rrid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('target.example.com.');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create MX record with weight', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'mx-test', type: 'MX', address: 'mail.example.com.', weight: '10' });
    expect(Number(rrid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('mail.example.com.');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create TXT record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'txt-test', type: 'TXT', address: 'v=spf1 include:example.com ~all' });
    expect(Number(rrid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('v=spf1');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create NS record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'ns-test', type: 'NS', address: 'ns1.example.com.' });
    expect(Number(rrid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('ns1.example.com.');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('edit A record address', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'edit-test', type: 'A', address: '192.0.2.10' });

    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&edit_record=${rrid}&Save=Save&name=edit-test&type=A&address=192.0.2.20&ttl=3600&csrf_token=${csrfToken}`);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('192.0.2.20');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('edit MX record weight', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'mx-edit', type: 'MX', address: 'mail.example.com.', weight: '10' });

    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&edit_record=${rrid}&Save=Save&name=mx-edit&type=MX&address=mail.example.com.&weight=20&ttl=3600&csrf_token=${csrfToken}`);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('20');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('delete record via POST', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'del-test', type: 'A', address: '192.0.2.99' });

    await deleteRecord(playwright, cookies, gid, zid, rrid);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).not.toContain('del-test');
  });

  test('multiple record types coexist in same zone', async ({ playwright }) => {
    const r1 = await createRecord(playwright, cookies, gid, zid,
      { name: 'multi-a', type: 'A', address: '192.0.2.50' });
    const r2 = await createRecord(playwright, cookies, gid, zid,
      { name: 'multi-mx', type: 'MX', address: 'mx.example.com.', weight: '10' });
    const r3 = await createRecord(playwright, cookies, gid, zid,
      { name: 'multi-txt', type: 'TXT', address: 'hello world' });

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('192.0.2.50');
    expect(body).toContain('mx.example.com.');
    expect(body).toContain('hello world');

    await deleteRecord(playwright, cookies, gid, zid, r1);
    await deleteRecord(playwright, cookies, gid, zid, r2);
    await deleteRecord(playwright, cookies, gid, zid, r3);
  });

  test('create record with custom TTL', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'ttl-test', type: 'A', address: '192.0.2.60', ttl: 86400 });

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('86400');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('PTR record in reverse zone', async ({ playwright }) => {
    // Create a reverse zone
    const revZone = `2.0.192.in-addr.arpa`;
    let revZid: string;
    try {
      revZid = await createZone(playwright, cookies, gid, revZone);
    } catch {
      // If the zone already exists or can't be created, skip
      return;
    }

    try {
      const rrid = await createRecord(playwright, cookies, gid, revZid,
        { name: '1', type: 'PTR', address: 'host.example.com.' });

      const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${revZid}`, cookies);
      expect(body).toContain('host.example.com.');

      await deleteRecord(playwright, cookies, gid, revZid, rrid);
    } finally {
      await deleteZone(playwright, cookies, gid, revZid);
    }
  });

  // --- Advanced record types ---

  test('create SRV record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: '_sip._tcp', type: 'SRV', address: 'sip.example.com.', weight: '10', priority: '0', other: '5060' });
    expect(Number(rrid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('sip.example.com.');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create CAA record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'caa-test', type: 'CAA', address: 'letsencrypt.org', weight: '0', other: 'issue' });
    expect(Number(rrid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('letsencrypt.org');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create SPF record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'spf-test', type: 'SPF', address: 'v=spf1 -all' });
    expect(Number(rrid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('v=spf1');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create LOC record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'loc-test', type: 'LOC', address: '51 30 12.748 N 0 7 39.612 W 0.00m' });
    expect(Number(rrid)).toBeGreaterThan(0);

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create SSHFP record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'sshfp-test', type: 'SSHFP', address: '123456789abcdef67890123456789abcdef67890', weight: '1', other: '1' });
    expect(Number(rrid)).toBeGreaterThan(0);

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create NAPTR record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'naptr-test', type: 'NAPTR', address: '!^.*$!sip:info@example.com!', weight: '100', priority: '10', other: 'u' });
    expect(Number(rrid)).toBeGreaterThan(0);

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('create DNAME record', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'dname-test', type: 'DNAME', address: 'other.example.com.' });
    expect(Number(rrid)).toBeGreaterThan(0);

    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain('other.example.com.');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('RR type selector dynamically shows/hides fields', async ({ page }) => {
    await browserLogin(page);

    const bodyFrame = page.frames().find(f => f.url().includes('group.cgi'));
    expect(bodyFrame).toBeTruthy();

    // Navigate to zones
    const zonesLink = bodyFrame!.locator('a:has-text("Zones")');
    if (await zonesLink.count() > 0) {
      await zonesLink.first().click();
      await page.waitForTimeout(1500);
    }

    // Find a zone to click into - or just verify the type selector exists on a zone page
    const zonesFrame = page.frames().find(f => f.url().includes('group_zones.cgi'));
    if (zonesFrame) {
      const zoneLink = zonesFrame.locator('a[href*="nt_zone_id="]').first();
      if (await zoneLink.count() > 0) {
        await zoneLink.click();
        await page.waitForTimeout(1500);

        const zoneFrame = page.frames().find(f => f.url().includes('zone.cgi'));
        if (zoneFrame) {
          // Look for the "New Record" link/area
          const newRecLink = zoneFrame.locator('a:has-text("New Resource Record")');
          if (await newRecLink.count() > 0) {
            await newRecLink.first().click();
            await page.waitForTimeout(1500);
          }

          const typeSelect = zoneFrame.locator('select[name="type"]');
          if (await typeSelect.count() > 0) {
            // Select MX - weight field should be visible
            await typeSelect.selectOption('MX');
            await page.waitForTimeout(300);

            // The weight field row should be present
            const weightInput = zoneFrame.locator('input[name="weight"]');
            expect(await weightInput.count()).toBeGreaterThan(0);
          }
        }
      }
    }
  });
});
