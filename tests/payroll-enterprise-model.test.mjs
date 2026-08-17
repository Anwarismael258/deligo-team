import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const sql=fs.readFileSync('supabase/migrations/401_hq_payroll_enterprise_model.sql','utf8');
test('Payroll tem período, componentes e estados empresariais',()=>{for(const x of ['payroll_lines','base_salary','allowances','bonuses','overtime','other_credits','absences_deductions','other_deductions','calculated','validated','submitted_to_finance','reconciled'])assert.match(sql,new RegExp(x));});
test('Payroll bloqueia duplicados e mantém histórico',()=>{assert.match(sql,/unique\(payroll_run_id,employee_id\)/);assert.match(sql,/payroll_line_history/);assert.match(sql,/provider_reference/);});
