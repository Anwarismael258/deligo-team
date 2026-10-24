import type { KPIResult } from "@/lib/analytics-contracts";

function formatValue(kpi: KPIResult) {
  if (kpi.value === null) return "Indisponível";
  if (kpi.unit === "MZN") return `${kpi.value.toLocaleString("pt-MZ", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} MT`;
  if (kpi.unit === "%") return `${kpi.value.toLocaleString("pt-MZ", { maximumFractionDigits: 1 })}%`;
  return kpi.value.toLocaleString("pt-MZ");
}

export function KPICard({ kpi }: { kpi: KPIResult }) {
  if (kpi.sourceStatus === "unavailable") return null;
  const trend = kpi.changePercent == null ? null : `${kpi.changePercent >= 0 ? "+" : ""}${kpi.changePercent.toFixed(1)}%`;
  return <article className={`analyticsKpiCard analyticsStatus-${kpi.sourceStatus}`}><span>{kpi.label}</span><strong>{formatValue(kpi)}</strong>{trend && <small className={kpi.changePercent! >= 0 ? "analyticsTrendPositive" : "analyticsTrendNegative"}>{trend} versus período anterior</small>}{kpi.source && <small>{kpi.source}</small>}</article>;
}
