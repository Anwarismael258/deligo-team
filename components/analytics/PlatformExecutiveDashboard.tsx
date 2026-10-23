import { useEffect, useState } from "react";
import { ChartContainer } from "./ChartContainer";
import { DashboardFilters } from "./DashboardFilters";
import { EmptyState } from "./EmptyState";
import { KPIGrid } from "./KPIGrid";
import { AnalyticsBarChart, AnalyticsDonutChart, AnalyticsLineChart } from "./AnalyticsCharts";
import type { AnalyticsFilters, KPIResult } from "@/lib/analytics-contracts";

type Platform = { slug: string; name: string; connected?: boolean; platform_status?: string; data_freshness?: string; metrics?: Array<{ key: string; label: string; value: number }> };
type FinancePlatform = { slug: string; name: string; gross_confirmed?: number; central_revenue_confirmed?: number; wallet_available?: number; wallet_pending?: number };
type PlatformDashboardData = { platforms?: Platform[]; deligoFinance?: { breakdown?: { platforms?: FinancePlatform[] } } };
type History = { range?: { from: string; to: string }; series?: Array<{ date: string; revenue: number; gmv: number; operations: number }>; comparison?: { revenue?: { current: number; previous: number; changePercent: number | null }; operations?: { current: number; previous: number; changePercent: number | null } }; limitations?: string[] };
const metric = (platform: Platform | undefined, labels: string[]) => platform?.metrics?.find((item) => labels.some((label) => item.label.toLowerCase().includes(label)))?.value ?? null;
const finance = (rows: FinancePlatform[], slug: string) => rows.find((item) => item.slug === slug);
const displaySlug = (value: string) => value === "DeliGo Market" ? "taomoz" : value.toLowerCase();
const money = (value: number | null | undefined) => value == null ? null : Number(value.toFixed(2));

