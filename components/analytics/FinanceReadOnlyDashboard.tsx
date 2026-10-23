"use client";

import { KPIGrid } from "./KPIGrid";
import { DataFreshnessIndicator } from "./DataFreshnessIndicator";
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
  return <section className="financePanel financeReadOnlyDashboard"><div className="panelTitle"><div><span>FASE 2A · SOMENTE LEITURA</span><h2>Inteligência financeira</h2><p>Indicadores derivados das fontes canónicas; nenhuma operação é executada nesta área.</p></div><DataFreshnessIndicator status={reconciliation.state === "READ_ONLY_RECONCILIATION_READY" ? "fresh" : "stale"} updatedAt={String(reconciliation.checkedAt || "")} /></div><KPIGrid items={kpis} /><div className="safeNotice"><b>PaySuite: {isPaysuiteReconciled ? "saldo confirmado" : "Não reconciliado"}</b><span>{String(paysuite.reason || "Não existe endpoint oficial de saldo/extrato configurado no código.")} Não apresentar este valor como saldo confirmado.</span></div><div className="financeSourceList"><strong>Fontes auditadas</strong>{sources.map((source) => <div key={String(source.key)}><span>{String(source.label || source.key)}</span><small>{String(source.source || "Fonte não indicada")} · {String(source.status || "indisponível")}</small></div>)}</div></section>;
}
