import { useMemo, useState } from "react";
import { AnalyticsDataTable } from "./AnalyticsDataTable";
import { ChartContainer } from "./ChartContainer";
import { DashboardFilters } from "./DashboardFilters";
import { DashboardHeader } from "./DashboardHeader";
import { DataFreshnessIndicator } from "./DataFreshnessIndicator";
import { EmptyState } from "./EmptyState";
import { KPIGrid } from "./KPIGrid";
import { TrendIndicator } from "./TrendIndicator";
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
type CommandCenter = { summary?: { operationsToday?: number; pendingKyc?: number; openSupport?: number; notificationWork?: number } };

const money = (value: number | null) => value == null ? null : Number(value.toFixed(2));
const numberValue = (value: unknown) => typeof value === "number" && Number.isFinite(value) ? value : null;

export function ExecutiveOverviewDashboard({ dashboard, commandCenter, onRefresh }: { dashboard: ExecutiveDashboardData | null; commandCenter: CommandCenter | null; onRefresh: () => void }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const breakdown = dashboard?.deligoFinance?.breakdown;
  const financePlatforms = Array.isArray(breakdown?.platforms) ? breakdown.platforms : [];
  const platformNames = (dashboard?.platforms || []).map((item) => item.name);
  const visibleFinancePlatforms = filters.platform ? financePlatforms.filter((item) => item.slug === filters.platform || item.name === filters.platform) : financePlatforms;
  const peopleCount = (dashboard?.modules?.platforms || []).reduce((sum, item) => sum + (Array.isArray(item.people) ? item.people.length : 0), 0);
  const connectedPlatforms = (dashboard?.platforms || []).filter((item) => item.connected || ["connected", "operational"].includes(String(item.platform_status))).length;
  const totalOperationsToday = numberValue(commandCenter?.summary?.operationsToday);
  const pendingAlerts = [commandCenter?.summary?.pendingKyc, commandCenter?.summary?.openSupport, commandCenter?.summary?.notificationWork].reduce<number | null>((sum, value) => {
    const numeric = numberValue(value);
    return numeric == null ? sum : (sum ?? 0) + numeric;
  }, null);
  const kpis: KPIResult[] = [
    { id: "corporate-revenue", label: "Receita corporativa", value: money(numberValue(breakdown?.central_revenue_confirmed)), unit: "MZN", sourceStatus: breakdown ? "fresh" : "unavailable", source: "hq.platform_financial_events · confirmada" },
    { id: "consolidated-gmv", label: "GMV consolidado", value: money(numberValue(breakdown?.gross_platform_volume_confirmed)), unit: "MZN", sourceStatus: breakdown ? "fresh" : "unavailable", source: "Resumo financeiro por plataforma" },
    { id: "active-users", label: "Utilizadores no directório", value: peopleCount || null, unit: "count", sourceStatus: peopleCount ? "fresh" : "unavailable", source: "Directório autorizado · não é métrica de actividade" },
    { id: "operations-today", label: "Operações hoje", value: totalOperationsToday, unit: "count", sourceStatus: totalOperationsToday == null ? "unavailable" : "fresh", source: "Centro de comando · hoje" },
    { id: "platforms-operational", label: "Plataformas operacionais", value: connectedPlatforms || null, unit: "count", sourceStatus: connectedPlatforms ? "fresh" : "unavailable", source: "Estado de integração HQ" },
    { id: "third-party-obligations", label: "Obrigações com utilizadores", value: money(numberValue(breakdown?.user_wallets_available)), unit: "MZN", sourceStatus: breakdown ? "fresh" : "unavailable", source: "Carteiras disponíveis · não é receita própria" },
    { id: "custody-available", label: "Custódia disponível", value: money(numberValue(breakdown?.total_funds_controlled_available)), unit: "MZN", sourceStatus: breakdown ? "fresh" : "unavailable", source: "Receita + carteiras, sem dupla contagem" },
    { id: "critical-alerts", label: "Alertas operacionais", value: pendingAlerts, unit: "count", sourceStatus: pendingAlerts == null ? "unavailable" : "fresh", source: "KYC, suporte e notificações" },
  ];
  const platformRows = useMemo(() => visibleFinancePlatforms.map((item) => ({ id: item.slug, platform: item.name, revenue: numberValue(item.central_revenue_confirmed), gmv: numberValue(item.gross_confirmed), wallets: numberValue(item.wallet_available), state: "Fonte interna" })), [visibleFinancePlatforms]);
  const insights = [
    connectedPlatforms > 0 ? `${connectedPlatforms} plataforma(s) com estado operacional confirmado.` : "Estado operacional das plataformas indisponível.",
    pendingAlerts == null ? "Alertas executivos sem fonte disponível." : `${pendingAlerts} alerta(s) operacional(is) requerem revisão.`,
    numberValue(breakdown?.central_revenue_confirmed) == null ? "Receita corporativa sem origem financeira disponível." : "Receita corporativa separada das carteiras de terceiros.",
  ];
  return <section className="analyticsDashboardShell executiveOverviewDashboard">
    <DashboardHeader title="Visão executiva" description="Indicadores reais autorizados da Central HQ, separados por titularidade e fonte." updatedAt={dashboard?.checkedAt ? new Date(dashboard.checkedAt).toLocaleString("pt-MZ") : undefined} actions={<button className="primaryAction" type="button" onClick={onRefresh}>Actualizar dados</button>} />
    <DashboardFilters value={filters} onChange={setFilters} platforms={platformNames} />
    <KPIGrid items={kpis} />
    <div className="analyticsExecutiveGrid">
      <ChartContainer title="Receita por plataforma" description="Valores confirmados pela fonte financeira; sem estimativas.">
        {platformRows.length ? <div className="analyticsBarList">{platformRows.map((row) => <div className="analyticsBarRow" key={row.id}><div><strong>{row.platform}</strong><small>{row.state}</small></div><span><i style={{ width: `${Math.min(100, Math.max(0, Number(row.revenue || 0)))}%` }} /><b>{row.revenue == null ? "Indisponível" : `${row.revenue.toLocaleString("pt-MZ", { minimumFractionDigits: 2 })} MT`}</b></span></div>)}</div> : <EmptyState title="Receita por plataforma indisponível" description="A fonte financeira não devolveu séries por plataforma para este contexto." />}
      </ChartContainer>
      <ChartContainer title="Evolução e comparação" description="Últimos 30 dias versus os 30 dias anteriores, no fuso Africa/Maputo.">
        <EmptyState title="Série temporal não disponível" description="A API atual fornece o resumo corrente, mas ainda não expõe uma série temporal verificável. Nenhum valor foi inventado." />
      </ChartContainer>
    </div>
    <ChartContainer title="Distribuição operacional por plataforma" description="Estado e volume devolvidos pelas fontes autorizadas.">
      <AnalyticsDataTable rows={(dashboard?.platforms || []).map((item) => ({ id: item.slug, plataforma: item.name, estado: item.platform_status || "Não confirmado", actualizacao: item.data_freshness || "Não indicada", ligada: item.connected ? "Sim" : "Não" }))} columns={[{ key: "plataforma", label: "Plataforma" }, { key: "estado", label: "Estado" }, { key: "ligada", label: "Ligação" }, { key: "actualizacao", label: "Actualização" }]} empty="Nenhuma plataforma devolvida pela fonte autorizada." />
    </ChartContainer>
    <div className="analyticsExecutiveGrid">
      <ChartContainer title="Insights determinísticos" description="Regras simples, sem IA e sem acesso de escrita."><div className="analyticsInsightList">{insights.map((insight) => <p key={insight}><span>•</span>{insight}</p>)}</div></ChartContainer>
      <ChartContainer title="Estado dos dados"><DataFreshnessIndicator status={dashboard?.checkedAt ? "fresh" : "unavailable"} updatedAt={dashboard?.checkedAt ? new Date(dashboard.checkedAt).toLocaleString("pt-MZ") : undefined} /><p className="analyticsDataNote">Filtro seleccionado: {filters.period}. Os indicadores sem fonte permanecem indisponíveis.</p><TrendIndicator changePercent={null} /></ChartContainer>
    </div>
  </section>;
}
