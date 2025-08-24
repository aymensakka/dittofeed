import { defineConfig, devices } from '@playwright/test';

/**
 * Read environment variables from file.
 * https://github.com/motdotla/dotenv
 */
// require('dotenv').config();

/**
 * See https://playwright.dev/docs/test-configuration.
 */
export default defineConfig({
  testDir: './e2e-tests',
  /* Run tests in files in parallel */
  fullyParallel: false,
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,
  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 1 : undefined,
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: 'html',
  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL: 'http://localhost:3000',
    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  /* Configure projects for major browsers */
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  /* Run your local dev server before starting the tests */
  webServer: [
    {
      command: 'source .env && AUTH_MODE=multi-tenant AUTH_PROVIDER=google DATABASE_URL=postgresql://dittofeed:password@localhost:5433/dittofeed REDIS_HOST=localhost REDIS_PORT=6380 CLICKHOUSE_HOST=localhost CLICKHOUSE_PORT=8124 CLICKHOUSE_USER=dittofeed CLICKHOUSE_PASSWORD=password TEMPORAL_ADDRESS=localhost:7234 yarn workspace api dev',
      port: 3001,
      reuseExistingServer: true,
      timeout: 120000,
    },
    {
      command: 'source .env && AUTH_MODE=multi-tenant NEXT_PUBLIC_AUTH_MODE=multi-tenant NEXT_PUBLIC_API_BASE=http://localhost:3001 NEXT_PUBLIC_ENABLE_MULTITENANCY=true NEXTAUTH_URL=http://localhost:3000/dashboard NEXTAUTH_SECRET=your-nextauth-secret yarn workspace dashboard dev',
      port: 3000,
      reuseExistingServer: true,
      timeout: 120000,
    }
  ],
});