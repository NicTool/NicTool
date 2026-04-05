import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.ts',
  timeout: 30_000,
  retries: 0,
  workers: 1,
  use: {
    baseURL: process.env.NICTOOL_URL || 'http://localhost:8080',
    ignoreHTTPSErrors: true,
  },
  reporter: [['list']],
});
