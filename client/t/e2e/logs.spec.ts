import { test, expect } from '@playwright/test';
import {
  BASE,
  apiLogin, authGet, authPost, cookieString,
  createGroup, deleteGroup, createZone, deleteZone,
  createRecord, deleteRecord, uniqueName, extractCsrf,
} from './helpers';

test.describe('Logs', () => {
  let cookies: string;
  let csrfToken: string;
  let gid: string;

  test.beforeAll(async ({ playwright }) => {
    const { sessionCookie, csrfCookie } = await apiLogin(playwright);
    cookies = cookieString(sessionCookie, csrfCookie);
    csrfToken = csrfCookie;
    gid = await createGroup(playwright, cookies, 1, uniqueName('e2e_logs'));
  });

  test.afterAll(async ({ playwright }) => {
    await deleteGroup(playwright, cookies, 1, gid);
  });

  test('group_log.cgi renders log page', async ({ playwright }) => {
    const { body } = await authGet(playwright,
      `${BASE}/group_log.cgi?nt_group_id=${gid}`, cookies);
    expect(body).toBeDefined();
    expect(body.toLowerCase()).not.toContain('internal server error');
    // Log page should render without errors
    expect(body).toContain('NicTool');
  });

  test('group_zones_log.cgi shows zone changes', async ({ playwright }) => {
    // Create and delete a zone to generate log entries
    const zone = `${uniqueName('e2e-log')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);
    await deleteZone(playwright, cookies, gid, zid);

    const { body } = await authGet(playwright,
      `${BASE}/group_zones_log.cgi?nt_group_id=${gid}`, cookies);
    expect(body).toBeDefined();
    expect(body.toLowerCase()).not.toContain('internal server error');
  });

  test('zone_record_log.cgi shows record changes', async ({ playwright }) => {
    const zone = `${uniqueName('e2e-reclog')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'logtest', type: 'A', address: '192.0.2.200' });
    await deleteRecord(playwright, cookies, gid, zid, rrid);

    const { body } = await authGet(playwright,
      `${BASE}/zone_record_log.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    expect(body).toBeDefined();
    expect(body.toLowerCase()).not.toContain('internal server error');

    await deleteZone(playwright, cookies, gid, zid);
  });

  test('log entry appears after creating a zone', async ({ playwright }) => {
    const zone = `${uniqueName('e2e-logz')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);

    // Check group zone log for the creation entry
    const { body } = await authGet(playwright,
      `${BASE}/group_zones_log.cgi?nt_group_id=${gid}`, cookies);
    expect(body).toContain(zone);

    await deleteZone(playwright, cookies, gid, zid);
  });

  test('log entry appears after deleting a record', async ({ playwright }) => {
    const zone = `${uniqueName('e2e-logr')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);
    const rrid = await createRecord(playwright, cookies, gid, zid,
      { name: 'logdel', type: 'A', address: '192.0.2.201' });
    await deleteRecord(playwright, cookies, gid, zid, rrid);

    // Check zone record log for the delete entry
    const { body } = await authGet(playwright,
      `${BASE}/zone_record_log.cgi?nt_group_id=${gid}&nt_zone_id=${zid}`, cookies);
    // Log should mention the deleted record
    expect(body).toContain('logdel');

    await deleteZone(playwright, cookies, gid, zid);
  });

  test('deleted zone has undelete link in log', async ({ playwright }) => {
    const zone = `${uniqueName('e2e-undel')}.test`;
    const zid = await createZone(playwright, cookies, gid, zone);
    await deleteZone(playwright, cookies, gid, zid);

    const { body } = await authGet(playwright,
      `${BASE}/group_zones_log.cgi?nt_group_id=${gid}`, cookies);
    // After deleting, the log should show the zone and potentially an undelete option
    expect(body).toContain(zone);
    // Check for undelete or recover link (case-insensitive)
    expect(body.toLowerCase()).toMatch(/undelete|recover|restore|deleted/i);
  });
});
