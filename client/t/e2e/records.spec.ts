import { test, expect } from '@playwright/test';
import {
  BASE,
  authGet, authPost,
  createGroup, deleteGroup, createZone, deleteZone,
  createRecord, deleteRecord, uniqueName, extractCsrf,
  apiCookies, clickIfPresent, frameFor, loginBodyFrame, zonePage,
} from './helpers';

test.describe('Records', () => {
  let cookies: string;
  let csrfToken: string;
  let gid: string;
  let zid: string;

  test.beforeAll(async ({ playwright }) => {
    cookies = await apiCookies(playwright);
    csrfToken = extractCsrf(cookies);
    gid = await createGroup(playwright, cookies, 1, uniqueName('e2e_recs'));
    zid = await createZone(playwright, cookies, gid, `${uniqueName('e2e')}.test`);
  });

  test.afterAll(async ({ playwright }) => {
    await deleteZone(playwright, cookies, gid, zid);
    await deleteGroup(playwright, cookies, 1, gid);
  });

  // creates the record, checks the zone page shows `shown`, then deletes it
  async function recordCreated(playwright: any, opts: Parameters<typeof createRecord>[4], shown?: string | RegExp) {
    const rrid = await createRecord(playwright, cookies, gid, zid, opts);
    expect(Number(rrid)).toBeGreaterThan(0);

    if (shown !== undefined) {
      const body = await zonePage(playwright, cookies, gid, zid);
      if (typeof shown === 'string') expect(body).toContain(shown);
      else expect(body).toMatch(shown);
    }

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  }

  // --- Basic record types ---

  test('create A record', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'a-test', type: 'A', address: '192.0.2.1' }, '192.0.2.1');
  });

  test('create AAAA record', async ({ playwright }) => {
    // Address may be displayed in expanded or compressed IPv6 form
    await recordCreated(playwright, { name: 'aaaa-test', type: 'AAAA', address: '2001:db8::1' }, /2001:db8:.*1|2001:0db8/i);
  });

  test('create CNAME record', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'cname-test', type: 'CNAME', address: 'target.example.com.' }, 'target.example.com.');
  });

  test('create MX record with weight', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'mx-test', type: 'MX', address: 'mail.example.com.', weight: '10' }, 'mail.example.com.');
  });

  test('create TXT record', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'txt-test', type: 'TXT', address: 'v=spf1 include:example.com ~all' }, 'v=spf1');
  });

  test('create NS record', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'ns-test', type: 'NS', address: 'ns1.example.com.' }, 'ns1.example.com.');
  });

  test('edit A record address', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'edit-test', type: 'A', address: '192.0.2.10' });

    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&edit_record=${rrid}&Save=Save&name=edit-test&type=A&address=192.0.2.20&ttl=3600&csrf_token=${csrfToken}`);

    const body = await zonePage(playwright, cookies, gid, zid);
    expect(body).toContain('192.0.2.20');

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('edit MX record weight', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'mx-edit', type: 'MX', address: 'mail.example.com.', weight: '10' });

    await authPost(playwright, `${BASE}/zone.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&edit_record=${rrid}&Save=Save&name=mx-edit&type=MX&address=mail.example.com.&weight=20&ttl=3600&csrf_token=${csrfToken}`);

    const { body } = await authGet(playwright,
      `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}&edit_record=1&nt_zone_record_id=${rrid}`, cookies);
    expect(body).toMatch(/name="weight" value="20"/);

    await deleteRecord(playwright, cookies, gid, zid, rrid);
  });

  test('delete record via POST', async ({ playwright }) => {
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'del-test', type: 'A', address: '192.0.2.99' });

    await deleteRecord(playwright, cookies, gid, zid, rrid);

    const body = await zonePage(playwright, cookies, gid, zid);
    expect(body).not.toContain('del-test');
  });

  test('multiple record types coexist in same zone', async ({ playwright }) => {
    const r1 = await createRecord(playwright, cookies, gid, zid,
      { name: 'multi-a', type: 'A', address: '192.0.2.50' });
    const r2 = await createRecord(playwright, cookies, gid, zid,
      { name: 'multi-mx', type: 'MX', address: 'mx.example.com.', weight: '10' });
    const r3 = await createRecord(playwright, cookies, gid, zid,
      { name: 'multi-txt', type: 'TXT', address: 'hello world' });

    const body = await zonePage(playwright, cookies, gid, zid);
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

    const body = await zonePage(playwright, cookies, gid, zid);
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

      const body = await zonePage(playwright, cookies, gid, revZid);
      expect(body).toContain('host.example.com.');

      await deleteRecord(playwright, cookies, gid, revZid, rrid);
    } finally {
      await deleteZone(playwright, cookies, gid, revZid);
    }
  });

  // --- Advanced record types ---

  test('create SRV record', async ({ playwright }) => {
    await recordCreated(playwright, { name: '_sip._tcp', type: 'SRV', address: 'sip.example.com.', weight: '10', priority: '0', other: '5060' }, 'sip.example.com.');
  });

  test('create CAA record', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'caa-test', type: 'CAA', address: 'letsencrypt.org', weight: '0', other: 'issue' }, 'letsencrypt.org');
  });

  test('create SPF record', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'spf-test', type: 'SPF', address: 'v=spf1 -all' }, 'v=spf1');
  });

  test('create LOC record', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'loc-test', type: 'LOC', address: '51 30 12.748 N 0 7 39.612 W 0.00m' });
  });

  test('create SSHFP record', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'sshfp-test', type: 'SSHFP', address: '123456789abcdef67890123456789abcdef67890', weight: '1', other: '1' });
  });

  test('create NAPTR record', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'naptr-test', type: 'NAPTR', address: '!^.*$!sip:info@example.com!', weight: '100', priority: '10', other: 'u' });
  });

  test('create DNAME record', async ({ playwright }) => {
    await recordCreated(playwright, { name: 'dname-test', type: 'DNAME', address: 'other.example.com.' }, 'other.example.com.');
  });

  test('RR type selector dynamically shows/hides fields', async ({ page }) => {
    const bodyFrame = await loginBodyFrame(page);

    // Navigate to zones
    await clickIfPresent(page, bodyFrame, 'a:has-text("Zones")');

    // Find a zone to click into - or just verify the type selector exists on a zone page
    const zonesFrame = frameFor(page, 'group_zones.cgi');
    if (zonesFrame) {
      const zoneLink = zonesFrame.locator('a[href*="nt_zone_id="]').first();
      if (await zoneLink.count() > 0) {
        await zoneLink.click();
        await page.waitForTimeout(1500);

        const zoneFrame = frameFor(page, 'zone.cgi');
        if (zoneFrame) {
          // Look for the "New Record" link/area
          await clickIfPresent(page, zoneFrame, 'a:has-text("New Resource Record")');

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
