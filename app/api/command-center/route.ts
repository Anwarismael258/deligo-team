import { NextResponse } from "next/server";
import { corporateAuthorization, hqRest } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

const restricted = new Set(["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "FINANCE", "ACCOUNTING", "COMPLIANCE"]);
const count = (rows: unknown) => Array.isArray(rows) ? rows.length : 0;
const rowsOrEmpty = async (request: Promise<unknown>) => {
  try {
    const value = await request;
    return Array.isArray(value) ? value : [];
  } catch {
    return [];
  }
};

export async function GET() {
  const authorization = await corporateAuthorization();
  if (!authorization || (!authorization.isSuperAdmin && !restricted.has(authorization.actor.role))) {
    return NextResponse.json({ error: "Sem permissão para o Command Center." }, { status: 403 });
  }
  const scope = !authorization.isSuperAdmin && authorization.platformIds.length
    ? `&platform_id=in.(${authorization.platformIds.join(",")})`
    : "";
  try {
    // Each platform adapter is optional. A single delayed source must never
    // blank the corporate overview that the CEO depends on.
    const [platforms, events, financial, pendingKyc, openSupport, notifications] = await Promise.all([
      rowsOrEmpty(hqRest(`platforms?select=id,slug,name,platform_code,integration_status,status&order=name`)),
      rowsOrEmpty(hqRest(`platform_events?select=id,event_type,entity_type,entity_id,payload,occurred_at,platforms(slug,name,platform_code)&order=occurred_at.desc&limit=80${scope}`)),
      rowsOrEmpty(hqRest(`platform_financial_events?select=gross_amount,platform_fee,payment_status,occurred_at,platforms(slug,name,platform_code)&order=occurred_at.desc&limit=200${scope}`)),
      rowsOrEmpty(hqRest(`platform_kyc_cases?select=*&status=in.(submitted,under_review,correction_requested)&limit=500${scope}`)),
      rowsOrEmpty(hqRest(`support_tickets?select=*&status=in.(open,in_analysis,waiting_customer)&limit=500${scope}`)),
      rowsOrEmpty(hqRest(`platform_notification_requests?select=*&status=in.(draft,approved,queued,failed)&limit=500${scope}`)),
    ]);
    const financeRows = Array.isArray(financial) ? financial as Record<string, unknown>[] : [];
    const confirmed = financeRows.filter((row) => row.payment_status === "confirmed");
    const today = new Date().toISOString().slice(0, 10);
    const todayConfirmed = confirmed.filter((row) => String(row.occurred_at || "").slice(0, 10) === today);
    const sum = (rows: Record<string, unknown>[], field: string) => rows.reduce((total, row) => total + Number(row[field] || 0), 0);
    const eventRows = Array.isArray(events) ? events as Record<string, unknown>[] : [];
    const platformName = (platformId: unknown) => {
      const platform = (Array.isArray(platforms) ? platforms as Record<string, unknown>[] : []).find((item) => String(item.id) === String(platformId));
      return String(platform?.name || platform?.platform_code || platformId || "Plataforma não indicada");
    };
    const pendingActions = [
      ...(Array.isArray(pendingKyc) ? pendingKyc as Record<string, unknown>[] : []).map((row) => ({ id: String(row.id || ""), category: "kyc", priority: String(row.priority || "normal"), responsible: String(row.assigned_to || row.assignee_name || "Não atribuído"), dueAt: row.due_at || row.sla_due_at || null, waitingSince: row.created_at || row.updated_at || null, origin: platformName(row.platform_id), status: String(row.status || "pending"), nextAction: "Abrir Operações de Campo", href: "/field" })),
      ...(Array.isArray(openSupport) ? openSupport as Record<string, unknown>[] : []).map((row) => ({ id: String(row.id || ""), category: "support", priority: String(row.priority || "Não indicada"), responsible: String(row.assigned_to || row.assignee_name || "Não atribuído"), dueAt: row.due_at || row.sla_due_at || null, waitingSince: row.created_at || row.updated_at || null, origin: platformName(row.platform_id), status: String(row.status || "open"), nextAction: "Abrir Apoio ao Cliente", href: "/apoio-cliente" })),
      ...(Array.isArray(notifications) ? notifications as Record<string, unknown>[] : []).map((row) => ({ id: String(row.id || ""), category: "notifications", priority: String(row.priority || "Não indicada"), responsible: String(row.assigned_to || row.assignee_name || "Não atribuído"), dueAt: row.due_at || null, waitingSince: row.created_at || row.updated_at || null, origin: platformName(row.platform_id), status: String(row.status || "pending"), nextAction: "Abrir Notificações", href: "/notificacoes" })),
    ].slice(0, 100);
    const perPlatform = (Array.isArray(platforms) ? platforms as Record<string, unknown>[] : []).map((platform) => {
      const id = String(platform.id);
      const platformEvents = eventRows.filter((event) => String((event.platforms as Record<string, unknown> | null)?.slug || "") === String(platform.slug));
      const platformFinancial = financeRows.filter((row) => String((row.platforms as Record<string, unknown> | null)?.slug || "") === String(platform.slug));
      return { ...platform, operationsToday: platformEvents.filter((event) => String(event.occurred_at || "").slice(0, 10) === today).length, revenueToday: sum(platformFinancial.filter((row) => row.payment_status === "confirmed" && String(row.occurred_at || "").slice(0, 10) === today), "platform_fee"), pendingKyc: (Array.isArray(pendingKyc) ? pendingKyc : []).filter((row) => String((row as Record<string, unknown>).platform_id) === id).length };
    });
    return NextResponse.json({
      checkedAt: new Date().toISOString(),
      summary: { gmvToday: sum(todayConfirmed, "gross_amount"), revenueToday: sum(todayConfirmed, "platform_fee"), operationsToday: eventRows.filter((event) => String(event.occurred_at || "").slice(0, 10) === today).length, pendingKyc: count(pendingKyc), openSupport: count(openSupport), notificationWork: count(notifications) },
      platforms: perPlatform,
      liveFeed: eventRows,
      pendingActions,
    }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Command Center indisponível." }, { status: 502 });
  }
}
