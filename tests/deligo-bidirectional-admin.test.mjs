import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
const read=p=>fs.readFileSync(p,"utf8");

test("comandos DeliGo exigem RBAC, motivo e executam apenas RPC central",()=>{
  const api=read("app/api/deligo/admin-command/route.ts");
  assert.match(api,/requireCorporatePermission\("platform\.manage", "deligo"\)/);
  assert.match(api,/reason\.length < 6/);
  assert.match(api,/hq_deligo_admin_command_v1/);
  assert.doesNotMatch(api,/\.from\(|SUPABASE_SERVICE_ROLE_KEY/);
});

test("Central confirma ações críticas e expõe comandos dos três perfis",()=>{
  const [button,page]=[read("app/components/DeligoCommandButton.tsx"),read("app/page.tsx")];
  assert.match(button,/Confirmar ação crítica/);assert.match(button,/Motivo obrigatório/);
  for(const action of ["block_client","suspend_restaurant","disable_courier","cancel_order","approve_kyc","reject_kyc"])assert.match(page,new RegExp(action));
});
