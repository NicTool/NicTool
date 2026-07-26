import { randomBytes } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

export default async function globalSetup(): Promise<void> {
  const runId = process.env.NICTOOL_E2E_RUN_ID ||
    `nt${randomBytes(8).toString('hex')}`;
  if (!/^[a-z0-9]{8,64}$/.test(runId)) {
    throw new Error('NICTOOL_E2E_RUN_ID must contain 8-64 lowercase letters or digits');
  }
  process.env.NICTOOL_E2E_RUN_ID = runId;

  const runDir = path.join(__dirname, '.e2e-runs');
  mkdirSync(runDir, { recursive: true });
  writeFileSync(path.join(runDir, `${runId}.json`), JSON.stringify({
    version: 1,
    runId,
    createdAt: Date.now(),
    baseUrl: process.env.NICTOOL_URL || 'https://localhost:8443',
    pid: process.pid,
  }), { flag: 'wx' });
}
