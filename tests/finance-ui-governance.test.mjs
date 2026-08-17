import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const ui=fs.readFileSync('app/page.tsx','utf8');
test('UI financeiro mostra tesouraria e separação de finalidades',()=>{ for(const x of ['Centro de Tesouraria','Treasury / Operating','Tax &amp; Obligations','Profit Reserve']) assert.ok(ui.includes(x),x); });
test('UI financeiro expõe governação executiva e dupla aprovação',()=>{ for(const x of ['Governação executiva','Dupla aprovação','CEO + Financeiro','Shareholder Wallet']) assert.ok(ui.includes(x),x); });
