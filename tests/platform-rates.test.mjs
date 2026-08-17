import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";

const marketFinance = fs.readFileSync("supabase/migrations/298_taomoz_payments_escrow_and_financial_controls.sql", "utf8");
const deligoFinance = fs.readFileSync("supabase/migrations/069_internal_wallet_escrow_and_ledger.sql", "utf8");
const sarcaFinance = fs.readFileSync("supabase/migrations/295_sarca_identity_and_mobility.sql", "utf8");

test("DeliGo e DeliGo Market usam 6% produto e 5% entrega", () => {
  assert.match(deligoFinance, /courier_fee_percent NUMERIC DEFAULT 0\.05/);
  assert.match(deligoFinance, /restaurant_fee_percent NUMERIC DEFAULT 0\.06/);
  assert.match(marketFinance, /new\.product_fee_rate_bps := 600/);
  assert.match(marketFinance, /new\.delivery_fee_rate_bps := 500/);
});

test("SARCA tem comissão base de 6%", () => {
  assert.match(sarcaFinance, /commission_rate_bps integer not null default 600/);
});
