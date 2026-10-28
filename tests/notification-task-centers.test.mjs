import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";

const read=(path)=>readFile(new URL(`../${path}`,import.meta.url),"utf8");

test("centros pessoais consultam fontes reais e respeitam o utilizador autenticado",async()=>{
  const [tasks,notifications,page]=await Promise.all([read("app/api/my-tasks/route.ts"),read("app/api/notifications/route.ts"),read("app/page.tsx")]);
  assert.match(tasks,/corporateActor\(\)/);
  assert.match(tasks,/approval_requests/);
  assert.match(tasks,/workflow_steps/);
  assert.match(notifications,/employee_id=eq\.\$\{a\.employee_id\}/);
  assert.match(page,/Centro de Notificações/);
  assert.match(page,/Minhas Tarefas/);
});

test("respostas de agentes não entram na inbox de notificações da Central",async()=>{
  const notifications=await read("app/api/notifications/route.ts");
  assert.match(notifications,/sender_type=eq\.customer/);
  assert.match(notifications,/externalMessages[\s\S]{0,260}sender_type[\s\S]{0,100}customer/);
  assert.doesNotMatch(notifications,/externalMessages[\s\S]{0,260}sender_type[\s\S]{0,100}agent/);
});

test("regras de aprovação são configuráveis, auditadas e aplicadas no backend",async()=>{
  const [api,migration]=await Promise.all([read("app/api/approval-rules/route.ts"),read("supabase/migrations/370_hq_notification_task_approval_center.sql")]);
  assert.match(api,/actor\.role!=="SUPER_ADMIN"/);
  assert.match(api,/approval_rule_updated/);
  assert.match(migration,/create table if not exists hq\.approval_rules/);
  assert.match(migration,/create trigger trg_hq_apply_approval_rule/);
  assert.match(migration,/purchase_executive_approval_threshold_mzn/);
});
