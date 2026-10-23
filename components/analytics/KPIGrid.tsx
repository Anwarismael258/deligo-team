import type { KPIResult } from "@/lib/analytics-contracts";
import { KPICard } from "./KPICard";

export function KPIGrid({ items }: { items: KPIResult[] }) {
  return <div className="analyticsKpiGrid">{items.map((item) => <KPICard kpi={item} key={item.id} />)}</div>;
}
