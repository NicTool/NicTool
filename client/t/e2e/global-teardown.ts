import { request } from '@playwright/test';
import {
  BASE, apiLogin, cookieString, authGet,
  deleteGroup, deleteZone, deleteUser, deleteNameserver,
} from './helpers';

// ---------------------------------------------------------------------------
// Remove every entity the suite created, whether or not the test that made it
// reached its own cleanup lines. Anything a test failure strands would
// otherwise accumulate across runs until the 10-row listing pages hide what
// the helpers look for.
//
// Only names carrying the uniqueName()/uniqueNsName() signature — a 13-digit
// epoch-milliseconds timestamp between separators — are touched, so seeded
// fixtures and real data are never candidates. delete_group refuses non-empty
// groups, so each group's zones, users, and nameservers go first and
// sub-groups are cleaned recursively.
// ---------------------------------------------------------------------------

const E2E_NAME = /[_-](\d{13})[_-]\d+/;

// Entities younger than this are left alone: they may belong to a suite run
// happening in parallel against the same server, and deleting a group in the
// window between that run's createGroup and createUser corrupts its state.
// Stale strays are harmless in the meantime — the exact-match searches the
// helpers use cannot be hidden by leftovers — so deferring their removal to
// a later session costs nothing.
const MAX_AGE_MS = Number(process.env.NICTOOL_E2E_CLEAN_AGE_MS || 30 * 60 * 1000);

function isStaleE2eName(text: string): boolean {
  const m = text.match(E2E_NAME);
  return !!m && Date.now() - Number(m[1]) > MAX_AGE_MS;
}

/** (id, name) pairs of stale e2e-created entities linked from a listing page. */
function extractRows(html: string, idParam: string): Map<string, string> {
  const rows = new Map<string, string>();
  // Listing rows link the entity name: <a href="cgi?...nt_x_id=ID...">NAME</a>,
  // sometimes with an icon before the text and params after the id (the user
  // list appends nt_group_id). Action links are excluded by their tails.
  const re = new RegExp(
    `${idParam}=(\\d+)((?:&amp;[^"]*)?)"[^>]*>\\s*(?:<img[^>]*>\\s*)*([^<]{1,80}?)\\s*<`, 'g');
  let m;
  while ((m = re.exec(html)) !== null) {
    const [, id, tail, text] = m;
    if (/delete|csrf_token|new=|edit/.test(tail)) continue;
    if (isStaleE2eName(text)) rows.set(id, text);
  }
  return rows;
}

/** Walk a paginated listing, collecting e2e-created entities. */
async function walkPages(pw: any, cookies: string, baseUrl: string,
  idParam: string): Promise<Map<string, string>> {
  const found = new Map<string, string>();
  for (let page = 1; page <= 50; page++) {
    const { body } = await authGet(pw, `${baseUrl}&page=${page}`, cookies);
    const before = found.size;
    for (const [id, name] of extractRows(body, idParam)) found.set(id, name);
    if (page > 1 && found.size === before) break; // past the end: nothing new
    if (!body.includes(`page=${page + 1}`)) break; // no next-page link
  }
  return found;
}

/** Depth-first cleanup of one group; returns how many entities were removed. */
async function cleanGroup(pw: any, cookies: string, gid: string,
  ancestors: Set<string>): Promise<number> {
  let removed = 0;

  for (const [zid] of await walkPages(pw, cookies,
    `${BASE}/group_zones.cgi?nt_group_id=${gid}`, 'nt_zone_id')) {
    await deleteZone(pw, cookies, gid, zid);
    removed++;
  }
  for (const [uid] of await walkPages(pw, cookies,
    `${BASE}/group_users.cgi?nt_group_id=${gid}`, 'nt_user_id')) {
    await deleteUser(pw, cookies, gid, uid);
    removed++;
  }
  for (const [nsid] of await walkPages(pw, cookies,
    `${BASE}/group_nameservers.cgi?nt_group_id=${gid}`, 'nt_nameserver_id')) {
    await deleteNameserver(pw, cookies, gid, nsid);
    removed++;
  }

  // The page renders the ancestor tree with the same link shape as the
  // sub-group rows, so skip this group and everything above it.
  const subs = await walkPages(pw, cookies,
    `${BASE}/group.cgi?nt_group_id=${gid}`, 'nt_group_id');
  for (const [sub, name] of subs) {
    if (sub === gid || ancestors.has(sub)) continue;
    removed += await cleanGroup(pw, cookies, sub, new Set([...ancestors, gid]));
    await deleteGroup(pw, cookies, gid, sub);
    removed++;
  }
  return removed;
}

export default async function globalTeardown(): Promise<void> {
  const pw = { request };
  const login = await apiLogin(pw);
  if (!login.sessionCookie) {
    console.log('e2e teardown: login failed, skipping cleanup');
    return;
  }
  const cookies = cookieString(login.sessionCookie, login.csrfCookie);

  // A delete can unblock another (a group empties once its user goes), so
  // repeat until a pass removes nothing.
  let total = 0;
  for (let round = 0; round < 5; round++) {
    const removed = await cleanGroup(pw, cookies, '1', new Set());
    total += removed;
    if (removed === 0) break;
  }
  if (total > 0) console.log(`e2e teardown: removed ${total} leftover test entities`);
}
