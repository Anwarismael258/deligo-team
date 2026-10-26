import { useEffect, useRef, useState } from "react";
import { ChartContainer } from "./ChartContainer";
import { DashboardFilters } from "./DashboardFilters";
import { DashboardHeader } from "./DashboardHeader";
import { EmptyState } from "./EmptyState";
import { KPIGrid } from "./KPIGrid";
import { TrendIndicator } from "./TrendIndicator";
import { AnalyticsBarChart, AnalyticsDonutChart, AnalyticsLineChart } from "./AnalyticsCharts";
import type { AnalyticsFilters, KPIResult } from "@/lib/analytics-contracts";
import { CentralEngineMonitor, type MonitorState } from "./CentralEngineMonitor";
import { CentralPresentationControls } from "./CentralPresentationControls";

type Platform = { slug: string; name: string; connected?: boolean; platform_status?: string; data_freshness?: string; metrics?: Array<{ key: string; label: string; value: number }> };
type FinancePlatform = { slug: string; name: string; gross_confirmed?: number; central_revenue_confirmed?: number; wallet_available?: number; wallet_pending?: number };
type ExecutiveDashboardData = {
  checkedAt?: string;
  platforms?: Platform[];
  operations?: { supportCases?: number; campaigns?: number; fieldVisits?: number; auditEvents?: number };
  modules?: { platforms?: Array<{ slug: string; name: string; people?: unknown[] }> };
  deligoFinance?: { breakdown?: { central_revenue_confirmed?: number; gross_platform_volume_confirmed?: number; user_wallets_available?: number; total_funds_controlled_available?: number; platforms?: FinancePlatform[] } };
};
type PendingAction = { id: string; category?: string; priority?: string; responsible?: string; dueAt?: string | null; waitingSince?: string | null; origin?: string; status?: string; nextAction?: string; href?: string };
type CommandCenterEvent = { id: string | number; event_type?: string; entity_type?: string; occurred_at?: string; platforms?: { name?: string; platform_code?: string } };
type CommandCenter = { checkedAt?: string; summary?: { operationsToday?: number; pendingKyc?: number; openSupport?: number; notificationWork?: number }; pendingActions?: PendingAction[]; liveFeed?: CommandCenterEvent[] };
type HistoryPoint = { date: string; revenue: number; gmv: number; commissions: number; operations: number; cancellations: number };
type HistoryData = { series: HistoryPoint[]; totals: Record<string, number>; comparison: Record<string, { current: number; previous: number; changePercent: number | null }>; range?: { from: string; to: string }; limitations?: string[] };

const money = (value: number | null) => value == null ? null : Number(value.toFixed(2));
const numberValue = (value: unknown) => typeof value === "number" && Number.isFinite(value) ? value : null;
const overviewVisualStyles = `.executiveOverviewDashboard .analyticsKpiCard{background:linear-gradient(145deg,#10253b,#0b1727);border-color:#315174;color:#eaf2ff;box-shadow:0 10px 24px #02071155}.executiveOverviewDashboard .analyticsKpiCard>span{color:#9db6ce}.executiveOverviewDashboard .analyticsKpiCard>strong{color:#f5f9ff}.executiveOverviewDashboard .analyticsKpiCard>small{color:#86a1bd}.executiveOverviewDashboard .analyticsChartContainer{background:linear-gradient(145deg,#10253b,#0b1727);border-color:#315174;color:#eaf2ff}.executiveOverviewDashboard .analyticsChartHeading h3{color:#f5f9ff}.executiveOverviewDashboard .analyticsChartHeading p{color:#9db6ce}.executiveOverviewDashboard .overviewConsolidatedLabel{margin:0;padding:12px 14px;border:1px solid #315174;border-radius:10px;background:#0b1b2d;color:#9db6ce;font-size:11px;text-align:right;box-shadow:0 8px 20px #02071144}`;

