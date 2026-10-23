import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const route = fs.readFileSync("app/api/analytics/microcredit/route.ts", "utf8");
const dashboard = fs.readFileSync("components/analytics/MicrocreditAnalyticsDashboard.tsx", "utf8");

test("Fase 8 declara fontes de pedidos e fontes financeiras separadas", () => {
  for (const source of ["loan_applications", "loan_contracts", "loan_disbursements", "loan_repayments", "loan_collaterals", "loan_application_history"]) assert.match(route, new RegExp(source));
  assert.match(route, /loan_application_deliveries/);
});

test("Fase 8 é somente leitura e protege o módulo", () => {
  assert.match(route, /export async function GET/);
  assert.doesNotMatch(route, /export async function (POST|PATCH|PUT|DELETE)/);
  assert.doesNotMatch(route, /method:\s*["'](POST|PATCH|PUT|DELETE)["']/);
  assert.match(route, /SUPER_ADMIN/);
  assert.match(route, /FINANCE/);
});

test("Fase 8 separa aprovação de desembolso e usa Maputo", () => {
  assert.match(route, /Pedidos aprovados não são tratados como desembolsos/);
  assert.match(route, /Africa\/Maputo/);
  for (const period of ["last_7_days", "last_30_days", "last_90_days", "custom"]) assert.match(route, new RegExp(period));
});

test("Fase 8 reutiliza analytics e filtros sensíveis", () => {
  for (const component of ["DashboardHeader", "DashboardFilters", "KPIGrid", "ChartContainer", "AnalyticsDataTable"]) assert.match(dashboard, new RegExp(component));
  for (const filter of ["status", "loan_type", "collateral_type"]) assert.match(route, new RegExp(filter));
});
