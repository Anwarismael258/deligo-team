import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

test("ledger separates DEMO and LIVE environments", () => {
  const sql = fs.readFileSync("supabase/migrations/403_hq_demo_ledger_mode.sql", "utf8");
  assert.match(sql, /environment text/);
  assert.match(sql, /environment in \('DEMO','LIVE'\)/);
  assert.match(sql, /live_financial_transactions/);
  assert.match(sql, /demo_financial_transactions/);
});
