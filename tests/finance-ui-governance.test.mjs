import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const ui=fs.readFileSync('app/contabilidade/governacao/page.tsx','utf8');
const mainUi=fs.readFileSync('app/page.tsx','utf8');
test('UI financeiro mostra tesouraria e separação de finalidades',()=>{ for(const x of ['Treasury / Operating','Payroll','Expenses','Tax & Obligations','Profit Reserve','Settlement']) assert.ok(ui.includes(x),x); });
test('UI financeiro não reintroduz o bloco executivo removido',()=>{ for(const x of ['Governação executiva','Dupla aprovação','CEO + Financeiro','Shareholder Wallet']) assert.equal(mainUi.includes(x),false,x); });
