import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const api=fs.readFileSync('app/api/employees/route.ts','utf8');const ui=fs.readFileSync('app/page.tsx','utf8');
test('RH carrega avatar apenas do display profile',()=>{assert.match(api,/employee_display_profiles/);assert.match(api,/avatar_url/);});
test('tabela de RH mostra foto ou iniciais',()=>{assert.match(ui,/employeeAvatar/);assert.match(ui,/Foto de/);assert.match(ui,/employeeAvatarFallback/);});
