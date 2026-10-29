import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
function load(path,deps){const exports={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(new URL('../'+path,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,jsx:ts.JsxEmit.ReactJSX}}).outputText,{exports,require:deps,URLSearchParams});return exports;}
const charts=load('components/analytics/AnalyticsCharts.tsx',require);
for(const mode of ['institutional','jobs'])test(`${mode} renders dated API series without crashing the module`,()=>{
 let state=0;
 const values=[{period:'last_30_days'}, {data:{series:[{date:'2026-10-28',value:0},{date:'2026-10-29',value:1}] }}, {}, '', 'financial', '', false];
 const stub=({children})=>React.createElement('div',null,children);
 const {CorporateOperationsAnalyticsDashboard}=load('components/analytics/CorporateOperationsAnalyticsDashboard.tsx',name=>name==='react'?{useState:()=>[values[state++],()=>{}],useEffect:()=>{}}:name.endsWith('AnalyticsCharts')?charts:name==='react/jsx-runtime'?require(name):new Proxy({}, {get:()=>stub}));
 const html=renderToStaticMarkup(React.createElement(CorporateOperationsAnalyticsDashboard,{mode}));
 assert.match(html,/2026-10-29/);assert.match(html,/<svg/);assert.doesNotMatch(html,/undefined/);
});
