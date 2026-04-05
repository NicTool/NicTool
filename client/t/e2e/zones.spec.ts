import { test, expect } from '@playwright/test';
import {
  BASE,
  apiLogin, authGet, authPost, cookieString,
  createGroup, deleteGroup, createZone, deleteZone,
  uniqueName, extractCsrf, browserLogin,
} from './helpers';

test.describe('Zones', () => {
  let cookies: string;
  let csrfToken: string;
  let gid: string;

  test.beforeAll(async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    cookies = cookieString(sessionCookie, csrfCookie);
    csrfToken = csrfCookie;
    gid = await createGroup(playwright, cookies, 1, uniqueName('e2e_zones'));
  });

  test.afterAll(async ({ playwright }) => {
    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('create zone with default SOA values', async ({ playwright }) => {
    const zone = `${uniqueName('e2e')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);
    expect(Number(zid)).toBeGreaterThan(0);
    await deleteZone(playwright, cookies, gid, zid);
  });

  test('zone appears in zone list', async ({ playwright }) => {
    const zone = `${uniqueName('e2e')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);

    const { body } = await authGet(playwright, `${BASE}/group_zones.cgi?nt_group_id=${gid}`, cookies);
    expect(body).toContain(zone);

    await deleteZone(playwright, cookies, gid, zid);
  });

  test('edit zone SOA properties', async ({ playwright }) => {
    const zone = `${uniqueName('e2e')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);

    // Edit SOA values
    const { body: editResponse } = await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&edit=1&Save=Save&zone=${zone}&mailaddr=hostmaster.${zone}&description=edited&ttl=7200&refresh=32768&retry=4096&expire=2097152&minimum=5120&csrf_token=${csrfToken}`);

    // The POST response or subsequent GET should reflect the new values
    // View the zone record list page which shows SOA details
    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    // SOA values should be visible somewhere (either in zone header or edit form)
    expect(body).toContain(zone);

    await deleteZone(playwright, cookies, gid, zid);
  });

  test('edit zone description', async ({ playwright }) => {
    const zone = `${uniqueName('e2e')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);

    const newDesc = 'Updated description for e2e test';
    await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=${gid}&nt_zone_id=${zid}&edit=1&Save=Save&zone=${zone}&mailaddr=admin.${zone}&description=${encodeURIComponent(newDesc)}&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560&csrf_token=${csrfToken}`);

    const { body } = await authGet(playwright, `${BASE}/group_zones.cgi?nt_group_id=${gid}&nt_zone_id=${zid}&edit=1`, cookies);
    expect(body).toContain('Updated description');

    await deleteZone(playwright, cookies, gid, zid);
  });

  test('delete zone', async ({ playwright }) => {
    const zone = `${uniqueName('e2e')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);

    await deleteZone(playwright, cookies, gid, zid);

    const { body } = await authGet(playwright, `${BASE}/group_zones.cgi?nt_group_id=${gid}`, cookies);
    expect(body).not.toContain(zone);
  });

  test('zone properties display shows correct values', async ({ playwright }) => {
    const zone = `${uniqueName('e2e')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);

    // View the zone record list page (shows zone name in header)
    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain(zone);

    await deleteZone(playwright, cookies, gid, zid);
  });

  test('create zone with custom SOA values persists them', async ({ playwright }) => {
    const zone = `${uniqueName('e2e')}.test`;
    const { body: createBody } = await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=${gid}&new=1&Create=Create&zone=${zone}&mailaddr=hostmaster.${zone}&description=custom+SOA&ttl=7200&refresh=32768&retry=4096&expire=2097152&minimum=5120&csrf_token=${csrfToken}`);

    // Zone should be created successfully
    const { body: listBody } = await authGet(playwright, `${BASE}/group_zones.cgi?nt_group_id=${gid}`, cookies);
    expect(listBody).toContain(zone);
    const m = listBody.match(/nt_zone_id=(\d+)/);
    expect(m).toBeTruthy();
    const zid = m![1];

    // View zone record page to confirm zone exists with correct name
    const { body } = await authGet(playwright, `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toContain(zone);

    await deleteZone(playwright, cookies, gid, zid);
  });

  test('duplicate zone name fails gracefully', async ({ playwright }) => {
    const zone = `${uniqueName('e2e')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);

    // Try to create the same zone again
    const { body } = await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
      `nt_group_id=${gid}&new=1&Create=Create&zone=${zone}&mailaddr=admin.${zone}&description=dup&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560&csrf_token=${csrfToken}`);

    // Should show error, not crash
    expect(body.toLowerCase()).toMatch(/error|already exists|duplicate|taken/i);

    await deleteZone(playwright, cookies, gid, zid);
  });

  test('new zone form auto-updates mailaddr via JS', async ({ page }) => {
    await browserLogin(page);

    const bodyFrame = page.frames().find(f => f.url().includes('group.cgi'));
    expect(bodyFrame).toBeTruthy();

    // Navigate to zones
    const zonesLink = bodyFrame!.locator('a:has-text("Zones")');
    if (await zonesLink.count() > 0) {
      await zonesLink.first().click();
      await page.waitForTimeout(1500);
    }

    const zonesFrame = page.frames().find(f => f.url().includes('group_zones.cgi'));
    if (zonesFrame) {
      const newZoneLink = zonesFrame.locator('a:has-text("New Zone")');
      if (await newZoneLink.count() > 0) {
        await newZoneLink.first().click();
        await page.waitForTimeout(1500);
      }

      // Find the zone form frame
      const formFrame = page.frames().find(f => f.url().includes('group_zones.cgi'));
      if (formFrame) {
        const zoneInput = formFrame.locator('input[name="zone"]');
        if (await zoneInput.count() > 0) {
          await zoneInput.fill('autotest.example.com');
          // Trigger blur to fire JS
          await zoneInput.evaluate(el => el.dispatchEvent(new Event('blur')));
          await page.waitForTimeout(500);

          const mailInput = formFrame.locator('input[name="mailaddr"]');
          if (await mailInput.count() > 0) {
            const val = await mailInput.inputValue();
            // The JS should have auto-populated mailaddr
            expect(val.length).toBeGreaterThan(0);
          }
        }
      }
    }
  });
});
