import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRpc, supabaseUrl } from "@/lib/hq-server";

const entity = "10000000-0000-0000-0000-000000000001";
const readers = new Set(["SUPER_ADMIN", "FINANCE", "PARTNER_ACQUISITION", "FIELD", "OPERATIONS", "SUPERVISOR"]);
const writers = new Set(["SUPER_ADMIN", "FINANCE", "PARTNER_ACQUISITION", "OPERATIONS", "SUPERVISOR"]);
const platforms: Record<string, string> = {
  deligo: "20000000-0000-0000-0000-000000000001",
  comunhao: "20000000-0000-0000-0000-000000000002",
  corporate: "20000000-0000-0000-0000-000000000006",
  sarca: "20000000-0000-0000-0000-000000000004",
  mestre24: "20000000-0000-0000-0000-000000000005",
};

const headers = (key: string) => ({
  apikey: key,
  Authorization: `Bearer ${key}`,
  "Accept-Profile": "hq",
  "Content-Profile": "hq",
  "Content-Type": "application/json",
  Prefer: "return=representation",
});

async function context() {
  const actor = await corporateActor();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  return actor && key && readers.has(actor.role) ? { actor, key } : null;
}

async function rest(key: string, path: string, init: RequestInit = {}) {
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init,
    headers: { ...headers(key), ...(init.headers || {}) },
    cache: "no-store",
  });
  if (!response.ok) throw new Error(await response.text());
  return response.status === 204 ? null : response.json();
}

async function audit(key: string, actor: string, action: string, targetType: string, targetId: string, metadata: unknown) {
  await rest(key, "audit_logs", { method: "POST", body: JSON.stringify({ actor_employee_id: actor, action, legal_entity_id: entity, module: "acquisition", target_type: targetType, target_id: targetId, result: "success", metadata }) });
}

async function history(key: string, leadId: string, actor: string, event: string, description: string, before?: unknown, after?: unknown) {
  await rest(key, "acquisition_history", { method: "POST", body: JSON.stringify({ lead_id: leadId, actor_employee_id: actor, event_type: event, description, previous_state: before || null, final_state: after || null }) });
  await audit(key, actor, `acquisition_${event}`, "acquisition_lead", leadId, { before: before || null, after: after || null });
}

