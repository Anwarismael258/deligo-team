import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, hqRest } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

type Period = "last_7_days" | "last_30_days" | "last_90_days" | "custom";
type Row = Record<string, unknown>;
const dayMs = 86_400_000;

function validDate(value: string | null) {
  return value && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00+02:00`)) ? value : null;
}

function maputoDate(date: Date) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Maputo", year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
}

function maputoStart(date: string) { return new Date(`${date}T00:00:00+02:00`); }
function isoEnd(date: string) { return new Date(maputoStart(date).getTime() + dayMs).toISOString(); }

function periodRange(period: Period, from: string | null, to: string | null) {
  const today = maputoDate(new Date());
  const end = period === "custom" ? to : today;
  const days = period === "last_7_days" ? 7 : period === "last_90_days" ? 90 : 30;
  if (period === "custom" && from && end) {
    return {
      from,
      to: end,
      days: Math.max(
        1,
        Math.round((maputoStart(end).getTime() - maputoStart(from).getTime()) / dayMs) + 1,
      ),
    };
  }
  const endDate = maputoStart(end || today);
  const startDate = new Date(endDate.getTime() - (days - 1) * dayMs);
  return { from: maputoDate(startDate), to: end || today, days };
}

function previousRange(current: { from: string; to: string; days: number }) {
  const end = new Date(maputoStart(current.from).getTime() - dayMs);
  const start = new Date(end.getTime() - (current.days - 1) * dayMs);
  return { from: maputoDate(start), to: maputoDate(end), days: current.days };
}

function amount(value: unknown) { return typeof value === "number" && Number.isFinite(value) ? value : Number(value || 0); }
function eventKey(row: Row, kind: string) { return `${kind}:${String(row.platform_id || "")}:${String(row.source_record_id || row.source_event_id || row.id || "")}`; }

function emptyDay(date: string) { return { date, revenue: 0, gmv: 0, commissions: 0, operations: 0, cancellations: 0, financialEvents: 0, operationalEvents: 0 }; }

function aggregate(financialRows: Row[], operationalRows: Row[], from: string, to: string) {
  const days = new Map<string, ReturnType<typeof emptyDay>>();
  const cursor = maputoStart(from);
  const end = maputoStart(to);
  while (cursor <= end) { const date = maputoDate(cursor); days.set(date, emptyDay(date)); cursor.setTime(cursor.getTime() + dayMs); }
  const financialSeen = new Set<string>();
  for (const row of financialRows) {
    const key = eventKey(row, "financial"); if (financialSeen.has(key)) continue; financialSeen.add(key);
    if (String(row.payment_status || "") !== "confirmed") continue;
    const date = maputoDate(new Date(String(row.occurred_at || row.created_at))); const day = days.get(date); if (!day) continue;
    day.revenue += amount(row.platform_fee); day.commissions += amount(row.platform_fee); day.gmv += amount(row.gross_amount); day.financialEvents += 1;
  }
  const operationalSeen = new Set<string>();
  for (const row of operationalRows) {
    const key = eventKey(row, "operational"); if (operationalSeen.has(key)) continue; operationalSeen.add(key);
    const date = maputoDate(new Date(String(row.occurred_at || row.created_at))); const day = days.get(date); if (!day) continue;
    day.operations += 1; day.operationalEvents += 1;
    if (/(cancel|cancelled|canceled|rejected|failed)/i.test(String(row.event_type || ""))) day.cancellations += 1;
  }
  return [...days.values()].map(day => Object.fromEntries(Object.entries(day).map(([key, value]) => [key, key === "date" ? value : Number(Number(value).toFixed(2))])));
}

function totals(series: Array<Record<string, unknown>>) {
  return ["revenue", "gmv", "commissions", "operations", "cancellations"].reduce<Record<string, number>>((result, key) => { result[key] = Number(series.reduce((sum, row) => sum + amount(row[key]), 0).toFixed(2)); return result; }, {});
}

function change(current: number, previous: number) { return previous === 0 ? null : Number((((current - previous) / previous) * 100).toFixed(2)); }

export async function GET(request: NextRequest) {
  const query = request.nextUrl.searchParams;
  const period = (query.get("period") || "last_30_days") as Period;
  if (!["last_7_days", "last_30_days", "last_90_days", "custom"].includes(period)) return NextResponse.json({ error: "Período inválido." }, { status: 400 });
  const from = validDate(query.get("from")); const to = validDate(query.get("to"));
  const selectedPlatform = String(query.get("platform") || "").trim();
  const authorization = await requireCorporatePermission("dashboard.view", selectedPlatform || undefined);
  if (!authorization) return NextResponse.json({ error: "Sem permissão para consultar séries históricas." }, { status: 403 });
  if (period === "custom" && (!from || !to || maputoStart(from) > maputoStart(to))) return NextResponse.json({ error: "Intervalo personalizado inválido." }, { status: 400 });
  const current = periodRange(period, from, to); const previous = previousRange(current);
  if (current.days > 366) return NextResponse.json({ error: "O intervalo máximo é de 366 dias." }, { status: 400 });
  const queryFrom = maputoStart(previous.from).toISOString(); const queryTo = isoEnd(current.to);
  const platformIds = selectedPlatform ? authorization.platformIds : authorization.platformIds;
  const platformFilter = platformIds.length ? `&platform_id=in.(${platformIds.join(",")})` : "";
  const platformSlug = selectedPlatform.toLowerCase().replace("deligo market", "taomoz");
  const relationSelect = selectedPlatform ? "platforms!inner(slug)," : "";
  const slugFilter = selectedPlatform ? `&platforms.slug=eq.${encodeURIComponent(platformSlug)}` : "";
  try {
    const [financialRows, operationalRows] = await Promise.all([
      hqRest(`platform_financial_events?select=${relationSelect}id,platform_id,source_record_id,gross_amount,platform_fee,payment_status,occurred_at,created_at&currency=eq.MZN&occurred_at=gte.${encodeURIComponent(queryFrom)}&occurred_at=lt.${encodeURIComponent(queryTo)}&limit=10000${platformFilter}${slugFilter}`) as Promise<Row[]>,
      hqRest(`platform_events?select=${relationSelect}id,platform_id,source_event_id,event_type,entity_type,occurred_at,created_at&occurred_at=gte.${encodeURIComponent(queryFrom)}&occurred_at=lt.${encodeURIComponent(queryTo)}&limit=10000${platformFilter}${slugFilter}`) as Promise<Row[]>,
    ]);
    const allFinancial = Array.isArray(financialRows) ? financialRows : []; const allOperational = Array.isArray(operationalRows) ? operationalRows : [];
    const currentSeries = aggregate(allFinancial, allOperational, current.from, current.to); const previousSeries = aggregate(allFinancial, allOperational, previous.from, previous.to);
    const currentTotals = totals(currentSeries); const previousTotals = totals(previousSeries);
    const comparison = Object.fromEntries(Object.keys(currentTotals).map(key => [key, { current: currentTotals[key], previous: previousTotals[key], changePercent: change(currentTotals[key], previousTotals[key]) }]));
    return NextResponse.json({ period, timezone: "Africa/Maputo", range: current, previousRange: previous, series: currentSeries, totals: currentTotals, comparison, sources: { financial: "hq.platform_financial_events · occurred_at · payment_status=confirmed · deduplicado por source_record_id/id", operational: "hq.platform_events · occurred_at · deduplicado por source_event_id/id" }, limitations: ["Utilizadores activos, subscrições activas e tempo médio não são calculados sem eventos históricos específicos verificáveis.", "A série não usa saldos actuais para reconstruir movimentos passados.", "O estado Reconciliado externamente da PaySuite não é inferido."], truncated: allFinancial.length >= 10000 || allOperational.length >= 10000 }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    console.error("Historical analytics query failed", error);
    return NextResponse.json({ error: "As fontes históricas estão indisponíveis." }, { status: 502 });
  }
}
