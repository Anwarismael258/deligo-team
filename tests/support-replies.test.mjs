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