export function ExecutiveOverviewDashboard({ dashboard, commandCenter, onRefresh, refreshKey = 0, realtimeState = "unknown", realtimeCheckedAt }: { dashboard: ExecutiveDashboardData | null; commandCenter: CommandCenter | null; onRefresh: () => void; refreshKey?: number; realtimeState?: MonitorState; realtimeCheckedAt?: string }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [history, setHistory] = useState<HistoryData | null>(null);
  const [historyError, setHistoryError] = useState("");
  const breakdown = dashboard?.deligoFinance?.breakdown;
  const platformNames = (dashboard?.platforms || []).map((item) => item.name);
  const peopleCount = (dashboard?.modules?.platforms || []).reduce((sum, item) => sum + (Array.isArray(item.people) ? item.people.length : 0), 0);
  const connectedPlatforms = (dashboard?.platforms || []).filter((item) => item.connected || ["connected", "operational"].includes(String(item.platform_status))).length;
  const [eventPulse, setEventPulse] = useState(false);
  const previousEventRef = useRef<string | null>(null);
  const liveFeed = (commandCenter?.liveFeed || []).filter((event, index, events) => events.findIndex(candidate => String(candidate.id) === String(event.id)) === index).slice(0, 3);
  const latestEventKey = liveFeed[0] ? String(liveFeed[0].id) : "";
  useEffect(() => {
    const previous = previousEventRef.current;
    previousEventRef.current = latestEventKey || previousEventRef.current;
    if (!previous || !latestEventKey || previous === latestEventKey || document.visibilityState !== "visible") return;
    setEventPulse(true);
    const timer = window.setTimeout(() => setEventPulse(false), 1100);
    return () => window.clearTimeout(timer);
  }, [latestEventKey, refreshKey]);
  useEffect(() => {
    const params = new URLSearchParams({ period: filters.period });
    if (filters.from) params.set("from", filters.from);
    if (filters.to) params.set("to", filters.to);
    if (filters.platform) params.set("platform", filters.platform);
    let cancelled = false;
    fetch(`/api/analytics/history?${params.toString()}`, { cache: "no-store" }).then(async response => { const body = await response.json(); if (!response.ok) throw new Error(body.error || "Não foi possível carregar a série histórica."); return body as HistoryData; }).then(data => { if (!cancelled) { setHistory(data); setHistoryError(""); } }).catch(error => { if (!cancelled) { setHistory(null); setHistoryError(error instanceof Error ? error.message : "Não foi possível carregar a série histórica."); } });
    return () => { cancelled = true; };
  }, [filters.period, filters.from, filters.to, filters.platform, refreshKey]);
  const pendingAlerts = [commandCenter?.summary?.pendingKyc, commandCenter?.summary?.openSupport, commandCenter?.summary?.notificationWork].reduce<number | null>((sum, value) => {
    const numeric = numberValue(value);
    return numeric == null ? sum : (sum ?? 0) + numeric;
  }, null);
  const kpis: KPIResult[] = [
    { id: "corporate-revenue", label: "Receita no período", value: history ? money(numberValue(history.totals.revenue)) : null, unit: "MZN", previousValue: history?.comparison.revenue?.previous, changePercent: history?.comparison.revenue?.changePercent, sourceStatus: history ? "fresh" : "unavailable", source: "hq.platform_financial_events · occurred_at · confirmada" },
    { id: "consolidated-gmv", label: "GMV no período", value: history ? money(numberValue(history.totals.gmv)) : null, unit: "MZN", previousValue: history?.comparison.gmv?.previous, changePercent: history?.comparison.gmv?.changePercent, sourceStatus: history ? "fresh" : "unavailable", source: "hq.platform_financial_events · occurred_at" },
    { id: "active-users", label: "Utilizadores no directório", value: peopleCount || null, unit: "count", sourceStatus: peopleCount ? "fresh" : "unavailable", source: "Directório autorizado · não é métrica de actividade" },
    { id: "operations-period", label: "Operações no período", value: history ? money(numberValue(history.totals.operations)) : null, unit: "count", previousValue: history?.comparison.operations?.previous, changePercent: history?.comparison.operations?.changePercent, sourceStatus: history ? "fresh" : "unavailable", source: "hq.platform_events · occurred_at" },
    { id: "platforms-operational", label: "Plataformas operacionais", value: connectedPlatforms || null, unit: "count", sourceStatus: connectedPlatforms ? "fresh" : "unavailable", source: "Estado de integração HQ" },
    { id: "third-party-obligations", label: "Obrigações com utilizadores", value: money(numberValue(breakdown?.user_wallets_available)), unit: "MZN", sourceStatus: breakdown ? "fresh" : "unavailable", source: "Carteiras disponíveis · não é receita própria" },
    { id: "custody-available", label: "Custódia disponível", value: money(numberValue(breakdown?.total_funds_controlled_available)), unit: "MZN", sourceStatus: breakdown ? "fresh" : "unavailable", source: "Receita + carteiras, sem dupla contagem" },
    { id: "critical-alerts", label: "Alertas operacionais", value: pendingAlerts, unit: "count", sourceStatus: pendingAlerts == null ? "unavailable" : "fresh", source: "KYC, suporte e notificações" },
  ];
  const platformChart = (dashboard?.platforms || []).map((item) => ({ label: item.name, value: item.connected || ["connected", "operational"].includes(String(item.platform_status)) ? 1 : 0 }));
  const custodyChart = [
    { label: "Receita", value: numberValue(breakdown?.central_revenue_confirmed) || 0 },
    { label: "Carteiras", value: numberValue(breakdown?.user_wallets_available) || 0 },
  ].filter(item => item.value > 0);
  const revenueByPlatform = (breakdown?.platforms || []).map(item => ({ label: item.name, value: numberValue(item.central_revenue_confirmed) || 0 })).filter(item => item.value > 0);
  const eventLabel = (event: CommandCenterEvent) => {
    const value = String(event.event_type || event.entity_type || "Evento recebido").replaceAll("_", " ");
    return value.charAt(0).toUpperCase() + value.slice(1);
  };
  const eventPlatform = (event: CommandCenterEvent) => event.platforms?.name || event.platforms?.platform_code || "Central";
  const eventHref = (event: CommandCenterEvent) => {
    const source = `${event.event_type || ""} ${event.entity_type || ""}`.toLowerCase();
    if (source.includes("support") || source.includes("message") || source.includes("ticket")) return "/apoio-cliente";
    if (source.includes("kyc") || source.includes("field")) return "/field";
    if (source.includes("finance") || source.includes("payment") || source.includes("wallet")) return "/financas";
    if (source.includes("task") || source.includes("project")) return "/projectos-tarefas";
    if (source.includes("order") || source.includes("delivery") || source.includes("ride") || source.includes("trip") || source.includes("service")) return "/mapa-operacional";
    return "/notificacoes";
  };
  return <section className="analyticsDashboardShell executiveOverviewDashboard">
    <style>{overviewVisualStyles}</style>
    <DashboardHeader title="Visão executiva" description="Indicadores reais autorizados da Central HQ, separados por titularidade e fonte." updatedAt={dashboard?.checkedAt ? new Date(dashboard.checkedAt).toLocaleString("pt-MZ") : undefined} actions={<><CentralPresentationControls /><button className="primaryAction" type="button" onClick={onRefresh}>Actualizar dados</button></>} />
    <CentralEngineMonitor checkedAt={dashboard?.checkedAt || commandCenter?.checkedAt} platforms={dashboard?.platforms} realtimeState={realtimeState} realtimeCheckedAt={realtimeCheckedAt} lastEvent={commandCenter?.liveFeed?.[0]} />
    <section className={`centralNowPanel ${eventPulse ? "isEventPulse" : ""}`} aria-labelledby="central-now-title">
      <div className="centralNowHeading"><div><span className="centralNowEyebrow">FEED AUTORIZADO</span><h2 id="central-now-title">A acontecer agora</h2><p>Os últimos eventos recebidos pela Central.</p></div><span className="centralNowStatus">{liveFeed.length ? `${liveFeed.length} recentes` : "Sem eventos"}</span></div>
      {liveFeed.length ? <div className="centralNowList">{liveFeed.map(event => <button className="centralNowItem" type="button" key={String(event.id)} onClick={() => window.location.assign(eventHref(event))}><span className="centralNowDot" aria-hidden="true" /><span className="centralNowBody"><strong>{eventLabel(event)}</strong><small>{eventPlatform(event)} · {event.occurred_at ? new Date(event.occurred_at).toLocaleString("pt-MZ") : "hora não indicada"}</small></span><span className="centralNowArrow" aria-hidden="true">→</span></button>)}</div> : <div className="centralNowEmpty">Nenhum evento real autorizado disponível neste momento.</div>}
    </section>
    <DashboardFilters value={filters} onChange={setFilters} platforms={platformNames} />
    <div className="analyticsExecutiveGrid">
      <ChartContainer title="Evolução das receitas" description="Valores confirmados pela fonte financeira; sem estimativas.">
        {historyError ? <EmptyState title="Série histórica indisponível" description={historyError} /> : <AnalyticsLineChart data={(history?.series || []).map(row => ({ date: row.date, value: row.revenue }))} label="Receita confirmada" />}
      </ChartContainer>
      <ChartContainer title="Receita por plataforma">
        <AnalyticsDonutChart data={revenueByPlatform} />
        {history?.comparison?.revenue && <div className="analyticsComparison analyticsComparisonCompact"><span>Variação vs. período anterior</span><TrendIndicator changePercent={history.comparison.revenue.changePercent} /></div>}
      </ChartContainer>
    </div>
    <div className="analyticsExecutiveGrid executiveVisualGrid">
      <ChartContainer title="Plataformas" description="Estado confirmado pelas fontes autorizadas.">
        <AnalyticsBarChart data={platformChart} label="Operacionais" />
      </ChartContainer>
      <ChartContainer title="Composição da custódia" description="Receita própria separada das carteiras de terceiros.">
        {custodyChart.length ? <AnalyticsDonutChart data={custodyChart} /> : <EmptyState title="Custódia indisponível" description="A fonte autorizada não devolveu valores verificáveis." />}
      </ChartContainer>
    </div>
    <KPIGrid items={kpis} />
  </section>;
}
