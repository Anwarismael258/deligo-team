import {test} from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const exports={};
vm.runInNewContext(ts.transpileModule(await readFile(new URL('../lib/notification-policy.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports});
const {isRelevantNotification:allows}=exports;
test('incoming operational work and direct communications reach the centre',()=>{
 for(const title of ['Novo pedido','Nova viagem','Novo KYC','Novo pedido de marketing']) assert.equal(allows({type:'platform_event',title}),true,title);
 for(const type of ['manual_communication','internal_message','support_message','wallet_transfer_received','wallet_transfer_sent','balance_confirmation','deposit_confirmed']) assert.equal(allows({type}),true,type);
});
test('routine activity does not fill the centre',()=>{
 for(const source_type of ['audit','task','process_event','financial_event']) assert.equal(allows({source_type,title:'Novo pedido actualizado'}),false);
 assert.equal(allows({type:'information',title:'Perfil actualizado'}),false);
});
