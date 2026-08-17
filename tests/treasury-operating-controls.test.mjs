import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const sql=fs.readFileSync('supabase/migrations/398_hq_treasury_operating_controls.sql','utf8');
test('cria Treasury e Tax/Obligations sem substituir Corporate Wallet',()=>{ assert.match(sql,/TREASURY_OPERATING_MZN/); assert.match(sql,/TAX_OBLIGATIONS_MZN/); });
test('contas de pagamento suportam empresa, pessoa, fornecedor, banco e provedores futuros',()=>{ for(const x of ['payment_accounts','corporate','employee','supplier','partner','shareholder','vodacom_mpesa','movitel','bank']) assert.match(sql,new RegExp(x)); });
test('tesouraria inclui orçamento, aprovações e alertas',()=>{ for(const x of ['department_budgets','finance_approval_items','finance_alerts']) assert.match(sql,new RegExp(x)); });
test('wallet pessoal temporária fica mascarada e não verificada',()=>{ assert.match(sql,/8411300015/); assert.match(sql,/84•••••15/); assert.match(sql,/false,true,'pending'/); });
