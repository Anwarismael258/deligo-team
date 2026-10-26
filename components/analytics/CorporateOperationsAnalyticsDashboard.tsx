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
const itemList = (items: unknown): Item[] => Array.isArray(items) ? items.filter(item => item && typeof item === "object").map(item => ({ label: String((item as Item).label || "Não indicado"), value: Number.isFinite(Number((item as Item).value)) ? Number((item as Item).value) : 0 })) : [];
const rows = (items?: Item[]) => itemList(items).map(item => ({ id: item.label, label: item.label, total: item.value }));
const labels = (...groups: Array<Item[] | undefined>) => Array.from(new Set(groups.flatMap(group => itemList(group).map(item => item.label)).filter(Boolean)));

export function CorporateOperationsAnalyticsDashboard({ mode }: { mode: Mode }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [payload, setPayload] = useState<Payload | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    const params = new URLSearchParams({ mode, period: filters.period });
    if (filters.from) params.set("from", filters.from); if (filters.to) params.set("to", filters.to); if (filters.platform) params.set("platform", filters.platform); if (filters.department) params.set("department", filters.department); if (filters.status) params.set("status", filters.status); if (filters.eventType) params.set("type", filters.eventType);
    let cancelled = false; let busy = false;
    const load = async () => { if (cancelled || busy) return; busy = true; if (!payload) setLoading(true); try { const response = await fetch(`/api/analytics/corporate-operations?${params}`, { cache: "no-store" }); const raw = await response.text(); let body: Payload & { error?: string } = {}; try { body = raw.trim() ? JSON.parse(raw) : {}; } catch { throw new Error(`Resposta inválida do servidor (${response.status}).`); } if (!response.ok) throw new Error(body.error || "Não foi possível carregar o dashboard."); if (!cancelled) { setPayload(body); setError(""); } } catch (reason) { if (!cancelled) setError(reason instanceof Error ? reason.message : "Não foi possível actualizar o dashboard."); } finally { busy = false; if (!cancelled) setLoading(false); } };
    void load(); const timer = window.setInterval(() => void load(), 10_000); const refresh = () => void load(); window.addEventListener("focus", refresh);
    return () => { cancelled = true; window.clearInterval(timer); window.removeEventListener("focus", refresh); };
  }, [mode, filters.period, filters.from, filters.to, filters.platform, filters.department, filters.status, filters.eventType]);
  const data = payload?.data;
  const kpis: KPIResult[] = (Array.isArray(data?.kpis) ? data.kpis : []).filter(Boolean).map(item => ({ id: String(item.id), label: String(item.label), value: item.value == null ? null : Number(item.value), unit: item.unit as KPIResult["unit"], sourceStatus: item.status === "fresh" ? "fresh" : "unavailable", source: `${item.source || "Fonte autorizada"} · ${item.formula || "agregação"}` }));
  const first = itemList(mode === "institutional" ? data?.byStatus : mode === "jobs" ? data?.byDepartment : mode === "projects" ? data?.byProjectStatus : data?.byType);
  const second = itemList(mode === "institutional" ? data?.byType : mode === "jobs" ? data?.byStatus : mode === "projects" ? data?.byPriority : data?.byStatus);
  const statusOptions = labels(itemList(data?.byStatus), itemList(data?.byProjectStatus));
  const typeOptions = labels(itemList(data?.byType), itemList(data?.byPriority));
  return <section className="analyticsDashboardShell corporateOperationsAnalytics"><DashboardHeader title={title[mode]} description={description[mode]} updatedAt={payload?.range ? `${payload.range.from} → ${payload.range.to}` : undefined} /><DashboardFilters value={filters} onChange={setFilters} platforms={(data?.filters?.platforms || []).map(item => item.id)} /><div className="analyticsFilters" aria-label="Filtros adicionais"><label><span>Estado</span><select value={filters.status || ""} onChange={event => setFilters({ ...filters, status: event.target.value || undefined })}><option value="">Todos os estados</option>{statusOptions.map(value => <option value={value} key={value}>{value}</option>)}</select></label><label><span>Departamento</span><select value={filters.department || ""} onChange={event => setFilters({ ...filters, department: event.target.value || undefined })}><option value="">Todos os departamentos</option>{(data?.filters?.departments || []).map(item => <option value={item.id} key={item.id}>{item.name}</option>)}</select></label><label><span>Tipo</span><select value={filters.eventType || ""} onChange={event => setFilters({ ...filters, eventType: event.target.value || undefined })}><option value="">Todos os tipos</option>{typeOptions.map(value => <option value={value} key={value}>{value}</option>)}</select></label></div>{error ? <EmptyState title="Dashboard indisponível" description={error} /> : loading && !payload ? <EmptyState title="A carregar dashboard" description="A consultar os dados autorizados…" /> : <><KPIGrid items={kpis} /><div className="analyticsExecutiveGrid"><ChartContainer title="Distribuição principal" description="Agregação da fonte autorizada."><AnalyticsBarChart data={first} label="Total" /></ChartContainer><ChartContainer title="Estados e tipos" description="Sem dados pessoais nos gráficos."><AnalyticsDataTable rows={rows(second)} columns={[{ key: "label", label: "Categoria" }, { key: "total", label: "Total" }]} empty="Sem dados verificáveis." /></ChartContainer></div><ChartContainer title="Evolução no período" description="Série da fonte autorizada; dias sem registos não são inventados."><AnalyticsLineChart data={(data?.series || []).map(item => ({ date: item.label, value: item.value }))} label="Registos" /></ChartContainer><div className="analyticsDataNote">{data?.limitations?.join(" ")}</div></>}</section>;
}
