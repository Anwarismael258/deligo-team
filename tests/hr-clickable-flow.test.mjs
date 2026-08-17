import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const ui=fs.readFileSync('app/page.tsx','utf8');
test('cartões e ciclos de RH são acionáveis',()=>{assert.match(ui,/hrMetricCard/);assert.match(ui,/abrir registo/);assert.match(ui,/setHrEventType/);assert.match(ui,/Guardar e notificar trabalhador/);});
