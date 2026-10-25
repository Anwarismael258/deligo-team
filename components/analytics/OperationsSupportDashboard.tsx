import { useEffect, useState } from "react";
import type { AnalyticsFilters, KPIResult } from "@/lib/analytics-contracts";
import { AnalyticsDataTable } from "./AnalyticsDataTable";
import { ChartContainer } from "./ChartContainer";
import { DashboardFilters } from "./DashboardFilters";
import { DashboardHeader } from "./DashboardHeader";
import { EmptyState } from "./EmptyState";
import { KPIGrid } from "./KPIGrid";
import { AnalyticsBarChart, AnalyticsLineChart } from "./AnalyticsCharts";

type Mode = "field" | "support";
type Breakdown = Array<{ label: string; value: number }>;
type Point = { date: string; visits: number; conversions: number; ticketsOpened: number; ticketsResolved: number };
type Data = { range?: { from: string; to: string }; data?: Record<string, unknown> & { byPlatform?: Breakdown; byStatus?: Breakdown; byActivity?: Breakdown; taskStates?: Breakdown; byPriority?: Breakdown; series?: Point[]; filters?: { platforms?: string[]; departments?: Array<{ id?: string; name?: string }>; agents?: Array<{ id?: string; name?: string }> } }; limitations?: string[] };
const numberValue = (value: unknown) => typeof value === "number" && Number.isFinite(value) ? value : null;
const labels = (rows: Breakdown | undefined) => (rows || []).map(item => ({ id: item.label, label: item.label, total: item.value }));

