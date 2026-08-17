import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const ui=fs.readFileSync('app/page.tsx','utf8');
test('RH expõe Centro de Payroll funcional',()=>{for(const x of ['PAYROLL','Novo registo salarial','Salário bruto (MZN)','Criar folha em rascunho','hr_payroll_records'])assert.ok(ui.includes(x),x);});
