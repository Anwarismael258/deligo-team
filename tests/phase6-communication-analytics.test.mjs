import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = () => readFile(new URL("../app/api/analytics/communication/route.ts", import.meta.url), "utf8");
const dashboard = () => readFile(new URL("../components/analytics/CommunicationAnalyticsDashboard.tsx", import.meta.url), "utf8");

test("fase 6 usa as fontes reais dos três módulos", async () => {
  const source = await route();
  for (const table of ["marketing_campaigns", "marketing_leads", "marketing_metrics", "inbox_messages", "inbox_replies", "notifications"]) assert.match(source, new RegExp(table));
  assert.match(source, /Africa\/Maputo/);
});

test("analytics de comunicação é somente leitura", async () => {
  const source = await route();
  assert.match(source, /export async function GET/);
  assert.doesNotMatch(source, /export async function (POST|PATCH|PUT|DELETE)/);
  assert.doesNotMatch(source, /method:\s*["'](POST|PATCH|PUT|DELETE)["']/);
  assert.match(source, /Cache-Control.*no-store/);
});

test("conversão, falhas, leituras e sem resposta têm regras explícitas", async () => {
  const source = await route();
  assert.match(source, /converted.*won.*approved/);
  assert.match(source, /read_at/);
  assert.match(source, /failed.*error/);
  assert.match(source, /conversationsWithoutResponse/);
});

test("UI de comunicação reutiliza analytics e expõe os filtros da fase", async () => {
  const source = await dashboard();
  for (const component of ["DashboardHeader", "DashboardFilters", "KPIGrid", "ChartContainer", "AnalyticsDataTable"]) assert.match(source, new RegExp(component));
  for (const filter of ["platform", "channel", "status", "eventType"]) assert.match(source, new RegExp(filter));
});
