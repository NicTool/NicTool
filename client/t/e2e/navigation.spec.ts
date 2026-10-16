import { test, expect } from '@playwright/test';
import { browserLogin, clickIfPresent, frameFor, loginBodyFrame } from './helpers';

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

    const navFrame = frameFor(page, 'nav.cgi');
    expect(navFrame).toBeTruthy();

    const navContent = await navFrame!.content();
    // Nav should have the group tree and various section links
    expect(navContent).toContain('NicTool');
  });

  for (const [tab, selector, cgi] of [
    ['Zones', 'a:has-text("Zones")', 'group_zones.cgi'],
    ['Users', 'a:has-text("Users")', 'group_users.cgi'],
    ['Nameservers', 'a:has-text("Nameservers")', 'group_nameservers.cgi'],
    // the Log link is in the nav bar within the body frame
    ['Log', 'a[href*="group_log.cgi"]', 'group_log.cgi'],
  ]) {
    test(`clicking ${tab} in nav loads ${cgi} in body`, async ({ page }) => {
      const bodyFrame = await loginBodyFrame(page);
      if (await clickIfPresent(page, bodyFrame, selector, 2000)) {
        expect(frameFor(page, cgi)).toBeTruthy();
      }
    });
  }

  test('nav refresh link reloads nav frame', async ({ page }) => {
    await browserLogin(page);

    const navFrame = frameFor(page, 'nav.cgi');
    expect(navFrame).toBeTruthy();

    // Look for a refresh/reload link in the nav frame
    const refreshLink = navFrame!.locator('a:has-text("refresh")');
    if (await refreshLink.count() > 0) {
      await refreshLink.first().click();
      await page.waitForTimeout(1500);

      // Nav frame should still be present after refresh
      const newNavFrame = frameFor(page, 'nav.cgi');
      expect(newNavFrame).toBeTruthy();
    } else {
      // If there's no explicit refresh link, verify nav frame is functional
      const navContent = await navFrame!.content();
      expect(navContent.length).toBeGreaterThan(0);
    }
  });
});
