"use client";

import { KPIGrid } from "./KPIGrid";
import { DataFreshnessIndicator } from "./DataFreshnessIndicator";
import { AnalyticsBarChart } from "./AnalyticsCharts";
import { ChartContainer } from "./ChartContainer";
import type { KPIResult } from "@/lib/analytics-contracts";

type FinanceSource = { key?: string; label?: string; value?: number; source?: string; status?: string };

export function FinanceReadOnlyDashboard({ reconciliation }: { reconciliation: Record<string, unknown> | null }) {
  if (!reconciliation) return null;
  const sources = (Array.isArray(reconciliation.sources) ? reconciliation.sources : []) as FinanceSource[];
  const kpis: KPIResult[] = sources.filter(source => source.key !== "finance.legacy_unclassified").slice(0, 3).map(source => ({ id: String(source.key || "finance.metric"), label: String(source.label || "Métrica financeira"), value: typeof source.value === "number" ? source.value : null, unit: "MZN", sourceStatus: source.status === "confirmed" ? "fresh" : source.status === "unavailable" ? "unavailable" : "stale", source: source.source, permission: "finance.view" }));
  const paysuite = (reconciliation.paysuite || {}) as Record<string, unknown>;
  const isPaysuiteReconciled = paysuite.state === "CONFIRMED";
  const platformRows = Array.isArray(reconciliation.platformReconciliation) ? reconciliation.platformReconciliation as Array<Record<string, unknown>> : [];
  const qualityChecks = Array.isArray(reconciliation.qualityChecks) ? reconciliation.qualityChecks as Array<Record<string, unknown>> : [];
  const confirmedSourceChart = sources.filter(source => source.status === "confirmed" && typeof source.value === "number" && Number.isFinite(source.value)).map(source => ({ label: String(source.label || source.key || "Fonte").slice(0, 24), value: Number(source.value) }));
  const platformChart = platformRows.map(row => ({ label: String(row.platform || row.slug || "Plataforma"), value: Number(row.central_revenue_confirmed ?? row.revenue ?? row.value) })).filter(row => Number.isFinite(row.value) && row.value > 0);
  const custodyChart = sources.filter(source => source.key !== "finance.legacy_unclassified" && typeof source.value === "number" && Number.isFinite(source.value)).map(source => ({ label: String(source.label || source.key || "Fonte").replace(" disponível", ""), value: Number(source.value) }));

  return <section className="financeReadOnlyDashboard">
    <div className="financeDashboardHead"><div><span>FINANÇAS · SOMENTE LEITURA</span><h2>Centro financeiro</h2></div><DataFreshnessIndicator status={reconciliation.state === "READ_ONLY_RECONCILIATION_READY" ? "fresh" : "stale"} updatedAt={String(reconciliation.checkedAt || "")} /></div>
    <div className="financeReconciliationBanner"><b>Reconciliação PaySuite pendente de validação externa.</b><span>Os valores abaixo vêm das fontes internas e não confirmam o saldo PaySuite.</span></div>
    <KPIGrid items={kpis} />
    <div className="financeAnalyticsGrid">
      <ChartContainer title="De quem é o dinheiro sob custódia"><AnalyticsBarChart data={custodyChart} label="MZN sob custódia" /></ChartContainer>
      <ChartContainer title="Receita confirmada por plataforma"><AnalyticsBarChart data={platformChart} label="Receita confirmada" /></ChartContainer>
      <ChartContainer title="Valores confirmados por fonte"><AnalyticsBarChart data={confirmedSourceChart} label="MZN confirmados" /></ChartContainer>
      <ChartContainer title="Reconciliação com PaySuite"><div className="financeReconciliationTable"><div className="financeTableHead"><span>Fonte</span><span>Valor</span><span>Estado</span></div>{sources.filter(source => source.key !== "finance.legacy_unclassified").map(source => <div className="financeTableRow" key={String(source.key)}><span>{String(source.label || source.key)}</span><b>{typeof source.value === "number" ? `${source.value.toLocaleString("pt-MZ", { minimumFractionDigits: 2 })} MT` : "Indisponível"}</b><em>{isPaysuiteReconciled ? "Confirmado" : "Por validar"}</em></div>)}</div></ChartContainer>
    </div>
    {platformRows.length > 0 && <div className="financeSourceList compactFinanceSources"><strong>Estado por plataforma</strong>{platformRows.map(row => <div key={String(row.slug || row.platform)}><span>{String(row.platform)}</span><small>{String(row.state)} · {String(row.evidence)}</small></div>)}</div>}
    <div className="financeDataFoot"><b>PaySuite: {isPaysuiteReconciled ? "saldo confirmado" : "não reconciliado"}</b><span>{String(paysuite.reason || "A API oficial de saldo/extrato ainda não está configurada.")}</span></div>
    {qualityChecks.length > 0 && <details className="financeQualityDetails"><summary>Qualidade e fontes auditadas</summary><div className="financeSourceList">{qualityChecks.map(check => <div key={String(check.key)}><span>{String(check.label)}</span><small>{String(check.state)} · {String(check.detail)}</small></div>)}{sources.map(source => <div key={String(source.key)}><span>{String(source.label || source.key)}</span><small>{String(source.source || "Fonte não indicada")} · {String(source.status || "indisponível")}</small></div>)}</div></details>}
  </section>;
}
