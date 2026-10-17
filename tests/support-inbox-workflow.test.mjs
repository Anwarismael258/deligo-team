import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("Finance cannot bypass the financial-ticket reply restriction", async () => {
  const source = await read("app/api/support/route.ts");
  assert.match(source, /if\(isFinanceRole\(current\.actor\.role\)\)return isFinancialTicket\(ticket\)/);
  assert.match(source, /if\(!assignmentAction&&!canReplyToTicket\(current,ticket\)\)/);
});

test("financial classification does not trust customer-controlled free text", async () => {
  const source = await read("app/api/support/route.ts");
  const start = source.indexOf("function isFinancialTicket(");
  const end = source.indexOf("\\n}", start);
  const classifier = source.slice(start, end);
  assert.match(classifier, /ticket\.category,ticket\.ticket_type,ticket\.assigned_team/);
  assert.doesNotMatch(classifier, /ticket\.subject|ticket\.description|ticket\.resolution/);
});

test("app support cases can be assigned to an active linked support employee", async () => {
  const source = await read("app/api/support/route.ts");
  assert.match(source, /employees\?id=eq\.\$\{encodeURIComponent\(body\.employeeId\)\}&select=id,department_id,status,auth_user_id/);
  assert.match(source, /assigned_user_id:employee\.auth_user_id/);
  assert.match(source, /event_type:body\.action==="escalate"\?"hq_escalated":"hq_assigned"/);
});

test("support UI exposes a real reply composer and removes the hidden legacy form", async () => {
  const source = await read("app/page.tsx");
  assert.match(source, /className="financeEntryForm supportReplyForm" onSubmit=\{submitSupportReply\}/);
  assert.match(source, /resource:"message",record:\{ticket_id:selectedSupportTicket,message:supportReplyDraft\.trim\(\),is_internal:supportReplyInternal\}/);
  assert.doesNotMatch(source, /showSupportForm/);
  assert.doesNotMatch(source, /workflowBridge" hidden/);
});
