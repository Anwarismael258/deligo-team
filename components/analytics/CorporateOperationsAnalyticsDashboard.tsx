"use client";

import { useEffect, useState } from "react";
import type { AnalyticsFilters, KPIResult } from "@/lib/analytics-contracts";
import { AnalyticsDataTable } from "./AnalyticsDataTable";
import { ChartContainer } from "./ChartContainer";
import { DashboardFilters } from "./DashboardFilters";
import { DashboardHeader } from "./DashboardHeader";
import { EmptyState } from "./EmptyState";
import { KPIGrid } from "./KPIGrid";
import { AnalyticsBarChart, AnalyticsLineChart } from "./AnalyticsCharts";

type Mode = "institutional" | "jobs" | "projects" | "reports";
type Item = { label: string; value: number };
type Payload = { range?: { from: string; to: string }; data?: { kpis?: Array<{ id: string; label: string; value: number | null; unit: string; source: string; formula: string; status: string }>; byStatus?: Item[]; byType?: Item[]; byDepartment?: Item[]; byPriority?: Item[]; byPlatform?: Item[]; byProjectStatus?: Item[]; series?: Item[]; limitations?: string[]; filters?: { platforms?: Array<{ id: string; name: string }>; departments?: Array<{ id: string; name: string }> } }; sources?: Record<string, string> };
const title: Record<Mode, string> = { institutional: "Analytics do Site Institucional", jobs: "Analytics de Vagas", projects: "Analytics de Projectos e Tarefas", reports: "Analytics de Relatórios" };
const description: Record<Mode, string> = { institutional: "Conteúdos e entradas institucionais com origem verificável.", jobs: "Vagas publicadas e estados de recrutamento disponíveis.", projects: "Execução, prazos e tarefas agregados sem alterar operações.", reports: "Disponibilidade e geração de relatórios registadas pelo backend." };
const rows = (items?: Item[]) => (items || []).map(item => ({ id: item.label, label: item.label, total: item.value }));
const labels = (...groups: Array<Item[] | undefined>) => Array.from(new Set(groups.flatMap(group => (group || []).map(item => item.label)).filter(Boolean)));

export function CorporateOperationsAnalyticsDashboard({ mode }: { mode: Mode }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [payload, setPayload] = useState<Payload | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    const params = new URLSearchParams({ mode, period: filters.period });
    if (filters.from) params.set("from", filters.from); if (filters.to) params.set("to", filters.to); if (filters.platform) params.set("platform", filters.platform); if (filters.department) params.set("department", filters.department); if (filters.status) params.set("status", filters.status); if (filters.eventType) params.set("type", filters.eventType);
    let cancelled = false; let busy = false;
    const load = async () => { if (cancelled || busy) return; busy = true; if (!payload) setLoading(true); try { const response = await fetch(`/api/analytics/corporate-operations?${params}`, { cache: "no-store" }); const body = await response.json(); if (!response.ok) throw new Error(body.error || "Não foi possível carregar o dashboard."); if (!cancelled) { setPayload(body as Payload); setError(""); } } catch (reason) { if (!cancelled) setError(reason instanceof Error ? reason.message : "Não foi possível actualizar o dashboard."); } finally { busy = false; if (!cancelled) setLoading(false); } };
    void load(); const timer = window.setInterval(() => void load(), 10_000); const refresh = () => void load(); window.addEventListener("focus", refresh);
    return () => { cancelled = true; window.clearInterval(timer); window.removeEventListener("focus", refresh); };
  }, [mode, filters.period, filters.from, filters.to, filters.platform, filters.department, filters.status, filters.eventType]);
  const data = payload?.data;
  const kpis: KPIResult[] = (data?.kpis || []).map(item => ({ id: item.id, label: item.label, value: item.value, unit: item.unit as KPIResult["unit"], sourceStatus: item.status === "fresh" ? "fresh" : "unavailable", source: `${item.source} · ${item.formula}` }));
  const first = mode === "institutional" ? data?.byStatus : mode === "jobs" ? data?.byDepartment : mode === "projects" ? data?.byProjectStatus : data?.byType;
  const second = mode === "institutional" ? data?.byType : mode === "jobs" ? data?.byStatus : mode === "projects" ? data?.byPriority : data?.byStatus;
  const statusOptions = labels(data?.byStatus, data?.byProjectStatus);
  const typeOptions = labels(data?.byType, data?.byPriority);
  return <section className="analyticsDashboardShell corporateOperationsAnalytics"><DashboardHeader title={title[mode]} description={description[mode]} updatedAt={payload?.range ? `${payload.range.from} → ${payload.range.to}` : undefined} /><DashboardFilters value={filters} onChange={setFilters} platforms={(data?.filters?.platforms || []).map(item => item.id)} /><div className="analyticsFilters" aria-label="Filtros adicionais"><label><span>Estado</span><select value={filters.status || ""} onChange={event => setFilters({ ...filters, status: event.target.value || undefined })}><option value="">Todos os estados</option>{statusOptions.map(value => <option value={value} key={value}>{value}</option>)}</select></label><label><span>Departamento</span><select value={filters.department || ""} onChange={event => setFilters({ ...filters, department: event.target.value || undefined })}><option value="">Todos os departamentos</option>{(data?.filters?.departments || []).map(item => <option value={item.id} key={item.id}>{item.name}</option>)}</select></label><label><span>Tipo</span><select value={filters.eventType || ""} onChange={event => setFilters({ ...filters, eventType: event.target.value || undefined })}><option value="">Todos os tipos</option>{typeOptions.map(value => <option value={value} key={value}>{value}</option>)}</select></label></div>{error ? <EmptyState title="Dashboard indisponível" description={error} /> : loading && !payload ? <EmptyState title="A carregar dashboard" description="A consultar os dados autorizados…" /> : <><KPIGrid items={kpis} /><div className="analyticsExecutiveGrid"><ChartContainer title="Distribuição principal" description="Agregação da fonte autorizada."><AnalyticsBarChart data={first} label="Total" /></ChartContainer><ChartContainer title="Estados e tipos" description="Sem dados pessoais nos gráficos."><AnalyticsDataTable rows={rows(second)} columns={[{ key: "label", label: "Categoria" }, { key: "total", label: "Total" }]} empty="Sem dados verificáveis." /></ChartContainer></div><ChartContainer title="Evolução no período" description="Série da fonte autorizada; dias sem registos não são inventados."><AnalyticsLineChart data={(data?.series || []).map(item => ({ date: item.label, value: item.value }))} label="Registos" /></ChartContainer><div className="analyticsDataNote">{data?.limitations?.join(" ")}</div></>}</section>;
}
