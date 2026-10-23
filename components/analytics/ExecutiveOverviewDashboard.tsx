import { useEffect, useState } from "react";
import { ChartContainer } from "./ChartContainer";
import { DashboardFilters } from "./DashboardFilters";
import { DashboardHeader } from "./DashboardHeader";
import { EmptyState } from "./EmptyState";
import { KPIGrid } from "./KPIGrid";
import { TrendIndicator } from "./TrendIndicator";
import { AnalyticsBarChart, AnalyticsDonutChart, AnalyticsLineChart } from "./AnalyticsCharts";
import type { AnalyticsFilters, KPIResult } from "@/lib/analytics-contracts";

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
type CommandCenter = { checkedAt?: string; summary?: { operationsToday?: number; pendingKyc?: number; openSupport?: number; notificationWork?: number }; pendingActions?: PendingAction[]; liveFeed?: Array<{ id: string | number; event_type?: string; entity_type?: string; occurred_at?: string; platforms?: { name?: string; platform_code?: string } }> };
type HistoryPoint = { date: string; revenue: number; gmv: number; commissions: number; operations: number; cancellations: number };
type HistoryData = { series: HistoryPoint[]; totals: Record<string, number>; comparison: Record<string, { current: number; previous: number; changePercent: number | null }>; range?: { from: string; to: string }; limitations?: string[] };

const money = (value: number | null) => value == null ? null : Number(value.toFixed(2));
const numberValue = (value: unknown) => typeof value === "number" && Number.isFinite(value) ? value : null;

export function ExecutiveOverviewDashboard({ dashboard, commandCenter, onRefresh }: { dashboard: ExecutiveDashboardData | null; commandCenter: CommandCenter | null; onRefresh: () => void }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [history, setHistory] = useState<HistoryData | null>(null);
  const [historyError, setHistoryError] = useState("");
  const breakdown = dashboard?.deligoFinance?.breakdown;
  const platformNames = (dashboard?.platforms || []).map((item) => item.name);
  const peopleCount = (dashboard?.modules?.platforms || []).reduce((sum, item) => sum + (Array.isArray(item.people) ? item.people.length : 0), 0);
  const connectedPlatforms = (dashboard?.platforms || []).filter((item) => item.connected || ["connected", "operational"].includes(String(item.platform_status))).length;
  useEffect(() => {
    const params = new URLSearchParams({ period: filters.period });
    if (filters.from) params.set("from", filters.from);
    if (filters.to) params.set("to", filters.to);
    if (filters.platform) params.set("platform", filters.platform);
    let cancelled = false;
    fetch(`/api/analytics/history?${params.toString()}`, { cache: "no-store" }).then(async response => { const body = await response.json(); if (!response.ok) throw new Error(body.error || "Não foi possível carregar a série histórica."); return body as HistoryData; }).then(data => { if (!cancelled) { setHistory(data); setHistoryError(""); } }).catch(error => { if (!cancelled) { setHistory(null); setHistoryError(error instanceof Error ? error.message : "Não foi possível carregar a série histórica."); } });
    return () => { cancelled = true; };
  }, [filters.period, filters.from, filters.to, filters.platform]);
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
  return <section className="analyticsDashboardShell executiveOverviewDashboard">
    <DashboardHeader title="Visão executiva" description="Indicadores reais autorizados da Central HQ, separados por titularidade e fonte." updatedAt={dashboard?.checkedAt ? new Date(dashboard.checkedAt).toLocaleString("pt-MZ") : undefined} actions={<button className="primaryAction" type="button" onClick={onRefresh}>Actualizar dados</button>} />
    <DashboardFilters value={filters} onChange={setFilters} platforms={platformNames} />
    <KPIGrid items={kpis} />
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
  </section>;
}