export function PlatformExecutiveDashboard({ dashboard, selectedPlatform }: { dashboard: PlatformDashboardData | null; selectedPlatform: string }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [history, setHistory] = useState<History | null>(null);
  const [historyError, setHistoryError] = useState("");
  const allPlatforms = dashboard?.platforms || [];
  const selected = selectedPlatform === "Todas as plataformas" ? null : allPlatforms.find((item) => item.name === selectedPlatform);
  const financeRows = dashboard?.deligoFinance?.breakdown?.platforms || [];
  const selectedFinance = selected ? finance(financeRows, displaySlug(selected.name)) : null;
  const makeKpis = (item: Platform | null, financeItem: FinancePlatform | null | undefined): KPIResult[] => [
    { id: "platform-operations", label: item?.name === "SARCA" ? "Viagens" : item?.name === "Mestre24" ? "Pedidos de serviços" : "Operações", value: metric(item || undefined, ["pedido", "operação", "viagem", "serviço"]), unit: "count", sourceStatus: item ? "fresh" : "unavailable", source: "Fonte operacional da plataforma" },
    { id: "platform-revenue", label: "Receita própria", value: money(financeItem?.central_revenue_confirmed), unit: "MZN", sourceStatus: financeItem ? "fresh" : "unavailable", source: "Eventos financeiros confirmados" },
    { id: "platform-gmv", label: "GMV confirmado", value: money(financeItem?.gross_confirmed), unit: "MZN", sourceStatus: financeItem ? "fresh" : "unavailable", source: "Eventos financeiros confirmados" },
    { id: "platform-wallets", label: "Carteiras de terceiros", value: money(financeItem?.wallet_available), unit: "MZN", sourceStatus: financeItem ? "fresh" : "unavailable", source: "Carteiras disponíveis · não é receita" },
  ];
  const rows = allPlatforms.map((item) => { const source = finance(financeRows, displaySlug(item.name)); return { id: item.slug, plataforma: item.name, estado: item.platform_status || "Não confirmado", receita: source?.central_revenue_confirmed == null ? "Indisponível" : `${source.central_revenue_confirmed.toLocaleString("pt-MZ", { minimumFractionDigits: 2 })} MT`, gmv: source?.gross_confirmed == null ? "Indisponível" : `${source.gross_confirmed.toLocaleString("pt-MZ", { minimumFractionDigits: 2 })} MT`, dados: item.data_freshness || "Não indicada" }; });
  const revenueChart = allPlatforms.map(item => ({ label: item.name, value: finance(financeRows, displaySlug(item.name))?.central_revenue_confirmed ?? 0 })).filter(item => item.value > 0);
  const operationsChart = allPlatforms.map(item => ({ label: item.name, value: metric(item, ["pedido", "operação", "viagem", "serviço"]) ?? 0 })).filter(item => item.value > 0);
  const statusCounts = Object.entries(allPlatforms.reduce<Record<string, number>>((result, item) => { const status = item.platform_status || "Desconhecido"; result[status] = (result[status] || 0) + 1; return result; }, {})).map(([label, value]) => ({ label, value }));
  const selectedMetrics = (selected?.metrics || []).map(item => ({ label: item.label, value: item.value })).filter(item => Number.isFinite(item.value));
  useEffect(() => {
    const params = new URLSearchParams({ period: filters.period });
    if (filters.from) params.set("from", filters.from);
    if (filters.to) params.set("to", filters.to);
    if (selected) params.set("platform", selected.name);
    let cancelled = false;
    fetch(`/api/analytics/history?${params.toString()}`, { cache: "no-store" })
      .then(async response => { const body = await response.json(); if (!response.ok) throw new Error(body.error || "Série histórica indisponível."); return body as History; })
      .then(body => { if (!cancelled) { setHistory(body); setHistoryError(""); } })
      .catch(error => { if (!cancelled) { setHistory(null); setHistoryError(error instanceof Error ? error.message : "Série histórica indisponível."); } });
    return () => { cancelled = true; };
  }, [selectedPlatform, filters.period, filters.from, filters.to]);
  return <section className="platformAnalyticsPanel">
    <div className="platformAnalyticsHead"><div><span>FASE 3 · PLATAFORMAS</span><h2>{selected ? `Dashboard · ${selected.name}` : "Comparação multiplataforma"}</h2><p>{selected ? "Indicadores reais autorizados desta plataforma." : "Resumo comparável das plataformas devolvidas pelo backend."}</p></div></div>
    <DashboardFilters value={filters} onChange={setFilters} platforms={allPlatforms.map(item => item.name)} />
    {selected ? <><KPIGrid items={makeKpis(selected, selectedFinance)} /><div className="analyticsExecutiveGrid"><ChartContainer title="Operações" description="Resumo operacional autorizado."><AnalyticsBarChart data={selectedMetrics} label="Operações" /></ChartContainer><ChartContainer title="Dados financeiros" description="Receita própria separada das carteiras.">{selectedFinance ? <div className="platformFinanceFacts"><p><span>Receita própria</span><strong>{money(selectedFinance.central_revenue_confirmed)?.toLocaleString("pt-MZ", { minimumFractionDigits: 2 })} MT</strong></p><p><span>GMV</span><strong>{money(selectedFinance.gross_confirmed)?.toLocaleString("pt-MZ", { minimumFractionDigits: 2 })} MT</strong></p><p><span>Carteiras</span><strong>{money(selectedFinance.wallet_available)?.toLocaleString("pt-MZ", { minimumFractionDigits: 2 })} MT</strong></p></div> : <EmptyState title="Dados financeiros indisponíveis" description="Esta fonte não devolveu receita ou carteiras reconciliáveis." />}</ChartContainer></div></> : <div className="analyticsExecutiveGrid"><ChartContainer title="Receita por plataforma" description="Receita confirmada pela fonte financeira."><AnalyticsBarChart data={revenueChart} label="Receita" /></ChartContainer><ChartContainer title="Operações por plataforma" description="Pedidos, viagens e serviços devolvidos pelas fontes."><AnalyticsBarChart data={operationsChart} label="Operações" /></ChartContainer><ChartContainer title="Estado das plataformas"><AnalyticsDonutChart data={statusCounts} /></ChartContainer></div>}
    <ChartContainer title="Evolução no período" description="Eventos históricos confirmados; não usa saldos atuais para reconstruir o passado.">{historyError ? <EmptyState title="Série histórica indisponível" description={historyError} /> : <AnalyticsLineChart data={(history?.series || []).map(item => ({ date: item.date, value: item.revenue, secondary: item.operations }))} label="Receita confirmada" secondaryLabel="Operações" />}</ChartContainer>
    <div className="analyticsDataNote">{history?.limitations?.join(" ") || "Fonte histórica atualizada no período selecionado."}</div>
  </section>;
}
