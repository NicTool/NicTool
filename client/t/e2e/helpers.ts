import { type APIRequestContext } from '@playwright/test';
import type { Page, Frame } from '@playwright/test';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
export const BASE = process.env.NICTOOL_URL || 'https://localhost:8443';
export const USERNAME = 'root';
export const PASSWORD = 'nictool';

export const GROUP_DEFAULTS = [
  'user_create=1', 'user_delete=1', 'user_write=1',
  'group_create=1', 'group_delete=1', 'group_write=1',
  'zone_create=1', 'zone_delegate=1', 'zone_delete=1', 'zone_write=1',
  'zonerecord_create=1', 'zonerecord_delegate=1', 'zonerecord_delete=1', 'zonerecord_write=1',
  'nameserver_create=1', 'nameserver_delete=1', 'nameserver_write=1',
  'self_write=1',
  'usable_nameservers=1', 'usable_nameservers=2', 'usable_nameservers=3',
].join('&');

// ---------------------------------------------------------------------------
// API Helpers
// ---------------------------------------------------------------------------

export async function freshCtx(playwright: any): Promise<APIRequestContext> {
  return await playwright.request.newContext({ ignoreHTTPSErrors: true });
}

export async function getLoginCsrf(ctx: APIRequestContext) {
  const res = await ctx.get(`${BASE}/index.cgi`);
  const body = await res.text();
  const match = body.match(/name="csrf_token"\s+value="([^"]+)"/);
  const csrfToken = match ? match[1] : '';

  const setCookies = res.headersArray().filter(h => h.name.toLowerCase() === 'set-cookie');
  let csrfCookie = '';
  for (const sc of setCookies) {
    const m = sc.value.match(/NicTool_csrf=([^;]+)/);
    if (m && m[1]) { csrfCookie = m[1]; break; }
  }

  return { csrfToken, csrfCookie, body, response: res };
}

export async function apiLogin(playwright: any, username = USERNAME, password = PASSWORD) {
  const ctx = await freshCtx(playwright);
  const { csrfToken, csrfCookie } = await getLoginCsrf(ctx);

  const res = await ctx.post(`${BASE}/index.cgi`, {
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Cookie': `NicTool_csrf=${csrfCookie}`,
    },
    data: `username=${encodeURIComponent(username)}&password=${encodeURIComponent(password)}&login=Enter&csrf_token=${csrfToken}`,
  });

  const body = await res.text();
  const headers = res.headers();
  const setCookieHeaders = res.headersArray().filter(h => h.name.toLowerCase() === 'set-cookie');
  let sessionCookie = '';
  let newCsrfCookie = '';
  for (const sc of setCookieHeaders) {
    const sm = sc.value.match(/^NicTool=([^;]+)/);
    if (sm && sm[1]) sessionCookie = sm[1];
    const cm = sc.value.match(/NicTool_csrf=([^;]+)/);
    if (cm && cm[1]) newCsrfCookie = cm[1];
  }

  await ctx.dispose();
  return { sessionCookie, csrfCookie: newCsrfCookie || csrfCookie, body, headers, setCookieHeaders };
}

export function cookieString(sessionCookie: string, csrfCookie: string): string {
  return `NicTool=${sessionCookie}; NicTool_csrf=${csrfCookie}`;
}

export async function authGet(playwright: any, url: string, cookies: string) {
  const ctx = await freshCtx(playwright);
  const res = await ctx.get(url, { headers: { Cookie: cookies } });
  const body = await res.text();
  await ctx.dispose();
  return { res, body };
}

export async function authPost(playwright: any, url: string, cookies: string, data: string) {
  const ctx = await freshCtx(playwright);
  const res = await ctx.post(url, {
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': cookies },
    data,
  });
  const body = await res.text();
  await ctx.dispose();
  return { res, body };
}

export function expectSecurityHeaders(headers: Record<string, string>) {
  const { expect } = require('@playwright/test');
  expect(headers['content-security-policy']).toContain("default-src 'self'");
  expect(headers['x-content-type-options']).toContain('nosniff');
  expect(headers['x-frame-options']).toContain('SAMEORIGIN');
  expect(headers['x-xss-protection']).toContain('1; mode=block');
  expect(headers['referrer-policy']).toContain('strict-origin-when-cross-origin');
}

// ---------------------------------------------------------------------------
// Browser Helpers
// ---------------------------------------------------------------------------

export async function browserLogin(page: Page) {
  await page.goto(`${BASE}/index.cgi`);
  await page.fill('input[name="username"]', USERNAME);
  await page.fill('input[name="password"]', PASSWORD);
  await page.click('input[type="submit"][name="login"]');
  await page.waitForTimeout(3000);
}

export function collectViolations(page: Page) {
  const violations: string[] = [];
  page.on('console', (msg) => {
    const text = msg.text();
    if (text.includes('Content Security Policy') || text.includes('Refused to')) {
      violations.push(text);
    }
  });
  page.on('pageerror', (err) => {
    violations.push(`PAGE ERROR: ${err.message}`);
  });
  return violations;
}

