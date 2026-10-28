import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import ts from 'typescript';
import * as presentation from '../lib/kyc-presentation.ts';

const require=createRequire(import.meta.url);
const source=readFileSync(new URL('../components/KycWorkspace.tsx',import.meta.url),'utf8');
const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true}}).outputText;
const rows=Object.keys(presentation.sarcaDocumentNames).map((type,index)=>({id:`hq-${index}`,subject_user_id:'driver-1',applicant_name:'Motorista Teste',platform_name:'SARCA',document_type:type,status:'submitted',document_references:[{signed_url:`https://storage.example/${type}.jpg`}]}));

function render(view,selected=null,approved=false){
  const states=[view,selected];const module={exports:{}};
  const loader=name=>name==='react'?{...React,useState:initial=>[states.length?states.shift():initial,()=>{}],useMemo:fn=>fn()}:name==='@/lib/kyc-presentation'?presentation:name==='@/lib/download-document'?{downloadDocument:async()=>{}}:name.endsWith('.css')?new Proxy({},{get:(_,key)=>String(key)}):require(name);
  new Function('require','module','exports',compiled)(loader,module,module.exports);
  return renderToStaticMarkup(React.createElement(module.exports.default,{rows:approved?rows.map(row=>({...row,status:'approved'})):rows,notice:'',busy:{},canDecide:true,onDecision:async()=>{},onOpenProfile(){}}));
}

test('KYC landing only exposes the queue selector; the pending queue has one driver and no loose photographs',()=>{
  const home=render('');assert.match(home,/Selecionar/);assert.doesNotMatch(home,/<img/);
  const pending=render('pending');assert.match(pending,/Ver detalhes/);assert.match(pending,/Voltar/);
  assert.equal((pending.match(/Motorista Teste/g)||[]).length,1);assert.doesNotMatch(pending,/<img/);
});

test('opening pending details shows one labelled photo per document',()=>{
  const html=render('pending','sarca:driver-1');assert.equal((html.match(/<img /g)||[]).length,10);
  for(const label of Object.values(presentation.sarcaDocumentNames))assert.ok(html.includes(label));
});

test('approved queue only opens the complete profile and never leaves approved photographs in the queue',()=>{
  const html=render('approved',null,true);assert.match(html,/Abrir perfil completo/);assert.doesNotMatch(html,/<img/);assert.doesNotMatch(html,/Pedir correção/);
  assert.doesNotMatch(render('pending','sarca:driver-1',true),/<img/);
});
