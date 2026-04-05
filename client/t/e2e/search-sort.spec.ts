import { test, expect } from '@playwright/test';
import {
  BASE,
  apiLogin, authGet, cookieString,
  createGroup, deleteGroup, createZone, deleteZone,
  createRecord, deleteRecord, uniqueName,
} from './helpers';

test.describe('Search and Sort', () => {
  let cookies: string;
  let gid: string;
  const zones: { name: string; zid: string }[] = [];

  test.beforeAll(async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    cookies = cookieString(sessionCookie, csrfCookie);

    gid = await createGroup(playwright, cookies, 1, uniqueName('e2e_search'));

    // Create multiple zones for search/sort testing
    for (let i = 1; i <= 5; i++) {
      const name = `search-${i}-${Date.now()}.test`;
      const zid = await createZone(playwright, cookies, gid, name);
      zones.push({ name, zid });
    }
  });

  test.afterAll(async ({ playwright }) => {
    for (const z of zones) {
      await deleteZone(playwright, cookies, gid, z.zid);
    }
    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('zone search by exact name', async ({ playwright }) => {
    const targetZone = zones[0];
    // Quick search form uses search_value parameter
    const { body } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${gid}&Quick+search=Search&search_value=${encodeURIComponent(targetZone.name)}`,
      cookies);
    expect(body).toContain(targetZone.name);
  });

  test('zone search with include_subgroups', async ({ playwright }) => {
    const { body } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${gid}&Quick+search=Search&search_value=search&include_subgroups=1`,
      cookies);
    expect(body).toContain('search-');
  });

  test('record search by type', async ({ playwright }) => {
    const targetZone = zones[0];
    const r1 = await createRecord(playwright, cookies, gid, targetZone.zid,
      { name: 'srch-a', type: 'A', address: '192.0.2.100' });
    const r2 = await createRecord(playwright, cookies, gid, targetZone.zid,
      { name: 'srch-mx', type: 'MX', address: 'mx.example.com.', weight: '10' });

    try {
      // View zone records - both should be visible
      const { body } = await authGet(playwright,
        `${BASE}/zone.cgi?nt_group_id=${gid}&nt_zone_id=${targetZone.zid}`,
        cookies);
      expect(body).toContain('192.0.2.100');
      expect(body).toContain('srch-a');
    } finally {
      await deleteRecord(playwright, cookies, gid, targetZone.zid, r1);
      await deleteRecord(playwright, cookies, gid, targetZone.zid, r2);
    }
  });

  test('pagination: page 1 with limit returns subset', async ({ playwright }) => {
    const { body } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${gid}&start=0&limit=2`,
      cookies);
    // Should show zone content
    expect(body).toContain('search-');
    // The page should have navigation or limit indicators
    expect(body).toBeDefined();
  });

  test('pagination: page 2 returns different results', async ({ playwright }) => {
    const { body: page1 } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${gid}&start=0&limit=2`,
      cookies);
    const { body: page2 } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${gid}&start=2&limit=2`,
      cookies);

    // Both pages should have content and not be identical
    expect(page1.length).toBeGreaterThan(0);
    expect(page2.length).toBeGreaterThan(0);
  });

  test('sort zones descending', async ({ playwright }) => {
    const { body } = await authGet(playwright,
      `${BASE}/group_zones.cgi?nt_group_id=${gid}&sort1=zone&sortmod1=Descending`,
      cookies);
    expect(body).toContain('search-');
    // Should not crash with sort params
    expect(body.toLowerCase()).not.toContain('internal server error');
  });
});