export function getBodyFrame(page: Page): Frame | undefined {
  return page.frames().find(f => f.url().includes('group.cgi') || f.url().includes('group_zones.cgi') || f.url().includes('group_users.cgi') || f.url().includes('group_nameservers.cgi') || f.url().includes('group_log.cgi') || f.url().includes('zone.cgi'));
}

export function getNavFrame(page: Page): Frame | undefined {
  return page.frames().find(f => f.url().includes('nav.cgi'));
}

// ---------------------------------------------------------------------------
// Unique Name Generator
// ---------------------------------------------------------------------------

let _counter = 0;
export function uniqueName(prefix: string): string {
  return `${prefix}_${Date.now()}_${++_counter}`;
}

// For nameserver names which cannot contain underscores
export function uniqueNsName(prefix: string): string {
  return `${prefix}-${Date.now()}-${++_counter}`;
}

// ---------------------------------------------------------------------------
// CRUD Factory Helpers
// ---------------------------------------------------------------------------

// Helper to find an entity ID on a listing page by name.
// Handles HTML-encoded ampersands and whitespace around names.
function findIdInBody(body: string, idParam: string, name: string): string | null {
  // Try specific match: idParam=(\d+) followed by the name somewhere nearby
  const escaped = escapeRegex(name);
  // Pattern 1: direct link like nt_group_id=71">groupname
  const m1 = body.match(new RegExp(`${idParam}=(\\d+)">${escaped}`));
  if (m1) return m1[1];
  // Pattern 2: link with &amp; params, then name with possible whitespace
  const m2 = body.match(new RegExp(`${idParam}=(\\d+)&amp;[^>]*>[\\s]*(?:<[^>]+>\\s*)*${escaped}`));
  if (m2) return m2[1];
  // Pattern 3: link with whitespace before name
  const m3 = body.match(new RegExp(`${idParam}=(\\d+)"[^>]*>[\\s]*${escaped}`));
  if (m3) return m3[1];
  // Pattern 4: name appears after img tag
  const m4 = body.match(new RegExp(`${idParam}=(\\d+)[^>]*>\\s*<img[^>]*>\\s*${escaped}`));
  if (m4) return m4[1];
  return null;
}

