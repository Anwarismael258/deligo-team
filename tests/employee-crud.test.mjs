import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = await readFile(new URL("../supabase/migrations/338_hq_employee_crud.sql", import.meta.url), "utf8");
const route = await readFile(new URL("../app/api/employees/route.ts", import.meta.url), "utf8");

test("edição de trabalhador exige autorização e controlo de concorrência", () => {
  assert.match(migration, /SUPER_ADMIN.*HUMAN_RESOURCES/);
  assert.match(migration, /HQ_EMPLOYEE_CONFLICT/);
  assert.match(route, /p_expected_updated_at: input\.updatedAt/);
  assert.match(route, /status: 409/);
});

test("edição sensível protege o fundador e deixa auditoria", () => {
  assert.match(migration, /HQ_FOUNDER_ACCOUNT_PROTECTED/);
  assert.match(migration, /HQ_SENSITIVE_ROLE_REQUIRES_SUPER_ADMIN/);
  assert.match(migration, /EMPLOYEE_UPDATED/);
});
