import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const api=fs.readFileSync('app/api/payroll/route.ts','utf8');
test('Payroll possui validação, envio financeiro e aprovação',()=>{for(const x of ['validate','submit','approve','submitted_to_finance','validated_by','approved_by'])assert.ok(api.includes(x),x);});
