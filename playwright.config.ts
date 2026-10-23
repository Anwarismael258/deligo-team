import { defineConfig, devices } from "@playwright/test";

const externalBaseUrl = process.env.E2E_BASE_URL;

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: true,
  reporter: "list",
  use: {
    baseURL: externalBaseUrl || "http://localhost:4173",
    trace: "retain-on-failure",
    serviceWorkers: "block",
  },
  projects: [
    { name: "chromium-local", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile-local", use: { ...devices["Pixel 5"] } },
  ],
  webServer: externalBaseUrl ? undefined : {
    command: "cmd /c \"set SUPABASE_URL=&& set SUPABASE_ANON_KEY=&& set PAYSUITE_ENABLED=false&& set PAYSUITE_API_TOKEN=&& set WHATSAPP_ACCESS_TOKEN=&& set NOMINALIA_SMTP_PASSWORD=&& npm run start -- --port 4173\"",
    url: "http://localhost:4173/login",
    reuseExistingServer: false,
    timeout: 120_000,
  },
});
