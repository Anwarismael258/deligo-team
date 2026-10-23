import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = () => readFile(new URL("../app/api/analytics/operations-support/route.ts", import.meta.url), "utf8");
const dashboard = () => readFile(new URL("../components/analytics/OperationsSupportDashboard.tsx", import.meta.url), "utf8");

test("field and support analytics declare their real read sources", async () => {
  const source = await route();
  for (const table of ["field_visits", "acquisition_leads", "acquisition_partners", "tasks", "support_tickets", "support_conversations", "support_history"]) {
    assert.match(source, new RegExp(table));
  }
  assert.match(source, /Africa\/Maputo/);
});

test("operational analytics is read-only and guarded by the existing permissions", async () => {
  const source = await route();
  assert.match(source, /requireCorporatePermission/);
  assert.doesNotMatch(source, /export async function (POST|PATCH|PUT|DELETE)/);
  assert.doesNotMatch(source, /\.insert\(|\.update\(|\.delete\(/);
  assert.match(source, /Cache-Control.*no-store/);
});

test("field conversion and support timing rules are explicit", async () => {
  const source = await route();
  assert.match(source, /approved.*currentLeads.*currentLeads\.length/);
  assert.match(source, /sender_type.*customer/);
  assert.match(source, /reopen_count/);
  assert.match(source, /critical.*urgent.*high/);
});

test("the UI reuses analytics components and exposes operational filters", async () => {
  const source = await dashboard();
  for (const component of ["DashboardHeader", "DashboardFilters", "KPIGrid", "ChartContainer", "AnalyticsDataTable"]) {
    assert.match(source, new RegExp(component));
  }
  for (const filter of ["status", "priority", "department", "agent"]) assert.match(source, new RegExp(filter));
  assert.doesNotMatch(source, /method:\s*["'](POST|PATCH|PUT|DELETE)["']/);
});
