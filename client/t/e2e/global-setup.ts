import { randomBytes } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

function processIsAlive(pid: unknown): boolean {
  if (!Number.isInteger(pid) || Number(pid) <= 0) return false;
  try {
    process.kill(Number(pid), 0);
    return true;
  } catch (error: any) {
    return error.code === 'EPERM';
  }
}

export default async function globalSetup(): Promise<void> {
  const runId = process.env.NICTOOL_E2E_RUN_ID ||
    `nt${randomBytes(8).toString('hex')}`;
  if (!/^[a-z0-9]{8,64}$/.test(runId)) {
    throw new Error('NICTOOL_E2E_RUN_ID must contain 8-64 lowercase letters or digits');
  }
  process.env.NICTOOL_E2E_RUN_ID = runId;

  const runDir = path.join(__dirname, '.e2e-runs');
  mkdirSync(runDir, { recursive: true });
  const manifestPath = path.join(runDir, `${runId}.json`);
  const manifest = JSON.stringify({
    version: 1,
    runId,
    createdAt: Date.now(),
    baseUrl: process.env.NICTOOL_URL || 'https://localhost:8443',
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
