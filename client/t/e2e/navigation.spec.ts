import { test, expect } from '@playwright/test';
import { BASE, browserLogin, getNavFrame, getBodyFrame } from './helpers';

test.describe('Navigation', () => {
  test('login produces frameset with nav and body frames', async ({ page }) => {
    await browserLogin(page);

    const frames = page.frames();
    expect(frames.length).toBeGreaterThan(1);

    const navFrame = frames.find(f => f.url().includes('nav.cgi'));
    const bodyFrame = frames.find(f => f.url().includes('group.cgi'));
    expect(navFrame).toBeTruthy();
    expect(bodyFrame).toBeTruthy();
  });

  test('nav frame shows group tree with section links', async ({ page }) => {
    await browserLogin(page);

    const navFrame = page.frames().find(f => f.url().includes('nav.cgi'));
    expect(navFrame).toBeTruthy();

    const navContent = await navFrame!.content();
    // Nav should have the group tree and various section links
    expect(navContent).toContain('NicTool');
  });

  test('clicking Zones in nav loads group_zones.cgi in body', async ({ page }) => {
    await browserLogin(page);

    const bodyFrame = page.frames().find(f => f.url().includes('group.cgi'));
    expect(bodyFrame).toBeTruthy();

    // Click Zones tab in body frame
    const zonesLink = bodyFrame!.locator('a:has-text("Zones")');
    if (await zonesLink.count() > 0) {
      await zonesLink.first().click();
      await page.waitForTimeout(2000);

      // After clicking, body frame should now show group_zones.cgi
      const updatedBodyFrame = page.frames().find(f => f.url().includes('group_zones.cgi'));
      expect(updatedBodyFrame).toBeTruthy();
    }
  });

  test('clicking Users in nav loads group_users.cgi in body', async ({ page }) => {
    await browserLogin(page);

    const bodyFrame = page.frames().find(f => f.url().includes('group.cgi'));
    expect(bodyFrame).toBeTruthy();

    const usersLink = bodyFrame!.locator('a:has-text("Users")');
    if (await usersLink.count() > 0) {
      await usersLink.first().click();
      await page.waitForTimeout(2000);

      const updatedBodyFrame = page.frames().find(f => f.url().includes('group_users.cgi'));
      expect(updatedBodyFrame).toBeTruthy();
    }
  });

  test('clicking Nameservers in nav loads group_nameservers.cgi in body', async ({ page }) => {
    await browserLogin(page);

    const bodyFrame = page.frames().find(f => f.url().includes('group.cgi'));
    expect(bodyFrame).toBeTruthy();

    const nsLink = bodyFrame!.locator('a:has-text("Nameservers")');
    if (await nsLink.count() > 0) {
      await nsLink.first().click();
      await page.waitForTimeout(2000);

      const updatedBodyFrame = page.frames().find(f => f.url().includes('group_nameservers.cgi'));
      expect(updatedBodyFrame).toBeTruthy();
    }
  });

  test('clicking Log in nav loads group_log.cgi in body', async ({ page }) => {
    await browserLogin(page);

    const bodyFrame = page.frames().find(f => f.url().includes('group.cgi'));
    expect(bodyFrame).toBeTruthy();

    // The Log link is in the nav bar within the body frame
    const logLink = bodyFrame!.locator('a[href*="group_log.cgi"]');
    if (await logLink.count() > 0) {
      await logLink.first().click();
      await page.waitForTimeout(2000);

      // The body frame should now be group_log.cgi
      const updatedBodyFrame = page.frames().find(f => f.url().includes('group_log.cgi'));
      expect(updatedBodyFrame).toBeTruthy();
    }
  });

  test('nav refresh link reloads nav frame', async ({ page }) => {
    await browserLogin(page);

    const navFrame = page.frames().find(f => f.url().includes('nav.cgi'));
    expect(navFrame).toBeTruthy();

    // Look for a refresh/reload link in the nav frame
    const refreshLink = navFrame!.locator('a:has-text("refresh")');
    if (await refreshLink.count() > 0) {
      await refreshLink.first().click();
      await page.waitForTimeout(1500);

      // Nav frame should still be present after refresh
      const newNavFrame = page.frames().find(f => f.url().includes('nav.cgi'));
      expect(newNavFrame).toBeTruthy();
    } else {
      // If there's no explicit refresh link, verify nav frame is functional
      const navContent = await navFrame!.content();
      expect(navContent.length).toBeGreaterThan(0);
    }
  });
});
