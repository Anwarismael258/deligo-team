import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const ui=fs.readFileSync('app/login/page.tsx','utf8');
test('OTP não mostra campo de senha no primeiro acesso',()=>{assert.match(ui,/mode===\"password\"&&<label className=\"loginField\">/);assert.match(ui,/Não coloque uma senha agora/);assert.match(ui,/name=\"otp\"/);});
