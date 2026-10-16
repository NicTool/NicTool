import { request } from '@playwright/test';
import { readdirSync, readFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import {
  BASE, TEST_GID, apiLogin, cookieString, authGet,
  deleteGroup, deleteZone, deleteUser, deleteNameserver,
} from './helpers';

type RunManifest = {
  version: number;
  runId: string;
  createdAt: number;
  baseUrl: string;
  pid?: number;
  file: string;
};

const RUN_DIR = path.join(__dirname, '.e2e-runs');
const MAX_AGE_MS = Number(process.env.NICTOOL_E2E_CLEAN_AGE_MS || 30 * 60 * 1000);

function normalizedUrl(url: string): string {
  return url.replace(/\/+$/, '');
}

function processIsAlive(pid: unknown): boolean {
  if (!Number.isInteger(pid) || Number(pid) <= 0) return false;
  try {
    process.kill(Number(pid), 0);
    return true;
  } catch (error: any) {
    return error.code === 'EPERM';
  }
}

function eligibleRuns(now = Date.now()): RunManifest[] {
  let files: string[];
  try {
    files = readdirSync(RUN_DIR).filter(file => file.endsWith('.json'));
  } catch (error: any) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }

  const currentRun = process.env.NICTOOL_E2E_RUN_ID;
  const runs: RunManifest[] = [];
  for (const file of files) {
    try {
      const manifest = JSON.parse(readFileSync(path.join(RUN_DIR, file), 'utf8'));
      if (manifest.version !== 1 ||
          !/^[a-z0-9]{8,64}$/.test(manifest.runId) ||
          !Number.isFinite(manifest.createdAt) ||
          normalizedUrl(manifest.baseUrl) !== normalizedUrl(BASE)) {
        continue;
      }
      if (manifest.runId === currentRun ||
          (now - manifest.createdAt > MAX_AGE_MS && !processIsAlive(manifest.pid))) {
        runs.push({ ...manifest, file });
      }
    } catch {
      // An invalid manifest grants no authority to delete anything.
    }
  }
  return runs;
}

export function isOwnedName(text: string, runIds: Set<string>): boolean {
  for (const runId of runIds) {
    if (text.includes(`_${runId}_`) || text.includes(`-${runId}-`)) return true;
  }
  return false;
}

export function paginationStarts(html: string): number[] {
  const starts = new Set<number>();
  const re = /(?:[?&]|&amp;)start=(\d+)/g;
  let match;
  while ((match = re.exec(html)) !== null) starts.add(Number(match[1]));
  return [...starts];
}

export async function collectListingPages(
  load: (start: number | null) => Promise<string>,
): Promise<string[]> {
  const bodies: string[] = [];
  const pending: Array<number | null> = [null];
  const seen = new Set<string>();

  while (pending.length > 0) {
    if (seen.size >= 1000) throw new Error('e2e teardown: pagination exceeded 1000 pages');
    const start = pending.shift()!;
    const key = start === null ? 'first' : String(start);
    if (seen.has(key)) continue;
    seen.add(key);

    const body = await load(start);
    bodies.push(body);
    for (const next of paginationStarts(body)) {
      if (!seen.has(String(next))) pending.push(next);
    }
  }
  return bodies;
}

function extractRows(html: string, idParam: string,
  runIds: Set<string>): Map<string, string> {
  const rows = new Map<string, string>();
  const re = new RegExp(
    `${idParam}=(\\d+)((?:&amp;[^"]*)?)"[^>]*>\\s*(?:<img[^>]*>\\s*)*([^<]{1,80}?)\\s*<`, 'g');
  let match;
  while ((match = re.exec(html)) !== null) {
    const [, id, tail, text] = match;
    if (/delete|csrf_token|new=|edit/.test(tail)) continue;
    if (isOwnedName(text, runIds)) rows.set(id, text);
  }
  return rows;
}

async function walkPages(pw: any, cookies: string, baseUrl: string,
  idParam: string, runIds: Set<string>): Promise<Map<string, string>> {
  const found = new Map<string, string>();
  const bodies = await collectListingPages(async start => {
    const url = start === null ? baseUrl : `${baseUrl}&start=${start}`;
    const { body } = await authGet(pw, url, cookies);
    return body;
  });
  for (const body of bodies) {
    for (const [id, name] of extractRows(body, idParam, runIds)) found.set(id, name);
  }
  return found;
}

async function cleanGroup(pw: any, cookies: string, gid: string,
  ancestors: Set<string>, runIds: Set<string>): Promise<number> {
  let removed = 0;

  for (const [zid] of await walkPages(pw, cookies,
    `${BASE}/group_zones.cgi?nt_group_id=${gid}`, 'nt_zone_id', runIds)) {
    await deleteZone(pw, cookies, gid, zid);
    removed++;
  }
  for (const [uid] of await walkPages(pw, cookies,
    `${BASE}/group_users.cgi?nt_group_id=${gid}`, 'nt_user_id', runIds)) {
    await deleteUser(pw, cookies, gid, uid);
    removed++;
  }
  for (const [nsid] of await walkPages(pw, cookies,
    `${BASE}/group_nameservers.cgi?nt_group_id=${gid}`, 'nt_nameserver_id', runIds)) {
    await deleteNameserver(pw, cookies, gid, nsid);
    removed++;
  }

  const subs = await walkPages(pw, cookies,
    `${BASE}/group.cgi?nt_group_id=${gid}`, 'nt_group_id', runIds);
  for (const [sub] of subs) {
    if (sub === gid || ancestors.has(sub)) continue;
    removed += await cleanGroup(pw, cookies, sub,
      new Set([...ancestors, gid]), runIds);
    await deleteGroup(pw, cookies, gid, sub);
    removed++;
  }
  return removed;
}

export default async function globalTeardown(): Promise<void> {
  const runs = eligibleRuns();
  if (runs.length === 0) return;

  const pw = { request };
  const login = await apiLogin(pw);
  if (!login.sessionCookie) {
    console.log('e2e teardown: login failed, leaving run manifests for a later cleanup');
    return;
  }
  const cookies = cookieString(login.sessionCookie, login.csrfCookie);
  const runIds = new Set(runs.map(run => run.runId));

  let total = 0;
  let lastRemoved = 0;
  for (let round = 0; round <= 5; round++) {
    lastRemoved = await cleanGroup(pw, cookies, String(TEST_GID), new Set(), runIds);
    total += lastRemoved;
    if (lastRemoved === 0) break;
  }
  if (lastRemoved !== 0) {
    throw new Error('e2e teardown: cleanup did not converge; run manifests were retained');
  }

  for (const run of runs) unlinkSync(path.join(RUN_DIR, run.file));
  if (total > 0) {
    console.log(`e2e teardown: removed ${total} entities owned by ${runs.length} test run(s)`);
  }
}
