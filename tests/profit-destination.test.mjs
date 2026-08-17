import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";

const migration = fs.readFileSync("supabase/migrations/394_hq_corporate_profit_destination.sql", "utf8");

test("lucro corporativo usa a wallet do Super Admin", () => {
  assert.match(migration, /8411300015/);
  assert.match(migration, /hq_profit_destination/);
  assert.match(migration, /confirmed_profit_destination_v1/);
});

test("destino de lucro não simula transferência", () => {
  assert.match(migration, /provider_transfer_required/);
  assert.match(migration, /Provider settlement remains explicit/);
});
