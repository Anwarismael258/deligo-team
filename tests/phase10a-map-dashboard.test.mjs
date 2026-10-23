import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const read = (path) => fs.readFileSync(path, "utf8");

test("Centro de Mapas mostra métricas reais e usa o endpoint autenticado", () => {
  const dashboard = read("components/analytics/OperationsMapDashboard.tsx");
  const route = read("app/api/map/route.ts");
  assert.match(dashboard, /fetch\("\/api\/map"/);
  assert.match(dashboard, /LiveOperationsMap/);
  assert.match(dashboard, /GPS desactualizado/);
  assert.match(dashboard, /Distribuição por plataforma/);
  assert.match(route, /corporateActor/);
  assert.match(route, /Sessao corporativa necessaria/);
});

test("Mapa operacional aparece para trabalhadores autenticados sem abrir ações operacionais", () => {
  const page = read("app/page.tsx");
  assert.match(page, /new Set<string>\(\["Mapa operacional"\]\)/);
  assert.match(page, /active === "Mapa operacional" && <OperationsMapDashboard\/>/);
});
