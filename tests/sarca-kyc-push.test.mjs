import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

const source=readFileSync(new URL('../lib/sarca-kyc-push.ts',import.meta.url),'utf8').replace(/^import .*;$/m,'').replace('export async function','async function');
const script=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText;
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const notification={id:'n1',user_id:'driver1',type:'SARCA_KYC_REJECTED',title:'KYC rejeitado',body:'Fotografia ilegível',action:'OPEN_DRIVER_ONBOARDING',data:{app:'sarca'},metadata:{app:'sarca'},dispatch_key:'sarca-kyc:1'};

async function run({delivery='push',status=200,claimed=true}={}){
  const calls=[];
  const fn=await new AsyncFunction('hqRpc','hqServiceKey','stagingRest','supabaseUrl','fetch','crypto','process','console',script+';return flushSarcaKycPush;')(
    async (name,body)=>{calls.push({name,body});return name==='claim_sarca_kyc_push_v1'?(claimed?notification:null):null;},
    ()=>'server-key',async()=>[{id:'n1'}],()=> 'https://project.supabase.co',
    async(url,options)=>{calls.push({url,request:JSON.parse(options.body)});return Response.json({success:true,data:{targets:[{delivery}]}},{status});},
    {randomUUID:()=> 'worker-1'},{env:{}},{error(){}});
  await fn('n1');return calls;
}

test('delivers the stored rejection reason only to its driver and marks successful delivery',async()=>{
  const calls=await run();
  const request=calls.find(c=>c.request).request;
  assert.equal(request.user_id,'driver1');assert.equal(request.body,'Fotografia ilegível');assert.equal(request.dispatch_key,'sarca-kyc:1');
  assert.equal(calls.at(-1).body.p_status,'sent');
});

test('provider failure remains retryable; a device without push remains in-app only',async()=>{
  assert.equal((await run({status:503})).at(-1).body.p_status,'failed');
  assert.equal((await run({delivery:'in_app_only'})).at(-1).body.p_status,'in_app_only');
});

test('another worker cannot send an already claimed notification',async()=>{
  const calls=await run({claimed:false});assert.equal(calls.length,1);
});
