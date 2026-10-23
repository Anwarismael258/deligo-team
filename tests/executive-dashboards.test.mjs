import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const root = new URL("../", import.meta.url);
const read = (path) => fs.readFileSync(new URL(path, root), "utf8");

test("Visão Geral reutiliza analytics e mantém fontes indisponíveis explícitas", () => {
  const source = read("components/analytics/ExecutiveOverviewDashboard.tsx");
  assert.match(source, /DashboardFilters/);
  assert.match(source, /KPIGrid/);
  assert.match(source, /AnalyticsDataTable/);
  assert.match(source, /Série temporal não disponível/);
  assert.match(source, /sem estimativas/i);
});

test("dashboard de plataformas separa receita própria de carteiras de terceiros", () => {
  const source = read("components/analytics/PlatformExecutiveDashboard.tsx");
  assert.match(source, /Receita própria/);
  assert.match(source, /Carteiras de terceiros/);
  assert.match(source, /não é receita/);
  assert.match(source, /Nenhum indicador operacional devolvido/);
});

test("a Visão Geral e Plataformas são integradas na rota existente", () => {
  const page = read("app/page.tsx");
  assert.match(page, /ExecutiveOverviewDashboard/);
  assert.match(page, /PlatformExecutiveDashboard/);
  assert.match(page, /active === "Visão geral"/);
  assert.match(page, /active === "Plataformas"/);
});
