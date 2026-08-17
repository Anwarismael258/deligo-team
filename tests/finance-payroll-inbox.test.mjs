import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const api=fs.readFileSync('app/api/finance/route.ts','utf8');const ui=fs.readFileSync('app/page.tsx','utf8');
test('Financeiro recebe períodos Payroll',()=>{assert.match(api,/payroll_runs/);assert.match(ui,/Payroll recebido do RH/);assert.match(ui,/Abrir Payroll/);});
