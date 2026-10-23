import type { ChangeEvent } from "react";
import type { AnalyticsFilters, AnalyticsPeriod } from "@/lib/analytics-contracts";

const periods: Array<[AnalyticsPeriod, string]> = [["today", "Hoje"], ["last_7_days", "Últimos 7 dias"], ["last_30_days", "Últimos 30 dias"], ["last_90_days", "Últimos 90 dias"], ["this_year", "Este ano"], ["custom", "Intervalo personalizado"]];

export function DashboardFilters({ value, onChange, platforms = [] }: { value: AnalyticsFilters; onChange: (next: AnalyticsFilters) => void; platforms?: string[] }) {
  const update = (event: ChangeEvent<HTMLSelectElement>) => onChange({ ...value, period: event.target.value as AnalyticsPeriod });
  return <div className="analyticsFilters" aria-label="Filtros do dashboard"><label><span>Período</span><select value={value.period} onChange={update}>{periods.map(([key, label]) => <option value={key} key={key}>{label}</option>)}</select></label>{value.period === "custom" && <><label><span>Desde</span><input type="date" value={value.from || ""} onChange={(event) => onChange({ ...value, from: event.target.value || undefined })} /></label><label><span>Até</span><input type="date" value={value.to || ""} onChange={(event) => onChange({ ...value, to: event.target.value || undefined })} /></label></>}{platforms.length > 0 && <label><span>Plataforma</span><select value={value.platform || ""} onChange={(event) => onChange({ ...value, platform: event.target.value || undefined })}><option value="">Todas as plataformas</option>{platforms.map((platform) => <option value={platform} key={platform}>{platform}</option>)}</select></label>}<span className="analyticsTimezone">Fuso: Africa/Maputo</span></div>;
}
