import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

const file=readFileSync(new URL('../lib/hq-server.ts',import.meta.url),'utf8');
const ast=ts.createSourceFile('hq-server.ts',file,ts.ScriptTarget.Latest,true);
const node=ast.statements.find(statement=>ts.isFunctionDeclaration(statement)&&statement.name?.text==='requireCorporatePermission');
const source=node.getText(ast).replace('export ','');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;

test('map reuses a verified request context while preserving platform and permission checks',async()=>{
  let authentications=0;
  const auth={isSuperAdmin:false,permissions:['operations.view'],platformSlugs:['sarca'],platformIds:[]};
  const requirePermission=new Function('corporateAuthorization',compiled+';return requireCorporatePermission;')(async()=>{authentications++;return auth;});
  assert.equal(await requirePermission('operations.view','sarca',auth),auth);
  assert.equal(await requirePermission('operations.view','deligo',auth),null);
  assert.equal(await requirePermission('finance.view','sarca',auth),null);
  assert.equal(authentications,0);
  assert.equal(await requirePermission('operations.view','sarca'),auth);
  assert.equal(authentications,1);
});
