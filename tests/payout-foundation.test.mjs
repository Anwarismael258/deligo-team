import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";

const migration = fs.readFileSync("supabase/migrations/395_hq_payouts_and_payroll_foundation.sql", "utf8");

test("fundação suporta levantamentos, reembolsos, transferências, bónus e salários", () => {
  for (const kind of ["withdrawal", "refund", "user_transfer", "bonus", "salary"]) assert.match(migration, new RegExp(`'${kind}'`));
  assert.match(migration, /payroll_runs/);
});

test("gateway fica bloqueado até existir integração oficial", () => {
  assert.match(migration, /vodacom_mpesa/);
  assert.match(migration, /movitel/);
  assert.match(migration, /official gateway adapter is configured/);
});

test("operações têm idempotência e reconciliação por webhook", () => {
  assert.match(migration, /idempotency_key text not null unique/);
  assert.match(migration, /unique\(provider, provider_event_id\)/);
});
