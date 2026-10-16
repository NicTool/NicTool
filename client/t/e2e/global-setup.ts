import { randomBytes } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { BASE, RUN_DIR, RUN_ID_PATTERN, processIsAlive } from './helpers';

export default async function globalSetup(): Promise<void> {
  const runId = process.env.NICTOOL_E2E_RUN_ID ||
    `nt${randomBytes(8).toString('hex')}`;
  if (!RUN_ID_PATTERN.test(runId)) {
    throw new Error('NICTOOL_E2E_RUN_ID must contain 8-64 lowercase letters or digits');
  }
  process.env.NICTOOL_E2E_RUN_ID = runId;

  mkdirSync(RUN_DIR, { recursive: true });
  const manifestPath = path.join(RUN_DIR, `${runId}.json`);
  const manifest = JSON.stringify({
    version: 1,
    runId,
    createdAt: Date.now(),
    baseUrl: BASE,
    pid: process.pid,
  });

  try {
    writeFileSync(manifestPath, manifest, { flag: 'wx' });
  } catch (error: any) {
    if (error.code !== 'EEXIST') throw error;
    const previous = JSON.parse(readFileSync(manifestPath, 'utf8'));
    if (processIsAlive(previous.pid)) {
      throw new Error(`NICTOOL_E2E_RUN_ID ${runId} is already active`);
    }
    writeFileSync(manifestPath, manifest);
  }
}
