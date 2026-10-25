import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const root = new URL("../", import.meta.url);
const read = path => fs.readFileSync(new URL(path, root), "utf8");

test("dashboard de utilizadores deduplica pessoas e separa associações de plataforma", () => {
  const route = read("app/api/analytics/users-team/route.ts");
  assert.match(route, /global_user_platforms_v1/);
  assert.match(route, /new Map<string, Row>\(\)/);
  assert.match(route, /joined_at/);
  assert.match(route, /byPlatform/);
});

test("dashboard de equipa usa estados e datas reais de tarefas", () => {
  const route = read("app/api/analytics/users-team/route.ts");
  assert.match(route, /hq_employee_directory_v1/);
  assert.match(route, /tasks\?select=id,status/);
  assert.match(route, /completed_at/);
  assert.match(route, /tasksOverdue/);
  assert.match(route, /department/);
});

test("UI de utilizadores e equipa reutiliza analytics e não cria rankings individuais", () => {
  const source = read("components/analytics/UserTeamDashboard.tsx");
  assert.match(source, /DashboardFilters/);
  assert.match(source, /KPIGrid/);
  assert.match(source, /AnalyticsDonutChart/);
  assert.doesNotMatch(source, /ranking individual/i);
  assert.match(source, /Série histórica indisponível/);
});
