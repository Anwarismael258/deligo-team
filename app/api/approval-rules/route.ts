import { NextRequest, NextResponse } from "next/server";
import { corporateActor, supabaseUrl } from "@/lib/hq-server";

const h = (key: string): Record<string, string> => ({ apikey: key, Authorization: `Bearer ${key}`, "Accept-Profile": "hq", "Content-Profile": "hq", "Content-Type": "application/json", Prefer: "return=representation" });
async function rest(key: string, path: string, init: RequestInit = {}) {
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, { ...init, headers: { ...h(key), ...Object.fromEntries(new Headers(init.headers).entries()) }, cache: "no-store" });
  if (!response.ok) throw new Error(await response.text());
  return response.status === 204 ? null : response.json();
}

export async function GET() {
  const actor = await corporateActor();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!actor || !key) return NextResponse.json({ error: "Sessão inválida." }, { status: 401 });
  const [rules, departments] = await Promise.all([rest(key, "approval_rules?select=*&order=request_type,sequence_order&limit=300"), rest(key, "departments?select=id,name,code&active=eq.true&order=name")]);
  return NextResponse.json({ data: { rules, departments }, canManage: ["SUPER_ADMIN", "FINANCE"].includes(actor.role) }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function PATCH(req: NextRequest) {
  const actor = await corporateActor();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!actor || !key || actor.role!=="SUPER_ADMIN" && actor.role!=="FINANCE") return NextResponse.json({ error: "Configuração reservada ao Administrador ou Finanças." }, { status: 403 });
  const body = await req.json() as { id?: string; amountMin?: number | null; amountMax?: number | null; departmentId?: string; requiredApprovals?: number; active?: boolean; priority?: string };
  if (!body.id || !body.departmentId || Number(body.requiredApprovals || 0) < 1) return NextResponse.json({ error: "Regra inválida." }, { status: 400 });
  try {
    const current = (await rest(key, `approval_rules?id=eq.${encodeURIComponent(body.id)}&select=*`))?.[0];
    const patch = { amount_min: body.amountMin ?? null, amount_max: body.amountMax ?? null, approver_department_id: body.departmentId, required_approvals: body.requiredApprovals, active: Boolean(body.active), priority: body.priority || "normal", updated_by: actor.employee_id, updated_at: new Date().toISOString() };
    const updated = (await rest(key, `approval_rules?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify(patch) }))?.[0];
    await rest(key, "audit_logs", { method: "POST", body: JSON.stringify({ actor_employee_id: actor.employee_id, action: "approval_rule_updated", module: "approvals", target_type: "approval_rule", target_id: body.id, result: "success", before_state: current, after_state: updated }) });
    return NextResponse.json({ record: updated });
  } catch {
    return NextResponse.json({ error: "Não foi possível atualizar a regra. Verifique intervalos sobrepostos." }, { status: 409 });
  }
}
