import { NextRequest, NextResponse } from "next/server";
import { hqServiceKey, requireCorporatePermission, supabaseUrl } from "@/lib/hq-server";

const resources = ["pricing_adjustment_policy", "pricing_zones", "pricing_time_windows", "toll_points"] as const;
type PricingResource = (typeof resources)[number];

function isResource(value: unknown): value is PricingResource {
  return typeof value === "string" && resources.includes(value as PricingResource);
}

function headers(key: string, content = false) {
  const result: Record<string, string> = {
    apikey: key,
    ...(content ? { "Content-Type": "application/json", Prefer: "return=representation" } : {}),
    "Accept-Profile": "sarca",
    ...(content ? { "Content-Profile": "sarca" } : {}),
  };
  if (!key.startsWith("sb_secret_")) result.Authorization = `Bearer ${key}`;
  return result;
}

async function sarcaRest(key: string, path: string, init: RequestInit = {}) {
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init,
    headers: { ...headers(key, Boolean(init.body)), ...(init.headers || {}) },
    cache: "no-store",
    signal: AbortSignal.timeout(8000),
  });
  const body = await response.text();
  if (!response.ok) throw new Error(body || `SARCA_PRICING_${response.status}`);
  return body.trim() ? JSON.parse(body) : null;
}

async function canManage() {
  for (const permission of ["platform.manage", "finance.manage", "operations.manage"]) {
    const authorization = await requireCorporatePermission(permission, "sarca");
    if (authorization) return authorization;
  }
  return null;
}

export async function GET() {
  const authorization = await requireCorporatePermission("operations.view", "sarca");
  if (!authorization) return NextResponse.json({ error: "Sem permissão para consultar o preço do SARCA." }, { status: 403 });
  const key = hqServiceKey();
  if (!key) return NextResponse.json({ error: "Serviço da Central não configurado." }, { status: 503 });
  try {
    const [policy, zones, timeWindows, tolls] = await Promise.all(resources.map((resource) =>
      sarcaRest(key, `${resource}?select=*&order=updated_at.desc`),
    ));
    return NextResponse.json({ policy: policy?.[0] || null, zones: zones || [], timeWindows: timeWindows || [], tolls: tolls || [] }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    console.error("SARCA_PRICING_READ_FAILED", error);
    return NextResponse.json({ error: "Não foi possível carregar as regras de preço do SARCA." }, { status: 502 });
  }
}

export async function POST(request: NextRequest) {
  const authorization = await canManage();
  if (!authorization) return NextResponse.json({ error: "Sem permissão para alterar o preço do SARCA." }, { status: 403 });
  const key = hqServiceKey();
  if (!key) return NextResponse.json({ error: "Serviço da Central não configurado." }, { status: 503 });
  const body = await request.json().catch(() => ({})) as { resource?: unknown; record?: Record<string, unknown> };
  if (!isResource(body.resource) || !body.record || typeof body.record !== "object") {
    return NextResponse.json({ error: "Recurso e configuração são obrigatórios." }, { status: 400 });
  }
  const record: Record<string, unknown> = { ...(body.record as Record<string, unknown>), updated_by: authorization.actor.employee_id };
  if (body.resource === "toll_points") {
    record.last_verified_at = record.last_verified_at || new Date().toISOString();
    record.verified_by_user_id = authorization.actor.authUserId;
  }
  try {
    const result = body.resource === "pricing_adjustment_policy"
      ? await sarcaRest(key, "pricing_adjustment_policy?id=eq.1", { method: "PATCH", body: JSON.stringify(record) })
      : record.id
        ? await sarcaRest(key, `${body.resource}?id=eq.${encodeURIComponent(String(record.id))}`, { method: "PATCH", body: JSON.stringify(record) })
        : await sarcaRest(key, body.resource, { method: "POST", body: JSON.stringify(record) });
    await fetch(`${supabaseUrl()}/rest/v1/audit_logs`, {
      method: "POST",
      headers: { ...headers(key, true), "Accept-Profile": "hq", "Content-Profile": "hq" },
      body: JSON.stringify({ actor_employee_id: authorization.actor.employee_id, action: "sarca_pricing_configuration_updated", module: "sarca", target_type: body.resource, target_id: String(record.id || "1"), result: "success", metadata: { fields: Object.keys(record) } }),
    }).catch((error) => console.error("SARCA_PRICING_AUDIT_FAILED", error));
    return NextResponse.json({ record: Array.isArray(result) ? result[0] : result });
  } catch (error) {
    console.error("SARCA_PRICING_WRITE_FAILED", error);
    return NextResponse.json({ error: "Não foi possível guardar esta configuração." }, { status: 409 });
  }
}

export async function DELETE(request: NextRequest) {
  const authorization = await canManage();
  if (!authorization) return NextResponse.json({ error: "Sem permissão para remover esta configuração." }, { status: 403 });
  const key = hqServiceKey();
  if (!key) return NextResponse.json({ error: "Serviço da Central não configurado." }, { status: 503 });
  const body = await request.json().catch(() => ({})) as { resource?: unknown; id?: unknown };
  if (!isResource(body.resource) || body.resource === "pricing_adjustment_policy" || !body.id) {
    return NextResponse.json({ error: "Só é possível remover uma zona, janela horária ou portagem identificada." }, { status: 400 });
  }
  try {
    await sarcaRest(key, `${body.resource}?id=eq.${encodeURIComponent(String(body.id))}`, { method: "DELETE" });
    await fetch(`${supabaseUrl()}/rest/v1/audit_logs`, {
      method: "POST",
      headers: { ...headers(key, true), "Accept-Profile": "hq", "Content-Profile": "hq" },
      body: JSON.stringify({ actor_employee_id: authorization.actor.employee_id, action: "sarca_pricing_configuration_removed", module: "sarca", target_type: body.resource, target_id: String(body.id), result: "success", metadata: {} }),
    }).catch((error) => console.error("SARCA_PRICING_AUDIT_FAILED", error));
    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("SARCA_PRICING_DELETE_FAILED", error);
    return NextResponse.json({ error: "Não foi possível remover esta configuração." }, { status: 409 });
  }
}
