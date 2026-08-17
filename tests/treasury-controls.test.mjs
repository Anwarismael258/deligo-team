import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";

const sql = fs.readFileSync("supabase/migrations/396_hq_treasury_ledger_controls.sql", "utf8");

test("ledger cobre todas as operações financeiras centrais", () => {
  for (const type of ["REVENUE", "PAYROLL_FUNDING", "SALARY_CREDIT", "BONUS_CREDIT", "EXPENSE_RESERVATION", "EXPENSE_PAYMENT", "ADVANCE_ISSUED", "ADVANCE_SETTLEMENT", "ADVANCE_RETURN", "PARTNER_SETTLEMENT", "EMPLOYEE_WITHDRAWAL", "SHAREHOLDER_DISTRIBUTION", "INTERNAL_TRANSFER", "REFUND", "REVERSAL", "ADJUSTMENT"]) assert.match(sql, new RegExp(type));
});

test("tesouraria separa wallets, contas de pagamento e adiantamentos", () => {
  for (const table of ["logical_wallets", "employee_payment_accounts", "employee_payment_account_changes", "employee_advances", "approval_matrix"]) assert.match(sql, new RegExp(table));
  assert.match(sql, /accountability_pending/);
});

test("aprovação e execução permanecem auditáveis", () => {
  for (const field of ["requested_by", "approved_by", "executed_by", "provider_reference", "requested_at", "approved_at", "executed_at"]) assert.match(sql, new RegExp(field));
  assert.match(sql, /required_roles text\[\]/);
});