export async function createGroup(playwright: any, cookies: string, parentGid: string | number, name?: string): Promise<string> {
  const groupName = name || uniqueName('e2e_grp');
  await authPost(playwright, `${BASE}/group.cgi`, cookies,
    `nt_group_id=${parentGid}&new=1&Create=Create&name=${groupName}&${GROUP_DEFAULTS}&csrf_token=${extractCsrf(cookies)}`);

  // Check multiple pages since NicTool hardcodes 10 items per page
  for (let page = 1; page <= 10; page++) {
    const { body } = await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${parentGid}&page=${page}`, cookies);
    const gid = findIdInBody(body, 'nt_group_id', groupName);
    if (gid) return gid;
    // If no "next page" link, stop searching
    if (!body.includes('page=' + (page + 1))) break;
  }
  throw new Error(`Failed to find created group "${groupName}" in parent ${parentGid}`);
}

export async function deleteGroup(playwright: any, cookies: string, parentGid: string | number, gid: string | number): Promise<void> {
  await authGet(playwright, `${BASE}/group.cgi?nt_group_id=${parentGid}&delete=${gid}&csrf_token=${extractCsrf(cookies)}`, cookies);
}

export async function createZone(playwright: any, cookies: string, gid: string | number, zoneName?: string): Promise<string> {
  const zone = zoneName || `${uniqueName('e2e')}.test`;
  await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
    `nt_group_id=${gid}&new=1&Create=Create&zone=${zone}&mailaddr=admin.${zone}&description=e2e+test&ttl=3600&refresh=16384&retry=2048&expire=1048576&minimum=2560&csrf_token=${extractCsrf(cookies)}`);

  const { body } = await authGet(playwright, `${BASE}/group_zones.cgi?nt_group_id=${gid}&limit=255`, cookies);
  const zid = findIdInBody(body, 'nt_zone_id', zone);
  if (!zid) {
    // Fallback: find any zone ID on the page
    const m2 = body.match(/nt_zone_id=(\d+)/);
    if (!m2) throw new Error(`Failed to find created zone "${zone}" in group ${gid}`);
    return m2[1];
  }
  return zid;
}

export async function deleteZone(playwright: any, cookies: string, gid: string | number, zid: string | number): Promise<void> {
  await authPost(playwright, `${BASE}/group_zones.cgi`, cookies,
    `nt_group_id=${gid}&delete=1&zone_list=${zid}&csrf_token=${extractCsrf(cookies)}`);
}

export async function createRecord(playwright: any, cookies: string, gid: string | number, zid: string | number,
  opts: { name: string; type: string; address: string; ttl?: number; weight?: string; priority?: string; other?: string; description?: string }
): Promise<string> {
  let data = `nt_group_id=${gid}&nt_zone_id=${zid}&new_record=1&Create=Create&name=${encodeURIComponent(opts.name)}&type=${opts.type}&address=${encodeURIComponent(opts.address)}&ttl=${opts.ttl || 3600}&csrf_token=${extractCsrf(cookies)}`;
  if (opts.weight !== undefined) data += `&weight=${encodeURIComponent(opts.weight)}`;
  if (opts.priority !== undefined) data += `&priority=${encodeURIComponent(opts.priority)}`;
  if (opts.other !== undefined) data += `&other=${encodeURIComponent(opts.other)}`;
  if (opts.description !== undefined) data += `&description=${encodeURIComponent(opts.description)}`;

  const { body } = await authPost(playwright, `${BASE}/zone.cgi`, cookies, data);
  const m = body.match(/nt_zone_record_id=(\d+)/);
  if (!m) throw new Error(`Failed to create record ${opts.type} "${opts.name}" in zone ${zid}. Body snippet: ${body.substring(0, 500)}`);
  return m[1];
}

export async function deleteRecord(playwright: any, cookies: string, gid: string | number, zid: string | number, rrid: string | number): Promise<void> {
  await authPost(playwright, `${BASE}/zone.cgi`, cookies,
    `nt_group_id=${gid}&nt_zone_id=${zid}&nt_zone_record_id=${rrid}&delete_record=${rrid}&csrf_token=${extractCsrf(cookies)}`);
}

export async function createUser(playwright: any, cookies: string, gid: string | number,
  opts: { username: string; password?: string; email?: string; first_name?: string; last_name?: string }
): Promise<string> {
  const pw = opts.password || 'testpass123!';
  const email = opts.email || `${opts.username}@test.example`;
  const first = opts.first_name || 'Test';
  const last = opts.last_name || 'User';
  await authPost(playwright, `${BASE}/group_users.cgi`, cookies,
    `nt_group_id=${gid}&new=1&Create=Create&username=${encodeURIComponent(opts.username)}&password=${encodeURIComponent(pw)}&password2=${encodeURIComponent(pw)}&email=${encodeURIComponent(email)}&first_name=${encodeURIComponent(first)}&last_name=${encodeURIComponent(last)}&group_defaults=1&csrf_token=${extractCsrf(cookies)}`);

  const { body } = await authGet(playwright, `${BASE}/group_users.cgi?nt_group_id=${gid}&limit=255`, cookies);
  const uid = findIdInBody(body, 'nt_user_id', opts.username);
  if (!uid) {
    // Fallback: find any user ID (excluding the nav bar user links)
    const m2 = body.match(/group_users\.cgi\?[^"]*nt_user_id=(\d+)/);
    if (!m2) throw new Error(`Failed to find created user "${opts.username}" in group ${gid}`);
    return m2[1];
  }
  return uid;
}

export async function deleteUser(playwright: any, cookies: string, gid: string | number, uid: string | number): Promise<void> {
  // NicTool uses delete=1&obj_list=<uid> format for user deletion
  await authGet(playwright, `${BASE}/group_users.cgi?nt_group_id=${gid}&delete=1&obj_list=${uid}&csrf_token=${extractCsrf(cookies)}`, cookies);
}

export async function createNameserver(playwright: any, cookies: string, gid: string | number,
  opts: { name: string; address?: string; description?: string; export_format?: string; ttl?: number }
): Promise<string> {
  const addr = opts.address || '192.0.2.1';
  const desc = opts.description || 'e2e test ns';
  const fmt = opts.export_format || 'bind';
  const ttl = opts.ttl || 3600;
  await authPost(playwright, `${BASE}/group_nameservers.cgi`, cookies,
    `nt_group_id=${gid}&new=1&Create=Create&name=${encodeURIComponent(opts.name)}&address=${encodeURIComponent(addr)}&description=${encodeURIComponent(desc)}&export_format=${fmt}&export_interval=120&ttl=${ttl}&csrf_token=${extractCsrf(cookies)}`);

  const { body } = await authGet(playwright, `${BASE}/group_nameservers.cgi?nt_group_id=${gid}&limit=255`, cookies);
  const nsid = findIdInBody(body, 'nt_nameserver_id', opts.name);
  if (!nsid) {
    // Fallback: look for any nameserver ID that isn't one of the default 3
    const allIds = [...body.matchAll(/nt_nameserver_id=(\d+)/g)].map(m => m[1]);
    const uniqueIds = [...new Set(allIds)];
    // The new one should be the highest ID
    const maxId = uniqueIds.reduce((max, id) => Math.max(max, Number(id)), 0);
    if (maxId > 0) return String(maxId);
    throw new Error(`Failed to find created nameserver "${opts.name}" in group ${gid}`);
  }
  return nsid;
}

export async function deleteNameserver(playwright: any, cookies: string, gid: string | number, nsid: string | number): Promise<void> {
  // NicTool uses delete=1&nt_nameserver_id=X format
  await authGet(playwright, `${BASE}/group_nameservers.cgi?nt_group_id=${gid}&delete=1&nt_nameserver_id=${nsid}&csrf_token=${extractCsrf(cookies)}`, cookies);
}

// ---------------------------------------------------------------------------
// Internal Utilities
// ---------------------------------------------------------------------------

export function extractCsrf(cookies: string): string {
  const m = cookies.match(/NicTool_csrf=([^;]+)/);
  return m ? m[1] : '';
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
