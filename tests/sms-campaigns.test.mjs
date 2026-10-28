import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const helper = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../lib/sms-campaigns.ts', import.meta.url), 'utf8'))).toString('base64'));
const { smsSegments, mozPhone, campaignMessage, sendMozeSms } = helper;

test('normaliza telefones sem aceitar números incompletos ou de outro país', () => {
  assert.equal(mozPhone('84 123 4567'), '258841234567');
  assert.equal(mozPhone('+258 84 123 4567'), '258841234567');
  for (const value of ['84-11315', '+27841234567', '258801234567', '']) assert.equal(mozPhone(value), null);
});
test('contabiliza GSM-7 básico, extensão e Unicode por unidades UTF-16', () => {
  assert.equal(smsSegments('').segments, 0);
  assert.equal(smsSegments('a'.repeat(160)).segments, 1);
  assert.equal(smsSegments('a'.repeat(161)).segments, 2);
  assert.equal(smsSegments('^'.repeat(80)).segments, 1);
  assert.equal(smsSegments('^'.repeat(81)).segments, 2);
  assert.equal(smsSegments('ã'.repeat(70)).segments, 1);
  assert.equal(smsSegments('ã'.repeat(71)).segments, 2);
  assert.equal(smsSegments('😊'.repeat(36)).segments, 2);
});
test('valida mensagem antes de qualquer pedido pago', () => {
  assert.equal(campaignMessage('  Olá!  '), 'Olá!');
  for (const value of [null, {}, '', ' ', 'a'.repeat(1001)]) assert.throws(() => campaignMessage(value));
});
const config = { key: 'test-key', secret: 'test-secret', sender: 'DELIGO' };
test('usa a API SMS e o remetente aprovado, sem confundir aceite com entregue', async () => {
  let calls = 0;
  const result = await sendMozeSms(config, '258841234567', 'Teste', async (url, options) => {
    calls++;
    assert.equal(url, 'https://api.mozesms.com/sms/send');
    assert.equal(options.headers['X-API-Key'], config.key);
    assert.equal(options.headers['X-API-Secret'], config.secret);
    assert.deepEqual(JSON.parse(options.body), { phone: '258841234567', message: 'Teste', sender_id: 'DELIGO' });
    return Response.json({ success: true, data: { id: 'provider-1', cost: 1.35 } });
  });
  assert.equal(calls, 1);
  assert.deepEqual(result, { status: 'accepted', reference: 'provider-1', cost: 1.35 });
});
test('falhas explícitas são separadas de timeouts e respostas incertas sem repetir o envio', async () => {
  const scenarios = [
    [async () => new Response('', { status: 402 }), 'failed'],
    [async () => new Response('', { status: 429 }), 'failed'],
    [async () => Response.json({ success: false }), 'failed'],
    [async () => new Response('', { status: 500 }), 'unknown'],
    [async () => Response.json({ success: true }), 'unknown'],
    [async () => new Response('not json'), 'unknown'],
    [async () => { throw new Error('timeout'); }, 'unknown'],
  ];
  for (const [transport, expected] of scenarios) {
    let calls = 0;
    const result = await sendMozeSms(config, '258841234567', 'Teste', async (...args) => { calls++; return transport(...args); });
    assert.equal(result.status, expected);
    assert.equal(calls, 1);
  }
});

test('saldo inválido bloqueia campanhas e a margem OTP é obrigatória', async () => {
  const { mozeBalance, smsBudgetAllows } = helper;
  assert.deepEqual(await mozeBalance(config, async () => Response.json({ success: true, data: { balance: 100, unit_price_mzn: 1.35, currency: 'MZN' } })), { balance: 100, unitPrice: 1.35 });
  for (const data of [{ balance: '100', unit_price_mzn: 1, currency: 'MZN' }, { balance: 100, currency: 'MZN' }, { balance: 100, unit_price_mzn: 1, currency: 'USD' }]) await assert.rejects(() => mozeBalance(config, async () => Response.json({ success: true, data })));
  assert.equal(smsBudgetAllows(100, 1.35, 1, 50), true);
  assert.equal(smsBudgetAllows(50, 1.35, 1, 50), false);
  assert.equal(smsBudgetAllows(100, 1.35, 1, NaN), false);
  assert.equal(smsBudgetAllows(100, 1.35, 1, 0), false);
});
