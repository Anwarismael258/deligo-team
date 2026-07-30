import { NextRequest, NextResponse } from "next/server";
import { corporateActor, stagingRest } from "@/lib/hq-server";

export const dynamic = "force-dynamic";
type Module = "marketing" | "support" | "field";
type Row = Record<string, unknown>;
const access: Record<Module, string[]> = {
  marketing: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "MARKETING"],
  support: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "CUSTOMER_SUPPORT"],
  field: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "FIELD"],
};
const getRows = async (path: string) => { try { return await stagingRest(path) as Row[]; } catch (error) { console.error("HQ operational source unavailable", path, error); return []; } };

export async function GET(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  const module = request.nextUrl.searchParams.get("module") as Module;
  if (!access[module]?.includes(actor.role)) return NextResponse.json({ error: "Sem permissão para este módulo." }, { status: 403 });
  let collections: Record<string, Row[]>;
  if (module === "support") {
    const [tickets, disputes] = await Promise.all([getRows("support_tickets?select=*&order=updated_at.desc&limit=120"), getRows("order_disputes?select=*&order=created_at.desc&limit=80")]);
    collections = { tickets, disputes };
  } else if (module === "marketing") {
    const [requests, campaigns, events] = await Promise.all([getRows("marketing_requests?select=*&order=created_at.desc&limit=150"), getRows("marketing_campaigns?select=*&order=created_at.desc&limit=120"), getRows("marketing_events?select=*&order=created_at.desc&limit=120")]);
    collections = { requests, campaigns, events };
  } else {
    const [deligoKyc, sarcaDrivers, comunhaoChurches, taomozSellerKyc, taomozSellers, restaurants, couriers, notes] = await Promise.all([
      getRows("profiles?select=id,full_name,phone,role,city,address,email,kyc_status,kyc_rejection_reason,approval_submitted_at,approval_sla_deadline,verification_score,is_blocked,created_at,updated_at&role=in.(restaurant,courier)&order=updated_at.desc&limit=250"),
      getRows("driver_profiles?select=*&order=updated_at.desc&limit=250"),
      getRows("church_applications?select=*&order=updated_at.desc&limit=250"),
      getRows("kyc_submissions?select=*&role=eq.seller&order=updated_at.desc&limit=250"),
      getRows("seller_profiles?select=*&order=updated_at.desc&limit=250"),
      getRows("restaurants?select=*&order=created_at.desc&limit=120"), getRows("couriers?select=*&order=created_at.desc&limit=120"), getRows("field_internal_notes?select=*&order=created_at.desc&limit=100"),
    ]);
    const tag = (rows: Row[], platform: string, subjectType: string) => rows.map(row => ({ ...row, _platform: platform, _subject_type: subjectType }));
    const sellerByProfile = new Map(taomozSellers.map(row => [String(row.profile_id || ""), row]));
    const taomozKyc = taomozSellerKyc.map(row => ({ ...sellerByProfile.get(String(row.profile_id || "")), ...row }));
    collections = {
      verifications: [...tag(deligoKyc, "DeliGo", "Estafeta / Restaurante"), ...tag(sarcaDrivers, "SARCA", "Condutor"), ...tag(comunhaoChurches, "Comunhão", "Igreja"), ...tag(taomozKyc, "TaoMoz", "Vendedor")],
      deligoKyc: tag(deligoKyc, "DeliGo", "Estafeta / Restaurante"), sarcaDrivers: tag(sarcaDrivers, "SARCA", "Condutor"), comunhaoChurches: tag(comunhaoChurches, "Comunhão", "Igreja"), taomozSellers: tag(taomozKyc, "TaoMoz", "Vendedor"), restaurants, couriers, notes,
    };
  }
  return NextResponse.json({ module, collections, checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function PATCH(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  const body = await request.json() as { module?: Module; entity?: string; id?: string; action?: string };
  if (!body.module || !access[body.module]?.includes(actor.role)) return NextResponse.json({ error: "Sem permissão." }, { status: 403 });
  if (!body.id) return NextResponse.json({ error: "Registo inválido." }, { status: 400 });
  if (body.module === "support" && body.entity === "tickets" && ["open", "in_progress", "resolved", "closed"].includes(body.action || "")) {
    const resolved = ["resolved", "closed"].includes(body.action || "");
    const now = new Date().toISOString();
    const update = { status: body.action, updated_at: now, ...(resolved ? { resolved_at: now, resolution: "Concluído no HQ corporativo" } : {}) };
    const rows = await stagingRest(`support_tickets?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify(update) });
    return NextResponse.json({ ok: true, rows });
  }
  return NextResponse.json({ error: "Acção ainda não autorizada neste fluxo." }, { status: 400 });
}
