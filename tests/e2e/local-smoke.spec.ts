import { expect, test } from "@playwright/test";

test.describe("Central HQ local smoke", () => {
  test("renders the corporate login without external services", async ({ page }) => {
    await page.goto("/login");
    await expect(page.getByText("ACESSO CORPORATIVO")).toBeVisible();
    await expect(page.getByRole("button", { name: /Enviar OTP/ })).toBeVisible();
  });

  test("login remains readable on mobile without horizontal overflow", async ({ page }) => {
    await page.goto("/login");
    const layout = await page.evaluate(() => ({ width: document.documentElement.scrollWidth, viewport: window.innerWidth }));
    expect(layout.width).toBeLessThanOrEqual(layout.viewport + 1);
  });

  test("local mock API responses never reach an external host", async ({ page }) => {
    const externalRequests: string[] = [];
    page.on("request", request => {
      if (!request.url().startsWith("http://localhost:4173")) externalRequests.push(request.url());
    });
    await page.route("**/api/**", route => route.fulfill({ status: 401, contentType: "application/json", body: JSON.stringify({ error: "Teste local sem sessão" }) }));
    await page.goto("/login");
    expect(externalRequests).toEqual([]);
  });
});
