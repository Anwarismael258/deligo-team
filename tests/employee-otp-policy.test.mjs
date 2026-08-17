import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const employee=fs.readFileSync('app/api/employees/route.ts','utf8');const login=fs.readFileSync('app/login/page.tsx','utf8');const otp=fs.readFileSync('app/api/auth/otp/verify/route.ts','utf8');
test('novos trabalhadores usam OTP e não senha padrão',()=>{assert.match(employee,/auth_method: "phone_otp"/);assert.match(employee,/phone_confirm: false/);assert.doesNotMatch(employee,/HQ_TEST_DEFAULT_PASSWORD/);});
test('fluxo OTP existe para solicitar e verificar telefone',()=>{assert.match(fs.readFileSync('app/api/auth/otp/request/route.ts','utf8'),/auth\/v1\/otp/);assert.match(otp,/grant_type=otp/);});
test('login informa política de primeiro acesso',()=>{assert.match(login,/OTP/);assert.match(login,/primeiro acesso/i);});
