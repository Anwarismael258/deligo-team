import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/397_hq_executive_dual_control.sql','utf8');

test('separa wallets de trabalhador e sócio para os dois executivos',()=>{
  for (const code of ['PROFIT_RESERVE_MZN','SHAREHOLDER_CEO_MZN','SHAREHOLDER_FINANCE_DIRECTOR_MZN','EMPLOYEE_CEO_MZN','EMPLOYEE_FINANCE_DIRECTOR_MZN']) assert.match(sql,new RegExp(code));
});

test('lucro e movimentos críticos exigem controlo duplo',()=>{
  assert.match(sql,/SHAREHOLDER_DISTRIBUTION.*2,array\['SUPER_ADMIN','FINANCE_DIRECTOR'\]/s);
  assert.match(sql,/approval_count/);
  assert.match(sql,/second_approved_by/);
});

test('saídas pessoais exigem natureza económica',()=>{
  assert.match(sql,/economic_category/);
  for (const category of ['SALARY','BONUS','REIMBURSEMENT','ADVANCE','SHAREHOLDER_DISTRIBUTION']) assert.match(sql,new RegExp(category));
});

test('dashboard executivo é somente leitura',()=>{
  assert.match(sql,/executive_finance_dashboard_v1/);
  assert.match(sql,/Read-only executive view/);
});
