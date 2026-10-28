import test from 'node:test';
import assert from 'node:assert/strict';
import {handleCentralEmployeePayout} from '../supabase/functions/central-employee-payout/handler.ts';
import {personalWalletAmounts} from '../lib/finance-custody.ts';
const id='10000000-0000-4000-8000-000000000001';
const user={id:'verified-user',phone:'258861234567',phone_confirmed_at:'2026-10-01'};
function fixture({fresh=true,foreign=false,pending=[],providerStatus='completed',providerAmount='33.23',providerPhone='861234567'}={}){
 const calls=[];
 const payout={id,fresh,net_minor:3323,phone:'861234567',holder:'Sara',method:'emola',reference:'DLGWDTEST',metadata:{reference:'DLGWDTEST',central_dispatch_started_at:'now'}};
 function builder(schema,table){const filters={};const b={select(){return b},eq(k,v){filters[k]=v;return b},limit(){return b},update(value){calls.push({update:value,schema});return b},single:async()=>({data:{id:'employee',auth_user_id:user.id,phone_e164:user.phone}}),maybeSingle:async()=>({data:{personal_phone:user.phone}}),then(resolve,reject){return Promise.resolve({data:pending,error:null}).then(resolve,reject)}};return b}
 const db={schema(schema){return {from:table=>builder(schema,table),rpc:async(name,args)=>{calls.push({name,args});return foreign?{error:'owner mismatch'}:{data:payout}}}},rpc:async(name,args)=>{calls.push({name,args});return {data:name==='hq_actor_context_v1'?{employee_id:'employee',status:'active'}:{ok:true}}}};
 const fetcher=async(url,options)=>{calls.push({url,options});return Response.json({status:'success',data:{id:'provider-1',reference:'DLGWDTEST',amount:providerAmount,status:providerStatus,beneficiary:{phone:providerPhone}}})};
 return {db,calls,fetcher};
}
const config={baseUrl:'https://provider.example/api/v1',token:'server-secret'};
test('Sara consolidated 34.26 remains available without changing the legacy wallet',async()=>{
 const wallets=await personalWalletAmounts([{id:'canonical',available_balance_minor:3426}], '8c772bb5-1f35-47f8-93ca-d6e2c8909b4d',async()=>{throw Error('unnecessary legacy read')});
 assert.equal(wallets[0].available_balance_minor,3426);
});
test('dispatch uses reserved net amount and verified destination, ignoring browser values',async()=>{
 const f=fixture({providerStatus:'pending'});const response=await handleCentralEmployeePayout({action:'central_employee_payout',payout_id:id,kind:'canonical',amount:9999,phone:'849999999'},user,f.db,config,f.fetcher);
 const sent=JSON.parse(f.calls.find(x=>x.url).options.body);assert.equal(sent.amount,'33.23');assert.equal(sent.beneficiary.phone,'861234567');assert.equal(sent.method,'emola');assert.equal(sent.webhook_url,undefined);
 assert.equal((await response.json()).provider_response.data.status,'pending');assert.equal(f.calls.some(x=>/complete_/.test(x.name||'')),false);
});
test('duplicate dispatch and foreign ownership cannot send another payout',async()=>{
 for(const options of [{fresh:false},{foreign:true}]){const f=fixture(options);await handleCentralEmployeePayout({action:'central_employee_payout',payout_id:id,kind:'canonical'},user,f.db,config,f.fetcher);assert.equal(f.calls.filter(x=>x.url).length,0)}
});
test('network ambiguity preserves reservation for authenticated reconciliation',async()=>{
 const f=fixture();const response=await handleCentralEmployeePayout({action:'central_employee_payout',payout_id:id,kind:'canonical'},user,f.db,config,async()=>{throw Error('timeout')});
 assert.equal((await response.json()).reconciliationRequired,true);assert.equal(f.calls.some(x=>/fail_/.test(x.name||'')),false);
});
test('completion requires matching provider reference, net amount and destination',async()=>{
 const request={id,amount_minor:3426,fee_minor:103,destination_phone:user.phone,metadata:{reference:'DLGWDTEST',central_provider_id:'provider-1',central_dispatch_started_at:'now'}};
 for(const mismatch of [false,true]){const f=fixture({pending:[request],providerAmount:mismatch?'34.26':'33.23'});await handleCentralEmployeePayout({action:'central_employee_reconcile'},user,f.db,config,f.fetcher);assert.equal(f.calls.some(x=>x.name==='complete_paysuite_payout_v1'),!mismatch)}
});
