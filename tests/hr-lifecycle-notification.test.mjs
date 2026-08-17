import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const api=fs.readFileSync('app/api/hr/route.ts','utf8');const ui=fs.readFileSync('app/page.tsx','utf8');
test('registo laboral cria notificação dirigida ao trabalhador',()=>{assert.match(api,/employee_id:record\.employee_id/);assert.match(api,/hr_lifecycle_event/);assert.match(api,/dedupe_key:`hr-event:/);});
test('UI permite escolher todos os ciclos laborais',()=>{for(const x of ['Horários e turnos','Férias e licenças','Payroll e benefícios','Avaliação de desempenho','Guardar e notificar trabalhador'])assert.ok(ui.includes(x),x);});
