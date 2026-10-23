import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const route = fs.readFileSync("app/api/analytics/corporate-operations/route.ts", "utf8");
const dashboard = fs.readFileSync("components/analytics/CorporateOperationsAnalyticsDashboard.tsx", "utf8");

test("Fase 7 usa as fontes reais auditadas", () => {
  for (const source of ["news", "job_openings", "projects", "tasks", "project_milestones", "saved_reports", "report_runs"]) assert.match(route, new RegExp(source));
});

test("Fase 7 mantém o endpoint somente leitura", () => {
  assert.match(route, /export async function GET/);
  assert.doesNotMatch(route, /method:\s*["'](POST|PATCH|PUT|DELETE)["']/);
  assert.doesNotMatch(route, /export async function (POST|PATCH|PUT|DELETE)/);
});

test("Fase 7 declara Maputo e períodos suportados", () => {
  assert.match(route, /Africa\/Maputo/);
  for (const period of ["last_7_days", "last_30_days", "last_90_days", "custom"]) assert.match(route, new RegExp(period));
});

test("Fase 7 reutiliza componentes analytics e filtros", () => {
  for (const component of ["DashboardHeader", "DashboardFilters", "KPIGrid", "ChartContainer", "AnalyticsDataTable"]) assert.match(dashboard, new RegExp(component));
  assert.match(dashboard, /department/);
  assert.match(dashboard, /status/);
});
