import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import ts from 'typescript';

async function route(role, current={id:'task-1',assigned_to:'me',status:'planned'}) {
 const calls=[];
 const context=vm.createContext({process:{env:{}},fetch:async(url,init={})=>{
  calls.push({url,init});
  const rows=url.includes('tasks?')?[current]:url.includes('employees?')?[{id:'me',status:'active'}]:url.includes('/tasks')?[current]:[];
  return {ok:true,status:200,json:async()=>rows};
 }});
 const source=ts.transpileModule(await readFile(new URL('../app/api/projects/route.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
 const exports={};
 context.exports=exports;
 context.require=name=>name==='next/server'?{NextResponse:{json:(body,options={})=>({body,status:options.status||200})}}:{corporateActor:async()=>role?{employee_id:'me',role}:null,hqServiceKey:()=> 'test-key',supabaseUrl:()=> 'https://test.invalid'};
 vm.runInContext(source,context);
 return {api:exports,calls};
}
const req=body=>({json:async()=>body});
for(const role of ['SUPER_ADMIN','FINANCE','SUPERVISOR']) test(`${role} pode atribuir tarefas`,async()=>{
 const {api}=await route(role);
 assert.equal((await api.POST(req({resource:'task',record:{title:'Teste',assigned_to:'me'}}))).status,201);
});
for(const role of ['FIELD','CUSTOMER_SUPPORT','MARKETING','EMPLOYEE','ACCOUNTING']) test(`${role} não pode atribuir tarefas`,async()=>{
 const {api,calls}=await route(role);
 assert.equal((await api.POST(req({resource:'task',record:{title:'Teste',assigned_to:'me'}}))).status,403);
 assert.equal(calls.length,0);
});
test('destinatário pode abrir, marcar como lida e concluir a sua tarefa',async()=>{
 const {api,calls}=await route('EMPLOYEE');
 assert.equal((await api.PATCH(req({resource:'task',id:'task-1',action:'read'}))).status,200);
 assert(calls.some(c=>c.url.includes('employee_id=eq.me')&&c.url.includes('source_id=eq.task-1')&&c.init.method==='PATCH'));
 assert.equal((await api.PATCH(req({resource:'task',id:'task-1',action:'complete'}))).status,200);
});
test('trabalhador não altera tarefa alheia nem cancela a própria',async()=>{
 const {api}=await route('FIELD',{id:'task-1',assigned_to:'other',status:'planned'});
 assert.equal((await api.PATCH(req({resource:'task',id:'task-1',action:'complete'}))).status,403);
 const own=await route('FIELD');
 assert.equal((await own.api.PATCH(req({resource:'task',id:'task-1',action:'cancel'}))).status,403);
});
test('consulta pessoal filtra tarefas na base de dados e permite todos os trabalhadores activos',async()=>{
 const {api,calls}=await route('EMPLOYEE');
 const response=await api.GET();
 assert.equal(response.status,200);
 assert.equal(response.body.canAssign,false);
 assert(calls.filter(c=>c.url.includes('/tasks?')).every(c=>c.url.includes('assigned_to=eq.me')));
});
test('sessão ausente não consulta dados',async()=>{
 const {api,calls}=await route(null);
 assert.equal((await api.GET()).status,403);
 assert.equal(calls.length,0);
});
