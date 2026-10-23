import { useEffect, useState } from "react";
import type { AnalyticsFilters, KPIResult } from "@/lib/analytics-contracts";
import { AnalyticsDataTable } from "./AnalyticsDataTable";
import { ChartContainer } from "./ChartContainer";
import { DashboardFilters } from "./DashboardFilters";
import { DashboardHeader } from "./DashboardHeader";
import { EmptyState } from "./EmptyState";
import { KPIGrid } from "./KPIGrid";
import { TrendIndicator } from "./TrendIndicator";

type Mode = "users" | "team";
type Point = { date: string; newUsers: number; memberships: number; tasksCreated: number; tasksCompleted: number };
type Breakdown = Array<{ label: string; value: number }>;
type Data = {
  range?: { from: string; to: string };
  users?: { total: number; newUsers: number; previousNewUsers: number; changePercent: number | null; active: number | null; suspended: number | null; pending: number | null; byPlatform: Breakdown; byRole: Breakdown; byStatus: Breakdown };
  team?: { total: number; active: number; byDepartment: Breakdown; tasksCreated: number; tasksCompleted: number; previousTasksCompleted: number; tasksOverdue: number; taskStates: Breakdown; changePercent: number | null };
  series?: Point[];
  filters?: { platforms?: string[]; departments?: Array<{ id?: string; code?: string; name?: string }> };
  limitations?: string[];
};

const numberOrNull = (value: number | null | undefined) => value == null ? null : value;
const labelize = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, character => character.toUpperCase());

