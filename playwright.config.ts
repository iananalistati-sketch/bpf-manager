import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  use: { baseURL: 'http://127.0.0.1:4175', trace: 'retain-on-failure' },
  projects: [{ name: 'chrome', use: {
    ...devices['Desktop Chrome'],
    ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
      ? { launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH } }
      : { channel: 'chrome' }),
  } }],
  webServer: {
    command: `${process.platform === 'win32' ? 'npm.cmd' : 'npm'} run dev -- --host 127.0.0.1 --port 4175 --strictPort`,
    url: 'http://127.0.0.1:4175',
    reuseExistingServer: false,
    env: { VITE_SUPABASE_URL: 'https://bpf-test.supabase.co', VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_only' },
  },
})