export function OperationsSupportDashboard({ mode }: { mode: Mode }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [payload, setPayload] = useState<Data | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    const params = new URLSearchParams({ mode, period: filters.period });
    if (filters.from) params.set("from", filters.from); if (filters.to) params.set("to", filters.to); if (filters.platform) params.set("platform", filters.platform); if (filters.status) params.set("status", filters.status); if (filters.priority) params.set("priority", filters.priority); if (filters.agent) params.set("agent", filters.agent); if (filters.department) params.set("department", filters.department);
    let cancelled = false;
    let busy = false;
    const load = async () => {
      if (cancelled || busy) return;
      busy = true;
      try {
        const response = await fetch(`/api/analytics/operations-support?${params.toString()}`, { cache: "no-store" });
        const body = await response.json();
        if (!response.ok) throw new Error(body.error || "Não foi possível carregar o dashboard operacional.");
        if (!cancelled) { setPayload(body as Data); setError(""); }
      } catch (reason) {
        if (!cancelled) setError(reason instanceof Error ? reason.message : "Não foi possível actualizar o dashboard.");
      } finally { busy = false; }
    };
    void load();
    const timer = window.setInterval(() => void load(), 10_000);
    const refresh = () => void load();
    window.addEventListener("focus", refresh);
    return () => { cancelled = true; window.clearInterval(timer); window.removeEventListener("focus", refresh); };
  }, [mode, filters.period, filters.from, filters.to, filters.platform, filters.status, filters.priority, filters.agent, filters.department]);
  const data = payload?.data;
  const kpis: KPIResult[] = mode === "field" ? [
    { id: "field-agents", label: "Agentes activos", value: numberValue(data?.agentsActive), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "employees · estado e função" },
    { id: "field-visits", label: "Visitas realizadas", value: numberValue(data?.visitsCompleted), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "field_visits · estado concluído" },
    { id: "field-establishments", label: "Estabelecimentos contactados", value: numberValue(data?.establishmentsContacted), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "acquisition_leads · criados no período" },
    { id: "field-new-partners", label: "Novos parceiros", value: numberValue(data?.newPartners), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "acquisition_partners" },
    { id: "field-approved", label: "Parceiros aprovados", value: numberValue(data?.partnersApproved), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "leads/partners · aprovado ou won" },
    { id: "field-conversion", label: "Taxa de conversão", value: numberValue(data?.conversionRate), unit: "%", sourceStatus: data?.conversionRate == null ? "unavailable" : "fresh", source: "aprovados ÷ leads criados" },
    { id: "field-pending", label: "Tarefas pendentes", value: numberValue(data?.tasksPending), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "tasks · estado" },
    { id: "field-completed", label: "Tarefas concluídas", value: numberValue(data?.tasksCompleted), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "tasks · completed_at" },
  ] : [
    { id: "support-open", label: "Tickets abertos", value: numberValue(data?.ticketsOpen), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "support_tickets · período" },
    { id: "support-resolved", label: "Tickets resolvidos", value: numberValue(data?.ticketsResolved), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "resolved_at/closed_at" },
    { id: "support-pending", label: "Tickets pendentes", value: numberValue(data?.ticketsPending), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "support_tickets · estado" },
    { id: "support-critical", label: "Tickets críticos", value: numberValue(data?.ticketsCritical), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "priority + estado" },
    { id: "support-response", label: "Primeira resposta média", value: numberValue(data?.averageFirstResponseMinutes), unit: "minutes", sourceStatus: data?.averageFirstResponseMinutes == null ? "unavailable" : "fresh", source: "support_conversations · minutos" },
    { id: "support-resolution", label: "Resolução média", value: numberValue(data?.averageResolutionMinutes), unit: "minutes", sourceStatus: data?.averageResolutionMinutes == null ? "unavailable" : "fresh", source: "timestamps do ticket · minutos" },
    { id: "support-reopened", label: "Tickets reabertos", value: numberValue(data?.reopened), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "reopen_count/histórico" },
  ];
  const breakdown = mode === "field" ? data?.byPlatform : data?.byStatus; const series = data?.series || [];
  return <section className="analyticsDashboardShell operationsSupportDashboard">
    <DashboardHeader title={mode === "field" ? "Dashboard de Operações de Campo" : "Dashboard de Apoio ao Cliente"} description={mode === "field" ? "Visitas, parceiros e tarefas agregados a partir das fontes Field e Aquisição." : "Fila de atendimento, tempos e estados provenientes das fontes de suporte."} updatedAt={payload?.range ? `${payload.range.from} → ${payload.range.to}` : undefined} />
    <DashboardFilters value={filters} onChange={setFilters} platforms={data?.filters?.platforms || []} />
    <div className="analyticsFilters" aria-label="Filtros operacionais"><label><span>Estado</span><select value={filters.status || ""} onChange={event => setFilters({ ...filters, status: event.target.value || undefined })}><option value="">Todos os estados</option>{(mode === "field" ? ["planned", "in_progress", "completed", "cancelled", "won", "approved"] : ["open", "in_analysis", "in_progress", "pending", "waiting_customer", "resolved", "closed"]).map(value => <option value={value} key={value}>{value.replaceAll("_", " ")}</option>)}</select></label>{mode === "support" && <label><span>Prioridade</span><select value={filters.priority || ""} onChange={event => setFilters({ ...filters, priority: event.target.value || undefined })}><option value="">Todas as prioridades</option>{["low", "normal", "high", "urgent", "critical"].map(value => <option value={value} key={value}>{value}</option>)}</select></label>}<label><span>Departamento</span><select value={filters.department || ""} onChange={event => setFilters({ ...filters, department: event.target.value || undefined })}><option value="">Todos os departamentos</option>{(data?.filters?.departments || []).map(department => <option value={String(department.id || "")} key={String(department.id)}>{String(department.name || department.id)}</option>)}</select></label><label><span>Agente</span><select value={filters.agent || ""} onChange={event => setFilters({ ...filters, agent: event.target.value || undefined })}><option value="">Todos os agentes</option>{(data?.filters?.agents || []).map(agent => <option value={String(agent.id || "")} key={String(agent.id)}>{String(agent.name || agent.id)}</option>)}</select></label></div>
    {error && !payload ? <EmptyState title="A carregar dashboard" description={error} /> : <><KPIGrid items={kpis} /><div className="analyticsExecutiveGrid"><ChartContainer title={mode === "field" ? "Distribuição por plataforma" : "Tickets por estado"} description="Dados agregados da fonte autorizada."><AnalyticsBarChart data={breakdown} label={mode === "field" ? "Operações" : "Tickets"} /></ChartContainer><ChartContainer title={mode === "field" ? "Actividades por tipo" : "Tickets por plataforma"} description="Sem dados pessoais desnecessários."><AnalyticsDataTable rows={labels(mode === "field" ? data?.byActivity : data?.byPlatform)} columns={[{ key: "label", label: mode === "field" ? "Actividade" : "Plataforma" }, { key: "total", label: "Total" }]} empty="Nenhum registo devolvido." /></ChartContainer></div><ChartContainer title={mode === "field" ? "Visitas e conversões" : "Tickets abertos e resolvidos"} description="Série diária real; dias sem actividade não são apresentados como eventos."><AnalyticsLineChart data={series.map(point => ({ date: point.date, value: mode === "field" ? point.visits : point.ticketsOpened, secondary: mode === "field" ? point.conversions : point.ticketsResolved }))} label={mode === "field" ? "Visitas" : "Tickets abertos"} secondaryLabel={mode === "field" ? "Conversões" : "Tickets resolvidos"} /></ChartContainer>{mode === "field" ? <ChartContainer title="Tarefas por estado" description="Carga operacional sem classificação individual."><AnalyticsDataTable rows={labels(data?.taskStates)} columns={[{ key: "label", label: "Estado" }, { key: "total", label: "Total" }]} empty="Nenhuma tarefa devolvida." /></ChartContainer> : <ChartContainer title="Tickets por prioridade" description="Tickets críticos são identificados por prioridade e estado aberto."><AnalyticsDataTable rows={labels(data?.byPriority)} columns={[{ key: "label", label: "Prioridade" }, { key: "total", label: "Total" }]} empty="Nenhuma prioridade devolvida." /></ChartContainer>}<div className="analyticsDataNote">{payload?.limitations?.join(" ") || "Fonte actualizada no período seleccionado."}</div></>}
  </section>;
}
