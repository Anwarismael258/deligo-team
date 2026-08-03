import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=(path)=>fs.readFileSync(new URL(`../${path}`,import.meta.url),"utf8");
const migration=read("supabase/migrations/373_hq_realtime_process_activity_and_comments.sql");
const realtime=read("app/api/realtime/route.ts");
const activity=read("app/api/processes/[id]/activity/route.ts");
const inbox=read("app/components/WorkflowInbox.tsx");
const page=read("app/page.tsx");
const propagation=read("supabase/migrations/374_hq_cross_module_state_propagation.sql");
const field=read("app/api/field/route.ts");
const legal=read("app/api/legal/route.ts");

test("eventos, linha temporal, comentários e menções são persistidos no backend",()=>{
  for(const table of ["process_events","process_comments","process_comment_mentions","realtime_events"])assert.match(migration,new RegExp(`create table if not exists hq\\.${table}`));
  assert.match(migration,/hq_add_process_comment_v1/);
  assert.match(migration,/process_mention/);
  assert.match(migration,/process_comment_added/);
  assert.match(migration,/audit_logs/);
});

test("canal incremental respeita sessão e plataformas atribuídas",()=>{
  assert.match(realtime,/corporateAuthorization/);
  assert.match(realtime,/authorization\.platformIds/);
  assert.match(realtime,/id=gt/);
  assert.match(realtime,/Cache-Control":"private, no-store/);
});

test("cada processo mostra atividade real e comentários ligados",()=>{
  assert.match(activity,/workflow_cases\?id=eq/);
  assert.match(activity,/process_events\?workflow_case_id=eq/);
  assert.match(activity,/process_comments\?workflow_case_id=eq/);
  assert.match(inbox,/Linha temporal/);
  assert.match(inbox,/@GestorFinanceiro verificar orçamento/);
  assert.match(inbox,/attachmentReference/);
});

test("telas ativas e mapa atualizam automaticamente",()=>{
  assert.match(page,/api\/realtime\?after/);
  assert.match(page,/setInterval\(\(\)=>void poll\(\),2500\)/);
  assert.match(page,/setInterval\(\(\) => void refreshMap\(\), 3_000\)/);
  for(const refresh of ["refreshFinance","refreshProcurement","refreshLegal","refreshField","refreshSupport","refreshMarketing","refreshBi","refreshWorkflows"])assert.match(page,new RegExp(refresh));
});

test("estados críticos propagam entre departamentos",()=>{
  assert.match(propagation,/propagate_finance_payment_to_procurement/);
  assert.match(propagation,/update hq\.purchase_requests set status='paid'/);
  assert.match(field,/step_type=eq\.kyc_review/);
  assert.match(field,/hq_decide_workflow_step_v1/);
  assert.match(legal,/step_type=eq\.contract_review/);
  assert.match(legal,/Contrato \$\{body\.status\}/);
});
