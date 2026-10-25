import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("respostas da Central são entregues à fonte da plataforma e notificam o utilizador", async () => {
  const route = await read("app/api/support/route.ts");
  assert.match(route, /SUPPORT_PLATFORM_REPLY_NOTIFICATION_FAILED/);
  assert.match(route, /p_type:"SUPPORT_MESSAGE_RECEIVED"/);
  assert.match(route, /p_action:"OPEN_SUPPORT_CHAT"/);
  assert.match(route, /p_dispatch_key:`support-reply:/);
  assert.match(route, /sourceRest\(current\.key,"mestre24","support_messages"/);
  assert.match(route, /sourceRest\(current\.key,"sarca","support_messages"/);
  assert.match(route, /stagingRest\("support_messages"/);
  assert.match(route, /notificationSent/);
});

test("a conversa preserva o nome do trabalhador nas respostas", async () => {
  const route = await read("app/api/support/route.ts");
  const page = await read("app/page.tsx");
  assert.match(route, /sender_name:null/);
  assert.match(route, /auth_user_id,employee_code/);
  assert.match(page, /m\.sender_name\|\|\(\(supportData\.employees\|\|\[\]\)\.find\(e=>e\.id===m\.sender_employee_id\|\|e\.auth_user_id===m\.sender_id\)/);
  assert.match(page, /· Trabalhador/);
});

test("tickets públicos duplicados são consolidados e respostas seguem o ticket do aplicativo", async () => {
  const route = await read("app/api/support/route.ts");
  assert.match(route, /publicCanonicalIdById/);
  assert.match(route, /external_source\|\|\"\"\)\.toLowerCase\(\)==="deligo_chat"/);
  assert.match(route, /let deliveryTicketId=publicId/);
  assert.match(route, /ticket_id:deliveryTicketId/);
  assert.match(route, /canonicalTicketId:deliveryTicketId/);
});
