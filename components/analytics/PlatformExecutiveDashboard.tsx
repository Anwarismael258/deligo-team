import { AnalyticsDataTable } from "./AnalyticsDataTable";
import { ChartContainer } from "./ChartContainer";
import { EmptyState } from "./EmptyState";
import { KPIGrid } from "./KPIGrid";
import type { KPIResult } from "@/lib/analytics-contracts";

type Platform = { slug: string; name: string; connected?: boolean; platform_status?: string; data_freshness?: string; metrics?: Array<{ key: string; label: string; value: number }> };
type FinancePlatform = { slug: string; name: string; gross_confirmed?: number; central_revenue_confirmed?: number; wallet_available?: number; wallet_pending?: number };
type PlatformDashboardData = { platforms?: Platform[]; deligoFinance?: { breakdown?: { platforms?: FinancePlatform[] } } };
const metric = (platform: Platform | undefined, labels: string[]) => platform?.metrics?.find((item) => labels.some((label) => item.label.toLowerCase().includes(label)))?.value ?? null;
const finance = (rows: FinancePlatform[], slug: string) => rows.find((item) => item.slug === slug);
const displaySlug = (value: string) => value === "DeliGo Market" ? "taomoz" : value.toLowerCase();
const money = (value: number | null | undefined) => value == null ? null : Number(value.toFixed(2));

export function PlatformExecutiveDashboard({ dashboard, selectedPlatform }: { dashboard: PlatformDashboardData | null; selectedPlatform: string }) {
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
  return <section className="platformAnalyticsPanel">
    <div className="platformAnalyticsHead"><div><span>FASE 3 · PLATAFORMAS</span><h2>{selected ? `Dashboard · ${selected.name}` : "Comparação multiplataforma"}</h2><p>{selected ? "Indicadores reais autorizados desta plataforma." : "Resumo comparável das plataformas devolvidas pelo backend."}</p></div></div>
    {selected ? <><KPIGrid items={makeKpis(selected, selectedFinance)} /><div className="analyticsExecutiveGrid"><ChartContainer title="Operações disponíveis" description="A fonte operacional atual devolve apenas o resumo disponível."><AnalyticsDataTable rows={selected.metrics || []} columns={[{ key: "label", label: "Indicador" }, { key: "value", label: "Valor" }]} empty="Nenhum indicador operacional devolvido." /></ChartContainer><ChartContainer title="Dados financeiros" description="Separados de carteiras de terceiros.">{selectedFinance ? <div className="platformFinanceFacts"><p><span>Receita própria</span><strong>{money(selectedFinance.central_revenue_confirmed)?.toLocaleString("pt-MZ", { minimumFractionDigits: 2 })} MT</strong></p><p><span>GMV</span><strong>{money(selectedFinance.gross_confirmed)?.toLocaleString("pt-MZ", { minimumFractionDigits: 2 })} MT</strong></p><p><span>Carteiras</span><strong>{money(selectedFinance.wallet_available)?.toLocaleString("pt-MZ", { minimumFractionDigits: 2 })} MT</strong></p></div> : <EmptyState title="Dados financeiros indisponíveis" description="Esta fonte não devolveu receita ou carteiras reconciliáveis." />}</ChartContainer></div></> : <ChartContainer title="Estado por plataforma" description="Nenhum valor é preenchido quando a fonte não o fornece."><AnalyticsDataTable rows={rows} columns={[{ key: "plataforma", label: "Plataforma" }, { key: "estado", label: "Estado" }, { key: "receita", label: "Receita" }, { key: "gmv", label: "GMV" }, { key: "dados", label: "Actualização" }]} empty="Nenhuma plataforma foi devolvida pelo backend autorizado." /></ChartContainer>}
  </section>;
}
