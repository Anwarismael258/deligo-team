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
  const kpis: KPIResult[] = sources.filter((source) => source.key !== "finance.legacy_unclassified").map((source) => ({
    id: String(source.key || "finance.metric"),
    label: String(source.label || "Métrica financeira"),
    value: typeof source.value === "number" ? source.value : null,
    unit: "MZN",
    sourceStatus: source.status === "confirmed" ? "fresh" : source.status === "unavailable" ? "unavailable" : "stale",
    source: source.source,
    permission: "finance.view",
  }));
  const paysuite = (reconciliation.paysuite || {}) as Record<string, unknown>;
  const isPaysuiteReconciled = paysuite.state === "CONFIRMED";
  const platformRows = Array.isArray(reconciliation.platformReconciliation) ? reconciliation.platformReconciliation as Array<Record<string, unknown>> : [];
  const qualityChecks = Array.isArray(reconciliation.qualityChecks) ? reconciliation.qualityChecks as Array<Record<string, unknown>> : [];
  const confirmedSourceChart = sources.filter((source) => source.status === "confirmed" && typeof source.value === "number" && Number.isFinite(source.value)).map((source) => ({ label: String(source.label || source.key || "Fonte").slice(0, 24), value: Number(source.value) }));
  return <section className="financePanel financeReadOnlyDashboard"><div className="panelTitle"><div><span>FASE 2B · SOMENTE LEITURA</span><h2>Consolidação financeira</h2><p>Indicadores derivados das fontes canónicas; nenhuma operação é executada nesta área.</p></div><DataFreshnessIndicator status={reconciliation.state === "READ_ONLY_RECONCILIATION_READY" ? "fresh" : "stale"} updatedAt={String(reconciliation.checkedAt || "")} /></div><KPIGrid items={kpis} /><div className="analyticsExecutiveGrid"><ChartContainer title="Valores confirmados por fonte" description="Apenas valores confirmados; fontes indisponíveis não são desenhadas."><AnalyticsBarChart data={confirmedSourceChart} label="MZN confirmados" /></ChartContainer><div className="safeNotice"><b>PaySuite: {isPaysuiteReconciled ? "saldo confirmado" : "Não reconciliado"}</b><span>{String(paysuite.reason || "Não existe endpoint oficial de saldo/extrato configurado no código.")} Não apresentar este valor como saldo confirmado.</span></div></div>{platformRows.length > 0 && <div className="financeSourceList"><strong>Estado de reconciliação por plataforma</strong>{platformRows.map((row) => <div key={String(row.slug || row.platform)}><span>{String(row.platform)}</span><small>{String(row.state)} · {String(row.evidence)}</small></div>)}</div>}<div className="financeSourceList"><strong>Qualidade dos dados</strong>{qualityChecks.map((check) => <div key={String(check.key)}><span>{String(check.label)}</span><small>{String(check.state)} · {String(check.detail)}</small></div>)}</div><div className="financeSourceList"><strong>Fontes auditadas</strong>{sources.map((source) => <div key={String(source.key)}><span>{String(source.label || source.key)}</span><small>{String(source.source || "Fonte não indicada")} · {String(source.status || "indisponível")}</small></div>)}</div></section>;
}
