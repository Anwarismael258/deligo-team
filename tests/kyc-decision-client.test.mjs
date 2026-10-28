import test from 'node:test';
import assert from 'node:assert/strict';
import { submitKycDecision } from '../lib/kyc-decision-client.ts';

test('returns the committed SARCA outcome without fetching photographs or reloading the dashboard', async () => {
  const calls=[];
  const fetcher=async (url, options)=>{
    calls.push(url);
    assert.equal(options.method,'PATCH');
    assert.ok(options.signal);
    assert.equal(JSON.parse(options.body).decision,'approve');
    return Response.json({result:{status:'approved',driver_status:'active',notification_id:'notification-1'}});
  };
  const result=await submitKycDecision('/api/kyc',{caseId:'case-1',decision:'approve'},fetcher);
  assert.deepEqual(calls,['/api/kyc']);
  assert.equal(result.result.driver_status,'active');
});

test('does not turn a rejected decision or a network failure into a success', async () => {
  await assert.rejects(submitKycDecision('/api/kyc',{},async()=>Response.json({error:'Motivo obrigatório'},{status:400})),/Motivo obrigatório/);
  await assert.rejects(submitKycDecision('/api/kyc',{},async()=>{throw new Error('network failed')}),/network failed/);
});
