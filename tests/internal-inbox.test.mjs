import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import ts from 'typescript';
const actorId='10000000-0000-0000-0000-000000000001',conversationId='20000000-0000-0000-0000-000000000001';
async function route(role,{member=true}={}){
 const calls=[];class InboxError extends Error{constructor(message,status=400){super(message);this.status=status}}
 const context=vm.createContext({console:{error(){}},URL,Date,Number,process:{env:{}},crypto:globalThis.crypto});const exports={};context.exports=exports;
 context.require=name=>name==='next/server'?{NextResponse:{json:(body,o={})=>({body,status:o.status||200})}}:name.includes('hq-server')?{hqRest:async path=>{calls.push(path);return []},hqRpc:async(name,payload)=>{calls.push({name,payload});return name==='chat_create_v1'?conversationId:[]}}:{InboxError,isUuid:v=>typeof v==='string'&&/^[0-9a-f-]{36}$/.test(v),inboxActor:async()=>{if(!role)throw new InboxError('Sem sessão',401);return {employee_id:actorId,role}},requireConversation:async()=>{if(!member)throw new InboxError('Sem acesso',403);return conversationId},meetingUrl:()=> 'https://meet.jit.si/DeliGo-random'};
 const source=ts.transpileModule(await readFile(new URL('../app/api/internal-inbox/route.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
 vm.runInContext(source,context);return {api:exports,calls};
}
const req=body=>({json:async()=>body});
for(const role of ['SUPER_ADMIN','FINANCE','SUPERVISOR','MARKETING','FIELD','CUSTOMER_SUPPORT','EMPLOYEE'])test(`Inbox: ${role} pode iniciar conversa`,async()=>{
 const {api,calls}=await route(role);const r=await api.POST(req({action:'create',title:'',recipients:[actorId]}));assert.equal(r.status,201);assert.equal(calls[0].payload.p_actor,actorId);
});
test('Inbox: ausência de sessão bloqueia criação',async()=>{const {api,calls}=await route(null);assert.equal((await api.POST(req({action:'create',title:'',recipients:[]}))).status,401);assert.equal(calls.length,0)});
test('Inbox: não participante não envia nem marca leitura',async()=>{const {api}=await route('SUPER_ADMIN',{member:false});assert.equal((await api.POST(req({action:'send',conversationId}))).status,403);assert.equal((await api.PATCH(req({conversationId}))).status,403)});
test('Inbox: envio valida conteúdo e identifica o autor no servidor',async()=>{const {api,calls}=await route('FIELD');const b={action:'send',conversationId,clientId:crypto.randomUUID(),body:'Olá equipa',senderId:'forged'};assert.equal((await api.POST(req(b))).status,201);assert.equal(calls[0].payload.p_actor,actorId);assert.equal((await api.POST(req({...b,body:'x'.repeat(10001)}))).status,400)});
test('Inbox: reunião usa URL gerada no servidor',async()=>{const {api,calls}=await route('EMPLOYEE');assert.equal((await api.POST(req({action:'meeting',conversationId,clientId:crypto.randomUUID(),body:'Reunião',meetingUrl:'https://evil.invalid'}))).status,201);assert.equal(calls[0].payload.p_meeting,'https://meet.jit.si/DeliGo-random')});

test('PostgreSQL: migração, conversas, anexos, privacidade, respostas, leitura e reenvio', {skip:!process.env.INBOX_PGLITE_MODULE},async()=>{
 const {PGlite}=await import(process.env.INBOX_PGLITE_MODULE);const db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema hq;create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table hq.employees(id uuid primary key,display_name text,status text);create table hq.notifications(id uuid default gen_random_uuid(),employee_id uuid,type text,title text,body text,target_url text,source_type text,source_id text,read_at timestamptz,created_at timestamptz default now());`);
 const sql=await readFile(new URL('../supabase/migrations/486_hq_internal_messenger.sql',import.meta.url),'utf8');await db.exec(sql);await db.exec(sql);
 const a=actorId,b='10000000-0000-0000-0000-000000000002',c='10000000-0000-0000-0000-000000000003',d='10000000-0000-0000-0000-000000000004';
 await db.query(`insert into hq.employees values($1,'A','active'),($2,'B','active'),($3,'C','active'),($4,'D','suspended')`,[a,b,c,d]);
 const create=async(who,recipients,title='',all=false)=>(await db.query('select hq.chat_create_v1($1,$2,$3,$4) id',[who,recipients,title,all])).rows[0].id;
 const direct=await create(a,[b]);assert.equal(await create(b,[a]),direct);
 await assert.rejects(create(a,[d]));
 const group=await create(a,[],'Todos',true);assert.equal((await db.query('select count(*)::int n from hq.chat_members where conversation_id=$1',[group])).rows[0].n,3);
 const send=async(who,conv,body,client=crypto.randomUUID(),reply=null,files=[])=> (await db.query('select (hq.chat_send_v1($1,$2,$3,$4,$5,$6,null)).*',[who,conv,body,client,reply,files])).rows[0];
 const client=crypto.randomUUID(),msg=await send(a,direct,'Olá',client);assert.equal((await send(a,direct,'Olá',client)).id,msg.id);
 assert.equal((await db.query('select count(*)::int n from hq.chat_messages')).rows[0].n,1);
 await assert.rejects(send(c,direct,'Segredo'));await assert.rejects(send(d,group,'Inválida'));
 const groupMsg=await send(c,group,'Grupo');await assert.rejects(send(b,direct,'Resposta',crypto.randomUUID(),groupMsg.id));
 const reply=await send(b,direct,'Recebido',crypto.randomUUID(),msg.id);assert.equal(reply.reply_to,msg.id);
 const fileId=crypto.randomUUID();await db.query(`insert into hq.chat_attachments(id,conversation_id,uploaded_by,storage_path,file_name,mime_type,size_bytes) values($1,$2,$3,'private/test','teste.pdf','application/pdf',100)`,[fileId,direct,a]);
 await assert.rejects(send(b,direct,'Roubo',crypto.randomUUID(),null,[fileId]));
 const attached=await send(a,direct,'Anexo',crypto.randomUUID(),null,[fileId]);assert.equal((await db.query('select message_id from hq.chat_attachments where id=$1',[fileId])).rows[0].message_id,attached.id);
 await assert.rejects(send(a,direct,'Reutilização',crypto.randomUUID(),null,[fileId]));
 const list=(await db.query('select hq.chat_list_v1($1) data',[b])).rows[0].data;assert(list.find(x=>x.id===direct).unread>=2);
 await db.query('select hq.chat_read_v1($1,$2,$3)',[b,direct,attached.id]);assert.equal((await db.query('select hq.chat_list_v1($1) data',[b])).rows[0].data.find(x=>x.id===direct).unread,0);
 assert(!(await db.query('select hq.chat_list_v1($1) data',[c])).rows[0].data.some(x=>x.id===direct));
 assert.equal((await db.query("select public from storage.buckets where id='hq-internal-inbox'")).rows[0].public,false);
 await db.close();
});

test('Anexos: não participante não recebe URL assinada nem faz upload',async()=>{
 for(const endpoint of ['file','upload']){
  let storageCalls=0;class InboxError extends Error{constructor(message,status=400){super(message);this.status=status}}
  const context=vm.createContext({console,URL,File,process:{env:{}},fetch:async()=>{storageCalls++;throw new Error('Storage não deve ser chamado')}}),exports={};context.exports=exports;
  context.require=name=>name==='next/server'?{NextResponse:{json:(body,o={})=>({body,status:o.status||200}),redirect:()=>{throw new Error('Não deve redireccionar')}}}:name.includes('hq-server')?{hqRest:async()=>[{conversation_id:conversationId,storage_path:'private/secret'}],hqServiceKey:()=> 'unused',supabaseUrl:()=> 'https://test.invalid'}:{InboxError,inboxActor:async()=>({employee_id:actorId}),isUuid:()=>true,requireConversation:async()=>{throw new InboxError('Sem acesso',403)},inboxBucket:'hq-internal-inbox',maxAttachmentBytes:3145728,attachmentTypes:new Set(['application/pdf'])};
  const source=ts.transpileModule(await readFile(new URL(`../app/api/internal-inbox/${endpoint}/route.ts`,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;vm.runInContext(source,context);
  const r=endpoint==='file'?await exports.GET({nextUrl:new URL(`https://test.invalid/?id=${actorId}`)}):await exports.POST({headers:new Headers(),formData:async()=>new Map([['conversationId',conversationId]])});
  assert.equal(r.status,403);assert.equal(storageCalls,0);
 }
});