export async function GET(request: NextRequest) {
  const current = await context();
  if (!current) return NextResponse.json({ error: "Sem acesso à Aquisição de Parceiros." }, { status: 403 });
  const query = request.nextUrl.searchParams;
  const status = query.get("status");
  const search = query.get("search");
  const page = Math.max(1, Number(query.get("page") || 1));
  const pageSize = 20;
  let path = `acquisition_leads?select=*&order=updated_at.desc&limit=${pageSize}&offset=${(page - 1) * pageSize}`;
  if (status && status !== "all") path += `&stage=eq.${encodeURIComponent(status)}`;
  if (search) {
    const term = encodeURIComponent(search.replace(/[,*()]/g, " ").trim());
    path += `&or=(name.ilike.*${term}*,organization_name.ilike.*${term}*,contact.ilike.*${term}*,location.ilike.*${term}*)`;
  }
  const [leads, partners, visits, negotiations, objectives, events, cases, steps, employees, platformRows] = await Promise.all([
    rest(current.key, path), rest(current.key, "acquisition_partners?select=*&order=created_at.desc&limit=300"),
    rest(current.key, "acquisition_visits?select=*&order=scheduled_at.desc&limit=500"), rest(current.key, "acquisition_negotiations?select=*&order=created_at.desc&limit=500"),
    rest(current.key, "acquisition_objectives?select=*&order=period_start.desc&limit=100"), rest(current.key, "acquisition_history?select=*&order=created_at.desc&limit=500"),
    rest(current.key, "workflow_cases?case_type=eq.partner_onboarding&select=*&order=updated_at.desc&limit=300"), rest(current.key, "workflow_steps?select=*&order=step_order&limit=1000"),
    rest(current.key, "employees?select=id,name,employee_code,status&status=eq.active&limit=500"), rest(current.key, "platforms?select=id,name,slug&limit=20"),
  ]);
  const caseIds = new Set(cases.map((item:{id:string})=>item.id));
  return NextResponse.json({ data: { leads, partners, visits, negotiations, objectives, history: events, workflow_cases:cases, workflow_steps:steps.filter((item:{case_id:string})=>caseIds.has(item.case_id)), employees, platforms: platformRows }, pagination: { page, pageSize, hasMore: leads.length === pageSize } }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function POST(request: NextRequest) {
  const current = await context();
  if (!current || !writers.has(current.actor.role)) return NextResponse.json({ error: "Sem permissão para gerir aquisição." }, { status: 403 });
  const body = await request.json() as { resource?: string; record?: Record<string, unknown> };
  if (!body.resource || !body.record) return NextResponse.json({ error: "Registo inválido." }, { status: 400 });
  try {
    let table = "";
    let record = { ...body.record } as Record<string, unknown>;
    if (body.resource === "lead") {
      table = "acquisition_leads";
      const platformId = platforms[String(record.platform_slug)];
      if (!platformId) return NextResponse.json({ error: "Plataforma inválida." }, { status: 400 });
      record = { ...record, platform_id: platformId, legal_entity_id:entity, department_id:"30000000-0000-0000-0000-000000000011", created_by:current.actor.employee_id, owner_id: record.owner_id || current.actor.employee_id, stage: "new", status: "open" };
      delete record.platform_slug;
    } else if (body.resource === "visit") {
      table = "acquisition_visits";
      record = { ...record, created_by: current.actor.employee_id };
    } else if (body.resource === "negotiation") {
      table = "acquisition_negotiations";
      record = { ...record, owner_id: current.actor.employee_id };
    } else if (body.resource === "objective") {
      table = "acquisition_objectives";
      record = { ...record, legal_entity_id: entity, platform_id: platforms[String(record.platform_slug)] || null, created_by: current.actor.employee_id };
      delete record.platform_slug;
    } else return NextResponse.json({ error: "Tipo inválido." }, { status: 400 });

    const created = (await rest(current.key, table, { method: "POST", body: JSON.stringify(record) }))?.[0];
    if (body.resource === "visit") await rest(current.key, `acquisition_leads?id=eq.${record.lead_id}`, { method: "PATCH", body: JSON.stringify({ stage: "visit_scheduled" }) });
    if (body.resource === "negotiation") await rest(current.key, `acquisition_leads?id=eq.${record.lead_id}`, { method: "PATCH", body: JSON.stringify({ stage: "negotiating" }) });
    if (body.resource === "lead") await history(current.key, created.id, current.actor.employee_id, "created", "Lead registado", null, created);
    else if (record.lead_id) await history(current.key, String(record.lead_id), current.actor.employee_id, `${body.resource}_created`, `${body.resource} registado`, null, created);
    else await audit(current.key, current.actor.employee_id, `acquisition_${body.resource}_created`, table, created.id, { after: created });
    return NextResponse.json({ record: created }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "Não foi possível guardar o registo de aquisição." }, { status: 409 });
  }
}

export async function PATCH(request: NextRequest) {
  const current = await context();
  if (!current || !writers.has(current.actor.role)) return NextResponse.json({ error: "Sem permissão." }, { status: 403 });
  const body = await request.json() as { resource?: string; id?: string; action?: string; reason?: string; result?: string; partnerType?: string; agreementReference?: string };
  if (!body.resource || !body.id || !body.action) return NextResponse.json({ error: "Ação inválida." }, { status: 400 });
  try {
    if (body.resource === "lead") {
      const before = (await rest(current.key, `acquisition_leads?id=eq.${body.id}&select=*`))?.[0];
      if (!before) return NextResponse.json({ error: "Lead não encontrado." }, { status: 404 });
      if (body.action === "convert") {
        const converted = await hqRpc("hq_convert_acquisition_lead_v1", { p_lead_id: body.id, p_actor_employee_id: current.actor.employee_id, p_partner_type: body.partnerType || "business", p_agreement_reference: body.agreementReference || null });
        await audit(current.key, current.actor.employee_id, "acquisition_converted", "acquisition_lead", body.id, { partner_id: converted.partner?.id || null });
        return NextResponse.json({ record: converted });
      }
      const stages: Record<string, Record<string, unknown>> = { contact: { stage: "contacted" }, qualify: { stage: "qualified" }, negotiate: { stage: "negotiating" }, lose: { stage: "lost", status: "lost", notes: body.reason || before.notes }, archive: { status: "archived" } };
      if (!stages[body.action]) throw new Error();
      if (body.action === "lose" && !body.reason?.trim()) return NextResponse.json({ error: "Indique o motivo da perda." }, { status: 400 });
      const updated = (await rest(current.key, `acquisition_leads?id=eq.${body.id}`, { method: "PATCH", body: JSON.stringify(stages[body.action]) }))?.[0];
      await history(current.key, body.id, current.actor.employee_id, body.action, `Lead atualizado: ${body.action}`, before, updated);
      return NextResponse.json({ record: updated });
    }

    const tables: Record<string, string> = { visit: "acquisition_visits", negotiation: "acquisition_negotiations", partner: "acquisition_partners" };
    const table = tables[body.resource];
    if (!table) throw new Error();
    const before = (await rest(current.key, `${table}?id=eq.${body.id}&select=*`))?.[0];
    if (!before) return NextResponse.json({ error: "Registo não encontrado." }, { status: 404 });
    let patch: Record<string, unknown> = {};
    if (body.resource === "visit") {
      const statuses: Record<string, string> = { start: "in_progress", complete: "completed", cancel: "cancelled", no_show: "no_show" };
      if (!statuses[body.action]) throw new Error();
      patch = { status: statuses[body.action], ...(body.result ? { result: body.result } : {}), ...(body.action === "complete" ? { completed_at: new Date().toISOString() } : {}) };
    } else if (body.resource === "negotiation") {
      const statuses: Record<string, string> = { submit: "submitted", counter: "countered", accept: "accepted", reject: "rejected" };
      if (!statuses[body.action]) throw new Error();
      patch = { status: statuses[body.action], ...(["accept", "reject"].includes(body.action) ? { decided_at: new Date().toISOString() } : {}) };
      if (body.action === "accept") await rest(current.key, `acquisition_leads?id=eq.${before.lead_id}`, { method: "PATCH", body: JSON.stringify({ stage: "won" }) });
    } else {
      const statuses: Record<string, string> = { activate: "active", suspend: "suspended", deactivate: "inactive" };
      if (!statuses[body.action]) throw new Error();
      patch = { status: statuses[body.action], ...(body.action === "activate" ? { activated_at: new Date().toISOString() } : {}) };
    }
    const updated = (await rest(current.key, `${table}?id=eq.${body.id}`, { method: "PATCH", body: JSON.stringify(patch) }))?.[0];
    const leadId = String(before.lead_id || before.source_lead_id || "");
    if (leadId) await history(current.key, leadId, current.actor.employee_id, `${body.resource}_${body.action}`, `${body.resource} atualizado`, before, updated);
    return NextResponse.json({ record: updated });
  } catch {
    return NextResponse.json({ error: "A operação foi bloqueada pelo estado atual." }, { status: 409 });
  }
}
