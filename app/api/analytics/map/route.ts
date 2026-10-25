import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRest } from "@/lib/hq-server";

export const dynamic = "force-dynamic";
type Period = "today" | "last_7_days" | "last_30_days" | "last_90_days" | "this_year";
type Row = Record<string, unknown>;
const dayMs = 86_400_000;
const maputoDate = (value: Date) => new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Maputo", year: "numeric", month: "2-digit", day: "2-digit" }).format(value);
const atMaputoStart = (value: string) => new Date(`${value}T00:00:00+02:00`);
const rangeFor = (period: Period, end = new Date()) => { const to = maputoDate(end); if (period === "this_year") { const from = `${to.slice(0, 4)}-01-01`; return { from, to, days: Math.max(1, Math.round((atMaputoStart(to).getTime() - atMaputoStart(from).getTime()) / dayMs) + 1) }; } const days = period === "today" ? 1 : period === "last_7_days" ? 7 : period === "last_90_days" ? 90 : 30; const from = maputoDate(new Date(atMaputoStart(to).getTime() - (days - 1) * dayMs)); return { from, to, days }; };
const previousRange = (range: { from: string; days: number }) => { const to = new Date(atMaputoStart(range.from).getTime() - dayMs); const from = new Date(to.getTime() - (range.days - 1) * dayMs); return { from: maputoDate(from), to: maputoDate(to), days: range.days }; };
const isoEnd = (date: string) => new Date(atMaputoStart(date).getTime() + dayMs).toISOString();
const countEvents = (rows: Row[]) => rows.reduce((total, row) => total + 1, 0);
const change = (current: number, previous: number) => previous === 0 ? null : Number((((current - previous) / previous) * 100).toFixed(2));

function aggregate(rows: Row[], range: { from: string; to: string }) {
  const points = new Map<string, { date: string; events: number; created: number; statusChanges: number; cancellations: number; deliveriesCompleted: number; ridesCompleted: number }>();
  for (let cursor = atMaputoStart(range.from); cursor <= atMaputoStart(range.to); cursor = new Date(cursor.getTime() + dayMs)) { const date = maputoDate(cursor); points.set(date, { date, events: 0, created: 0, statusChanges: 0, cancellations: 0, deliveriesCompleted: 0, ridesCompleted: 0 }); }
  const seen = new Set<string>();
  rows.forEach(row => { const key = String(row.id || `${row.resource_type}:${row.resource_id}:${row.event_type}:${row.occurred_at}`); if (seen.has(key)) return; seen.add(key); const date = maputoDate(new Date(String(row.occurred_at || row.created_at || ""))); const point = points.get(date); if (!point) return; const event = String(row.event_type || "").toLowerCase(); const platform = String((row.platforms as Row | undefined)?.slug || "").toLowerCase(); point.events += 1; if (event === "created") point.created += 1; if (event.includes("status")) point.statusChanges += 1; if (/(cancel|reject|fail)/i.test(event)) point.cancellations += 1; if (platform === "deligo" && /^(delivery|order)_?(auto_|override_|otp_)?completed$/.test(event)) point.deliveriesCompleted += 1; if (platform === "sarca" && event === "ride_completed") point.ridesCompleted += 1; });
  return [...points.values()];
}

export async function GET(request: NextRequest) {
  if (!await corporateActor()) return NextResponse.json({ error: "Sessão corporativa necessária." }, { status: 401 });
  const requested = request.nextUrl.searchParams.get("period") || "last_30_days";
  if (!["today", "last_7_days", "last_30_days", "last_90_days", "this_year"].includes(requested)) return NextResponse.json({ error: "Período inválido." }, { status: 400 });
  const period = requested as Period; const current = rangeFor(period); const previous = previousRange(current); const from = atMaputoStart(previous.from).toISOString(); const to = isoEnd(current.to);
  try {
    const rows = await hqRest(`platform_events?select=id,platform_id,resource_type:entity_type,resource_id:entity_id,event_type,occurred_at,created_at,platforms!inner(slug)&occurred_at=gte.${encodeURIComponent(from)}&occurred_at=lt.${encodeURIComponent(to)}&order=occurred_at.asc&limit=10000`) as Row[];
    const all = Array.isArray(rows) ? rows : []; const currentRows = all.filter(row => { const date = Date.parse(String(row.occurred_at || row.created_at || "")); return date >= atMaputoStart(current.from).getTime() && date < new Date(to).getTime(); }); const previousRows = all.filter(row => { const date = Date.parse(String(row.occurred_at || row.created_at || "")); return date >= atMaputoStart(previous.from).getTime() && date < atMaputoStart(current.from).getTime(); });
    const currentSeries = aggregate(currentRows, current); const previousSeries = aggregate(previousRows, previous); const currentTotal = countEvents(currentRows); const previousTotal = countEvents(previousRows);
    const currentDeliveries = currentSeries.reduce((sum, row) => sum + row.deliveriesCompleted, 0); const previousDeliveries = previousSeries.reduce((sum, row) => sum + row.deliveriesCompleted, 0); const currentRides = currentSeries.reduce((sum, row) => sum + row.ridesCompleted, 0); const previousRides = previousSeries.reduce((sum, row) => sum + row.ridesCompleted, 0);
    return NextResponse.json({ timezone: "Africa/Maputo", range: current, previousRange: previous, series: currentSeries, totals: { events: currentTotal, deliveriesCompleted: currentDeliveries, ridesCompleted: currentRides }, comparison: { events: { current: currentTotal, previous: previousTotal, changePercent: change(currentTotal, previousTotal) }, deliveriesCompleted: { current: currentDeliveries, previous: previousDeliveries, changePercent: change(currentDeliveries, previousDeliveries) }, ridesCompleted: { current: currentRides, previous: previousRides, changePercent: change(currentRides, previousRides) } }, sources: { events: "hq.platform_events · occurred_at · deduplicado por id e origem", deliveries: "hq.platform_events · event_type de conclusão DeliGo", rides: "hq.platform_events · event_type=ride_completed" }, limitations: ["Esta série mede eventos operacionais auditáveis e não reconstrói percursos GPS nem posições históricas.", "Distância, velocidade, duração média e produtividade individual permanecem indisponíveis porque a fonte consolidada não contém telemetria suficiente.", "Dias sem eventos são apresentados como zero para manter o eixo temporal; não são inferidas operações.", "A fonte não é uma confirmação externa da PaySuite."] }, { headers: { "Cache-Control": "private, no-store" } });
  } catch { return NextResponse.json({ error: "O histórico operacional está indisponível." }, { status: 502 }); }
}
