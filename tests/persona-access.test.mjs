import assert from "node:assert/strict";
import test from "node:test";

const access = {
  sara: new Set(["finance.view", "accounting.view", "approvals.finance", "reports.view"]),
  sansao: new Set(["operations.view", "field.view", "support.view", "tasks.assign"]),
  accountant: new Set(["accounting.view", "finance.result.prepare", "reports.export"]),
  technology: new Set(["technology.view", "integrations.view", "incidents.manage", "assets.view"]),
};

test("Tecnologia não recebe acesso financeiro", () => {
  assert.equal(access.technology.has("finance.view"), false);
  assert.equal(access.technology.has("payments.execute"), false);
});

test("Supervisor não recebe acesso a payroll", () => {
  assert.equal(access.sansao.has("payroll.view"), false);
});

test("Contabilista prepara, mas não aprova distribuição", () => {
  assert.equal(access.accountant.has("finance.result.prepare"), true);
  assert.equal(access.accountant.has("profit_distribution.approve"), false);
});

test("Sara não recebe Super Admin implicitamente", () => {
  assert.equal(access.sara.has("security.super_admin.assign"), false);
});

test("Perfis operacionais não executam pagamentos", () => {
  assert.equal(access.sansao.has("payments.execute"), false);
  assert.equal(access.technology.has("payments.execute"), false);
});