export function UserTeamDashboard({ mode }: { mode: Mode }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [data, setData] = useState<Data | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    const params = new URLSearchParams({ period: filters.period });
    if (filters.from) params.set("from", filters.from);
    if (filters.to) params.set("to", filters.to);
    if (filters.platform) params.set("platform", filters.platform);
    if (filters.department) params.set("department", filters.department);
    if (filters.status) params.set("status", filters.status);
    let cancelled = false;
    fetch(`/api/analytics/users-team?${params.toString()}`, { cache: "no-store" })
      .then(async response => { const body = await response.json(); if (!response.ok) throw new Error(body.error || "Não foi possível carregar os indicadores."); return body as Data; })
      .then(next => { if (!cancelled) { setData(next); setError(""); } })
      .catch(reason => { if (!cancelled) { setData(null); setError(reason instanceof Error ? reason.message : "Dashboard indisponível."); } });
    return () => { cancelled = true; };
  }, [filters.period, filters.from, filters.to, filters.platform, filters.department, filters.status]);

  const users = data?.users;
  const team = data?.team;
  const kpis: KPIResult[] = mode === "users" ? [
    { id: "users-total", label: "Utilizadores registados", value: numberOrNull(users?.total), unit: "count", sourceStatus: users ? "fresh" : "unavailable", source: "hq.global_user_platforms_v1 · pessoas únicas" },
    { id: "users-new", label: "Novos utilizadores", value: numberOrNull(users?.newUsers), unit: "count", previousValue: users?.previousNewUsers, changePercent: users?.changePercent, sourceStatus: users ? "fresh" : "unavailable", source: "joined_at · período seleccionado" },
    { id: "users-active", label: "Utilizadores activos", value: numberOrNull(users?.active), unit: "count", sourceStatus: users?.active == null ? "unavailable" : "fresh", source: "Estado explícito da fonte" },
    { id: "users-suspended", label: "Contas suspensas", value: numberOrNull(users?.suspended), unit: "count", sourceStatus: users ? "fresh" : "unavailable", source: "profile_status/membership_status" },
    { id: "users-pending", label: "Contas pendentes", value: numberOrNull(users?.pending), unit: "count", sourceStatus: users ? "fresh" : "unavailable", source: "profile_status/membership_status" },
  ] : [
    { id: "team-total", label: "Trabalhadores", value: numberOrNull(team?.total), unit: "count", sourceStatus: team ? "fresh" : "unavailable", source: "hq_employee_directory_v1" },
    { id: "team-active", label: "Trabalhadores activos", value: numberOrNull(team?.active), unit: "count", sourceStatus: team ? "fresh" : "unavailable", source: "hq_employee_directory_v1 · status" },
    { id: "tasks-created", label: "Tarefas criadas", value: numberOrNull(team?.tasksCreated), unit: "count", sourceStatus: team ? "fresh" : "unavailable", source: "hq.tasks · created_at" },
    { id: "tasks-completed", label: "Tarefas concluídas", value: numberOrNull(team?.tasksCompleted), unit: "count", previousValue: team?.previousTasksCompleted, changePercent: team?.changePercent, sourceStatus: team ? "fresh" : "unavailable", source: "hq.tasks · completed_at/status" },
    { id: "tasks-overdue", label: "Tarefas em atraso", value: numberOrNull(team?.tasksOverdue), unit: "count", sourceStatus: team ? "fresh" : "unavailable", source: "due_at/status" },
  ];
  const breakdown = mode === "users" ? users?.byPlatform : team?.byDepartment;
  const statusRows = mode === "users" ? users?.byStatus : team?.taskStates;
  const maxBreakdown = Math.max(1, ...(breakdown || []).map(item => item.value));
  const maxSeries = Math.max(1, ...(data?.series || []).map(point => mode === "users" ? point.newUsers : point.tasksCompleted));
  return <section className="analyticsDashboardShell userTeamDashboard">
    <DashboardHeader title={mode === "users" ? "Dashboard de utilizadores" : "Dashboard de equipa"} description={mode === "users" ? "Pessoas únicas e contas por plataforma, sem duplicar acessos multiplataforma." : "Dimensão da equipa e volume agregado de tarefas, sem rankings individuais."} updatedAt={data?.range ? `${data.range.from} → ${data.range.to}` : undefined} />
    <DashboardFilters value={filters} onChange={setFilters} platforms={data?.filters?.platforms || []} />
    {mode === "team" && <div className="analyticsFilters" aria-label="Filtros de equipa"><label><span>Departamento</span><select value={filters.department || ""} onChange={event => setFilters({ ...filters, department: event.target.value || undefined })}><option value="">Todos os departamentos</option>{(data?.filters?.departments || []).map(department => <option value={String(department.code || department.id || "")} key={String(department.id || department.code)}>{String(department.name || department.code || "Departamento")}</option>)}</select></label><label><span>Estado</span><select value={filters.status || ""} onChange={event => setFilters({ ...filters, status: event.target.value || undefined })}><option value="">Todos os estados</option>{["active", "invited", "suspended", "completed", "in_progress", "pending", "cancelled"].map(status => <option value={status} key={status}>{labelize(status)}</option>)}</select></label></div>}
    {error ? <EmptyState title="Indicadores indisponíveis" description={error} /> : <>
      <KPIGrid items={kpis} />
      <div className="analyticsExecutiveGrid">
        <ChartContainer title={mode === "users" ? "Distribuição por plataforma" : "Distribuição por departamento"} description="Contagens agregadas da fonte autorizada.">
          {breakdown?.length ? <div className="analyticsBarList">{breakdown.map(item => <div className="analyticsBarRow" key={item.label}><div><strong>{item.label}</strong><small>{item.value} registo(s)</small></div><span><i style={{ width: `${Math.max(3, item.value / maxBreakdown * 100)}%` }} /><b>{item.value}</b></span></div>)}</div> : <EmptyState title="Distribuição indisponível" description="A fonte não devolveu dados suficientes." />}
        </ChartContainer>
        <ChartContainer title={mode === "users" ? "Estados das contas" : "Tarefas por estado"} description="Sem inferir estados ausentes.">
          <AnalyticsDataTable rows={(statusRows || []).map(item => ({ id: item.label, estado: labelize(item.label), total: item.value }))} columns={[{ key: "estado", label: "Estado" }, { key: "total", label: "Total" }]} empty="Nenhum estado devolvido pela fonte." />
        </ChartContainer>
      </div>
      <ChartContainer title={mode === "users" ? "Evolução de novos registos" : "Evolução de tarefas concluídas"} description="Série diária real; dias sem eventos não são inventados como actividade.">
        {data?.series?.some(point => (mode === "users" ? point.newUsers : point.tasksCompleted) > 0) ? <div className="analyticsBarList">{data.series.map(point => { const value = mode === "users" ? point.newUsers : point.tasksCompleted; return <div className="analyticsBarRow" key={point.date}><div><strong>{point.date}</strong><small>{mode === "users" ? "Novos utilizadores" : "Tarefas concluídas"}</small></div><span><i style={{ width: `${Math.max(2, value / maxSeries * 100)}%` }} /><b>{value}</b></span></div>; })}</div> : <EmptyState title="Série histórica indisponível" description="Não existem eventos verificáveis no período seleccionado." />}
      </ChartContainer>
      {mode === "users" && <ChartContainer title="Distribuição por tipo de utilizador" description="Papéis devolvidos pela associação de plataforma."><AnalyticsDataTable rows={(users?.byRole || []).map(item => ({ id: item.label, papel: item.label, total: item.value }))} columns={[{ key: "papel", label: "Papel" }, { key: "total", label: "Total" }]} empty="Nenhum papel devolvido pela fonte." /></ChartContainer>}
      <div className="analyticsDataNote">{data?.limitations?.[0] || "Fonte actualizada no período seleccionado."}{team && <span> · Conclusões agregadas: <TrendIndicator changePercent={team.changePercent} /></span>}</div>
    </>}
  </section>;
}
