import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.ts',
  globalSetup: './global-setup.ts',
  globalTeardown: './global-teardown.ts',
  timeout: 30_000,
  retries: 0,
  workers: 1,
  use: {
    baseURL: process.env.NICTOOL_URL || 'https://localhost:8443',
    ignoreHTTPSErrors: true,
  },
  reporter: [['list']],
});
