import assert from "node:assert/strict";
import test from "node:test";

const access = {
  sara: new Set(["finance.view", "finance.transactions.approve", "accounting.view", "approvals.finance", "reports.view", "reserved_matters.approve"]),
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
  assert.equal(access.sara.has("security.permissions.manage"), false);
});

test("A Diretora Financeira pode rever finanças e decisões reservadas", () => {
  assert.equal(access.sara.has("finance.transactions.approve"), true);
  assert.equal(access.sara.has("reserved_matters.approve"), true);
});

test("Perfis operacionais não executam pagamentos", () => {
  assert.equal(access.sansao.has("payments.execute"), false);
  assert.equal(access.technology.has("payments.execute"), false);
});
