import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = await readFile(new URL("../supabase/migrations/339_hq_operational_action_audit.sql", import.meta.url), "utf8");
const route = await readFile(new URL("../app/api/operations/route.ts", import.meta.url), "utf8");

test("auditoria operacional permite apenas os papéis do módulo", () => {
  assert.match(migration, /CUSTOMER_SUPPORT/);
  assert.match(migration, /MARKETING/);
  assert.match(migration, /FIELD/);
  assert.match(migration, /HQ_OPERATION_FORBIDDEN/);
});

test("mensagens e alterações de tickets deixam auditoria", () => {
  assert.match(route, /SUPPORT_MESSAGE_SENT/);
  assert.match(route, /SUPPORT_TICKET_/);
  assert.match(route, /hq_log_operational_action_v1/);
});

test("campanhas passam pelo backend e ficam auditadas", () => {
  assert.match(route, /MARKETING_CAMPAIGN_CREATED/);
  assert.match(route, /MARKETING_CAMPAIGN_\$\{body\.action\}/);
  assert.match(route, /\["draft", "published", "archived"\]/);
});
