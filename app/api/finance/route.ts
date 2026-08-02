import { NextRequest, NextResponse } from "next/server";
import { corporateActor, supabaseUrl } from "@/lib/hq-server";

const allowed = new Set(["SUPER_ADMIN", "FINANCE", "ACCOUNTING"]);
const legalEntityId = "10000000-0000-0000-0000-000000000001";
const platformIds: Record<string, string> = {
  deligo: "20000000-0000-0000-0000-000000000001",
  comunhao: "20000000-0000-0000-0000-000000000002",
  taomoz: "20000000-0000-0000-0000-000000000003",
  sarca: "20000000-0000-0000-0000-000000000004",
};
const tables = ["financial_accounts", "financial_transactions", "budgets", "payment_requests", "cashflow_forecasts", "profit_distributions"] as const;

const apiHeaders = (key: string) => ({
  apikey: key,
  Authorization: `Bearer ${key}`,
  "Accept-Profile": "hq",
  "Content-Profile": "hq",
  "Content-Type": "application/json",
  Prefer: "return=representation",
});

async function financeContext() {
  const actor = await corporateActor();
  if (!actor || !allowed.has(actor.role)) return null;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  return key ? { actor, key, headers: apiHeaders(key) } : null;
}

async function writeAudit(key: string, actorId: string, action: string, targetType: string, targetId: string, platformId?: string | null) {
  await fetch(`${supabaseUrl()}/rest/v1/audit_logs`, {
    method: "POST",
    headers: apiHeaders(key),
    body: JSON.stringify({ actor_employee_id: actorId, action, legal_entity_id: legalEntityId, platform_id: platformId || null, module: "finance", target_type: targetType, target_id: targetId, result: "success" }),
  });
}

export async function GET() {
  const context = await financeContext();
  if (!context) return NextResponse.json({ error: "Acesso reservado a Finanças, Contabilidade e Super Admin." }, { status: 403 });
  const rows = await Promise.all(tables.map(async (table) => {
    const order = table === "financial_transactions" ? "occurred_at" : "created_at";
    const response = await fetch(`${supabaseUrl()}/rest/v1/${table}?select=*&order=${order}.desc&limit=250`, { headers: context.headers, cache: "no-store" });
    return [table, response.ok ? await response.json() : []] as const;
  }));
  return NextResponse.json({ data: Object.fromEntries(rows), checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function POST(request: NextRequest) {
  const context = await financeContext();
  if (!context) return NextResponse.json({ error: "Sem permissão para registar operações financeiras." }, { status: 403 });
  const body = await request.json() as { resource?: string; record?: Record<string, unknown> };
  if (!body.resource || !body.record || !["financial_accounts", "financial_transactions", "budgets", "payment_requests", "cashflow_forecasts"].includes(body.resource)) {
    return NextResponse.json({ error: "Operação financeira inválida." }, { status: 400 });
  }
  const record = { ...body.record, legal_entity_id: legalEntityId } as Record<string, unknown>;
  const platformSlug = typeof record.platform_slug === "string" ? record.platform_slug : "";
  delete record.platform_slug;
  record.platform_id = platformIds[platformSlug] || null;
  if (body.resource === "financial_transactions") record.created_by = context.actor.employee_id;
  if (body.resource === "payment_requests") record.requested_by = context.actor.employee_id;
  if (body.resource === "cashflow_forecasts") record.created_by = context.actor.employee_id;
  if (body.resource === "budgets") {
    record.created_by = context.actor.employee_id;
    record.financial_year = Number(record.financial_year) || new Date().getFullYear();
  }
  const response = await fetch(`${supabaseUrl()}/rest/v1/${body.resource}`, { method: "POST", headers: context.headers, body: JSON.stringify(record) });
  if (!response.ok) return NextResponse.json({ error: "Não foi possível guardar o registo financeiro." }, { status: 400 });
  const created = (await response.json())[0];
  await writeAudit(context.key, context.actor.employee_id, `finance_${body.resource}_created`, body.resource, created.id, created.platform_id);
  return NextResponse.json({ record: created }, { status: 201 });
}

export async function PATCH(request: NextRequest) {
  const context = await financeContext();
  if (!context) return NextResponse.json({ error: "Sem permissão para aprovar pagamentos." }, { status: 403 });
  const body = await request.json() as { paymentId?: string; action?: "approve" | "reject" | "mark_paid"; receiptPath?: string };
  if (!body.paymentId || !body.action || !["approve", "reject", "mark_paid"].includes(body.action)) return NextResponse.json({ error: "Aprovação inválida." }, { status: 400 });
  const lookup = await fetch(`${supabaseUrl()}/rest/v1/payment_requests?id=eq.${encodeURIComponent(body.paymentId)}&select=*`, { headers: context.headers, cache: "no-store" });
  const current = lookup.ok ? (await lookup.json())[0] as { status?:string; requested_by?:string } | undefined : undefined;
  if (!current) return NextResponse.json({ error: "Pagamento não encontrado." }, { status: 404 });
  if (body.action === "approve" && current.status !== "pending") return NextResponse.json({ error: "Apenas pagamentos pendentes podem ser aprovados." }, { status: 409 });
  if (body.action === "approve" && current.requested_by === context.actor.employee_id) return NextResponse.json({ error: "O solicitante não pode aprovar o próprio pagamento." }, { status: 409 });
  if (body.action === "mark_paid" && current.status !== "approved") return NextResponse.json({ error: "O pagamento precisa estar aprovado antes de ser marcado como pago." }, { status: 409 });
  if (body.action === "reject" && !["pending", "approved"].includes(current.status || "")) return NextResponse.json({ error: "Este pagamento já está encerrado." }, { status: 409 });
  const status = body.action === "approve" ? "approved" : body.action === "reject" ? "rejected" : "paid";
  const changes: Record<string, unknown> = { status, updated_at: new Date().toISOString() };
  if (body.action === "approve") changes.approved_by = context.actor.employee_id;
  if (body.action === "mark_paid") {
    changes.paid_at = new Date().toISOString();
    if (body.receiptPath) changes.receipt_path = body.receiptPath;
  }
  const response = await fetch(`${supabaseUrl()}/rest/v1/payment_requests?id=eq.${encodeURIComponent(body.paymentId)}`, { method: "PATCH", headers: context.headers, body: JSON.stringify(changes) });
  if (!response.ok) return NextResponse.json({ error: "Não foi possível atualizar o pagamento." }, { status: 400 });
  const updated = (await response.json())[0];
  await writeAudit(context.key, context.actor.employee_id, `finance_payment_${status}`, "payment_requests", body.paymentId, updated?.platform_id);
  return NextResponse.json({ record: updated });
}
