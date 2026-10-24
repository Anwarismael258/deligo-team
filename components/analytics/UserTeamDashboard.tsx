import { useEffect, useState } from "react";
import type { AnalyticsFilters, KPIResult } from "@/lib/analytics-contracts";
import { ChartContainer } from "./ChartContainer";
import { DashboardFilters } from "./DashboardFilters";
import { EmptyState } from "./EmptyState";
import { KPIGrid } from "./KPIGrid";
import { TrendIndicator } from "./TrendIndicator";
import { AnalyticsBarChart, AnalyticsDonutChart, AnalyticsHorizontalBarChart, AnalyticsLineChart } from "./AnalyticsCharts";

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
const userChartStyles = `.userTeamDashboard .analyticsChartContainer{background:linear-gradient(145deg,#10253b,#0b1727);border-color:#315174;color:#eaf2ff}.userTeamDashboard .analyticsChartHeading h3{color:#f5f9ff;font-size:15px}.userTeamDashboard .analyticsChartCanvas{height:260px!important;min-height:260px!important;background:#0b1b2d;border:1px solid #315174;border-radius:9px;padding:8px}.userTeamDashboard .analyticsChartCanvas svg{height:244px!important;min-height:244px!important}.userTeamDashboard .analyticsChartCanvas svg text{font-size:12px!important;fill:#d7e8f8!important}.userTeamDashboard .analyticsDataNote{color:#9db6ce}`;

type DirectoryEmployee = { department?: string; status?: string };

export function UserTeamDashboard({ mode, teamDirectory = [] }: { mode: Mode; teamDirectory?: DirectoryEmployee[] }) {
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
  const directoryDepartments = Object.entries(teamDirectory.reduce<Record<string, number>>((result, employee) => { const label = employee.department || "Sem departamento"; result[label] = (result[label] || 0) + 1; return result; }, {})).map(([label, value]) => ({ label, value }));
  const directoryStatuses = Object.entries(teamDirectory.reduce<Record<string, number>>((result, employee) => { const label = labelize(employee.status || "unknown"); result[label] = (result[label] || 0) + 1; return result; }, {})).map(([label, value]) => ({ label, value }));
  return <section className="analyticsDashboardShell userTeamDashboard">
    <style>{userChartStyles}</style>
    <DashboardFilters value={filters} onChange={setFilters} platforms={data?.filters?.platforms || []} />
    {mode === "team" && <div className="analyticsFilters" aria-label="Filtros de equipa"><label><span>Departamento</span><select value={filters.department || ""} onChange={event => setFilters({ ...filters, department: event.target.value || undefined })}><option value="">Todos os departamentos</option>{(data?.filters?.departments || []).map(department => <option value={String(department.code || department.id || "")} key={String(department.id || department.code)}>{String(department.name || department.code || "Departamento")}</option>)}</select></label><label><span>Estado</span><select value={filters.status || ""} onChange={event => setFilters({ ...filters, status: event.target.value || undefined })}><option value="">Todos os estados</option>{["active", "invited", "suspended", "completed", "in_progress", "pending", "cancelled"].map(status => <option value={status} key={status}>{labelize(status)}</option>)}</select></label></div>}
    {error ? mode === "team" && teamDirectory.length ? <><div className="analyticsExecutiveGrid"><ChartContainer title="Equipa por departamento"><AnalyticsBarChart data={directoryDepartments} label="Trabalhadores" /></ChartContainer><ChartContainer title="Estados da equipa"><AnalyticsDonutChart data={directoryStatuses} /></ChartContainer></div><div className="analyticsDataNote">Resumo da lista autorizada. Analytics histórico indisponível: {error}</div></> : <EmptyState title="Indicadores indisponíveis" description={error} /> : <>
      <KPIGrid items={kpis} />
      <div className="analyticsExecutiveGrid">
        <ChartContainer title={mode === "users" ? "Distribuição por plataforma" : "Distribuição por departamento"} description="Contagens agregadas da fonte autorizada.">
          {mode === "team" ? <AnalyticsHorizontalBarChart data={breakdown} label="Tarefas por departamento" /> : <AnalyticsBarChart data={breakdown} label="Utilizadores" />}
        </ChartContainer>
        <ChartContainer title={mode === "users" ? "Estados das contas" : "Tarefas por estado"} description="Estados confirmados pela fonte.">
          <AnalyticsDonutChart data={(statusRows || []).map(item => ({ label: labelize(item.label), value: item.value }))} />
        </ChartContainer>
      </div>
      <ChartContainer title={mode === "users" ? "Evolução de novos registos" : "Evolução de tarefas concluídas"} description="Série diária real; Série histórica indisponível quando a fonte não devolve eventos verificáveis.">
        <AnalyticsLineChart data={(data?.series || []).map(point => ({ date: point.date, value: mode === "users" ? point.newUsers : point.tasksCompleted }))} label={mode === "users" ? "Novos utilizadores" : "Tarefas concluídas"} />
      </ChartContainer>
      {mode === "users" && <ChartContainer title="Tipos de utilizador" description="Papéis confirmados pela associação de plataforma."><AnalyticsHorizontalBarChart data={(users?.byRole || []).map(item => ({ label: labelize(item.label), value: item.value }))} label="Utilizadores por tipo" /></ChartContainer>}
      <div className="analyticsDataNote">{data?.limitations?.[0] || "Fonte actualizada no período seleccionado."}{team && <span> · Conclusões agregadas: <TrendIndicator changePercent={team.changePercent} /></span>}</div>
    </>}
  </section>;
}
