import test from 'node:test';
import assert from 'node:assert/strict';
import { groupKycCases, documentsForCase, sarcaDocumentNames } from '../lib/kyc-presentation.ts';

const rows=Object.keys(sarcaDocumentNames).map((type,index)=>({id:`hq-${index}`,subject_user_id:'driver-1',applicant_name:'Motorista Teste',platform_name:'SARCA',document_type:type,status:'approved',document_references:[{signed_url:`https://storage.example/${type}.jpg`,label:type}]}));

test('ten SARCA documents form one person with one independently named photo for each document',()=>{
  const groups=groupKycCases(rows);
  assert.equal(groups.length,1);assert.equal(groups[0].name,'Motorista Teste');assert.equal(groups[0].status,'approved');
  assert.equal(groups[0].documents.length,10);
  assert.deepEqual(groups[0].documents.map(document=>document.label),Object.values(sarcaDocumentNames));
  assert.equal(new Set(groups[0].documents.map(document=>document.url)).size,10);
  assert.equal(groups[0].documents.find(document=>document.label==='BI frente').caseId,'hq-0');
});

test('a pending document keeps the person out of approved KYC; different people never share their photos',()=>{
  const groups=groupKycCases([...rows.map((row,index)=>index===0?{...row,status:'submitted'}:row),{...rows[0],id:'other-case',subject_user_id:'driver-2',applicant_name:'Outro motorista'}]);
  assert.equal(groups.length,2);assert.equal(groups[0].status,'submitted');assert.equal(groups[1].documents.length,1);
});

test('complete-profile documents retain the SARCA labels and unavailable files remain explicit',()=>{
  assert.equal(documentsForCase({id:'doc',document_type:'vehicle_registration',file_path:'https://storage.example/livrete.jpg',status:'approved'})[0].label,'Livrete');
  assert.equal(documentsForCase({id:'missing',document_type:'selfie',file_path:'private/not-signed.jpg'})[0].url,null);
});
