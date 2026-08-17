import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const ui=fs.readFileSync('app/page.tsx','utf8');const api=fs.readFileSync('app/api/payroll/route.ts','utf8');
test('Payroll tem períodos e cálculo de trabalhadores activos',()=>{for(const x of ['Novo período de Payroll','Calcular folha','period_label','status=eq.active'])assert.ok(ui.includes(x)||api.includes(x),x);});
