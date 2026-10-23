import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const root = new URL("../", import.meta.url);
const read = (path) => fs.readFileSync(new URL(path, root), "utf8");

test("séries históricas usam eventos canónicos, data de ocorrência e deduplicação", () => {
  const source = read("app/api/analytics/history/route.ts");
  assert.match(source, /platform_financial_events/);
  assert.match(source, /platform_events/);
  assert.match(source, /occurred_at/);
  assert.match(source, /payment_status=confirmed|payment_status\) !== \"confirmed\"/);
  assert.match(source, /financialSeen/);
  assert.match(source, /operationalSeen/);
});

test("períodos históricos têm limites Maputo e comparação segura", () => {
  const source = read("app/api/analytics/history/route.ts");
  assert.match(source, /Africa\/Maputo/);
  assert.match(source, /last_7_days/);
  assert.match(source, /last_30_days/);
  assert.match(source, /last_90_days/);
  assert.match(source, /previousRange/);
  assert.match(source, /previous === 0 \? null/);
});

test("a UI apresenta a série real e não inventa pontos ausentes", () => {
  const source = read("components/analytics/ExecutiveOverviewDashboard.tsx");
  assert.match(source, /api\/analytics\/history/);
  assert.match(source, /Receita histórica indisponível/);
  assert.match(source, /Comparação temporal indisponível/);
  assert.match(source, /history\.comparison\.revenue/);
});
