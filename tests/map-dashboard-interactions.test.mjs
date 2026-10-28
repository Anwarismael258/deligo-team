import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import ts from 'typescript';
import * as presentation from '../lib/map-presentation.ts';

const require=createRequire(import.meta.url);
const source=readFileSync(new URL('../components/analytics/OperationsMapDashboard.tsx',import.meta.url),'utf8');
const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true}}).outputText;
const routes=Array.from({length:15},(_,index)=>({id:'sarca:trip:'+index,platform:'SARCA',label:'Viagem '+index,workerName:'Motorista '+index,coordinates:[[-25.9,32.5],[-25.8,32.6]],updatedAt:new Date().toISOString()}));

function harness({fullscreen=false,page=0,fetcher=async()=>Response.json({markers:[],routes})}={}){
  let index=0,refIndex=0;const updates=[],callbacks=[];const module={exports:{}};
  const native={entered:0,exited:0};const room={requestFullscreen:async()=>{native.entered++;}};
  const doc={visibilityState:'visible',fullscreenElement:fullscreen?room:null,exitFullscreen:async()=>{native.exited++;},body:{style:{}}};
  const loader=name=>{
    if(name==='react')return {...React,useState:initial=>{const key=index++;const value=key===0?fullscreen:key===1?page:key===5?{markers:[],routes,checkedAt:new Date().toISOString()}:initial;return[value,next=>updates.push({key,next})];},useRef:initial=>({current:refIndex++===0?room:initial}),useEffect(){},useMemo:fn=>fn(),useCallback:fn=>{callbacks.push(fn);return fn;}};
    if(name==='@/lib/map-presentation')return presentation;
    if(name==='@/components/LiveOperationsMap')return ()=>React.createElement('div',{'data-testid':'live-map'});
    if(name.endsWith('DashboardFilters'))return {DashboardFilters:()=>null};
    if(name.endsWith('OperationsDensityHeatmap'))return {OperationsDensityHeatmap:()=>null};
    if(name.endsWith('.css'))return new Proxy({},{get:(_,key)=>String(key)});
    return require(name);
  };
  new Function('require','module','exports','window','document','fetch',compiled)(loader,module,module.exports,{setTimeout:()=>1,clearTimeout(){}},doc,fetcher);
  const tree=module.exports.OperationsMapDashboard();
  return {tree,callbacks,updates,doc,native,html:renderToStaticMarkup(tree)};
}
function findButton(tree,text){
  if(!tree||typeof tree!=='object')return null;
  if(tree.type==='button'&&tree.props.children===text)return tree;
  for(const child of React.Children.toArray(tree.props?.children)){const found=findButton(child,text);if(found)return found;}return null;
}

test('active list shows only six operations and exposes the next page and fullscreen',()=>{
  const ui=harness();assert.equal((ui.html.match(/<strong>Viagem \d+/g)||[]).length,6);assert.match(ui.html,/Seguinte/);assert.match(ui.html,/1 \/ 3/);assert.match(ui.html,/Motorista 0/);assert.match(ui.html,/Tela cheia/);
  const next=harness({page:1});assert.match(next.html,/Viagem 6/);assert.doesNotMatch(next.html,/<strong>Viagem 0</);
});

test('fullscreen controls invoke the native browser entry and exit actions',async()=>{
  const ui=harness();await findButton(ui.tree,'Tela cheia').props.onClick();assert.equal(ui.native.entered,1);assert.ok(ui.updates.some(update=>update.key===0&&update.next===true));
  const full=harness({fullscreen:true});await findButton(full.tree,'Sair da tela cheia').props.onClick();assert.equal(full.native.exited,1);
});

test('live refresh never overlaps requests and preserves the last snapshot after a network failure',async()=>{
  let calls=0,resolve;
  const deferred=new Promise(done=>{resolve=done;});
  const ui=harness({fetcher:async()=>{calls++;if(calls===1)return deferred;throw new Error('network down');}});
  const refresh=ui.callbacks[0];const first=refresh();await refresh();assert.equal(calls,1);
  resolve(Response.json({markers:[],routes}));await first;
  await refresh();assert.equal(calls,2);
  assert.equal(ui.updates.filter(update=>update.key===5).length,1);
  assert.ok(ui.updates.some(update=>update.key===7&&update.next==='network down'));
  ui.doc.visibilityState='hidden';await refresh();assert.equal(calls,2);
});
