import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const root = new URL("../", import.meta.url);
const read = (path) => fs.readFileSync(new URL(path, root), "utf8");

test("PaySuite Fase 2C documenta apenas capacidades oficiais de leitura confirmadas", () => {
  const doc = read("docs/paysuite-phase2c-validation.md");
  assert.match(doc, /GET \/api\/v1\/payments\/\{id\}/);
  assert.match(doc, /GET \/api\/v1\/payouts\?page=&limit=/);
  assert.match(doc, /GET \/api\/v1\/refunds/);
  assert.match(doc, /Consulta de saldo da conta.*Não confirmada/s);
  assert.match(doc, /Extrato financeiro.*Não confirmada/s);
});

test("o cliente PaySuite existente não inventa GET de saldo ou extrato", () => {
  const client = read("lib/paysuite.ts");
  assert.match(client, /Authorization/);
  assert.match(client, /PAYSUITE_API_TOKEN/);
  assert.doesNotMatch(client, /\/balance|\/transactions|\/statement|\/settlements/);
});

test("a integração existente mantém escrita limitada a pagamentos e payouts", () => {
  const createPayment = read("app/api/payments/paysuite/create/route.ts");
  const withdraw = read("app/api/profile/withdraw/route.ts");
  assert.match(createPayment, /paysuiteRequest[\s\S]*\/payments/);
  assert.match(withdraw, /paysuiteRequest[\s\S]*\/payouts/);
  assert.match(read("app/api/payments/paysuite/webhook/route.ts"), /x-signature/);
});
