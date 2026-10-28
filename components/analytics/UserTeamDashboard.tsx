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
  users?: { total: number; newUsers: number; previousNewUsers: number; changePercent: number | null; active: number | null; suspended: number | null; pending: number | null; byPlatform: Breakdown; byRole: Breakdown; byPlatformRole?: Breakdown; byStatus: Breakdown };
  team?: { total: number; active: number; byDepartment: Breakdown; tasksCreated: number; tasksCompleted: number; previousTasksCompleted: number; tasksOverdue: number; taskStates: Breakdown; changePercent: number | null };
  series?: Point[];
  filters?: { platforms?: string[]; departments?: Array<{ id?: string; code?: string; name?: string }> };
  limitations?: string[];
};

const numberOrNull = (value: number | null | undefined) => value == null ? null : value;
const labelize = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, character => character.toUpperCase());
const userChartStyles = `.userTeamDashboard .analyticsKpiCard{background:linear-gradient(145deg,#10253b,#0b1727);border-color:#315174;color:#eaf2ff;box-shadow:0 10px 24px #02071155}.userTeamDashboard .analyticsKpiCard>span{color:#9db6ce}.userTeamDashboard .analyticsKpiCard>strong{color:#f5f9ff}.userTeamDashboard .analyticsKpiCard>small{color:#86a1bd}.userTeamDashboard .analyticsChartContainer{background:linear-gradient(145deg,#10253b,#0b1727);border-color:#315174;color:#eaf2ff}.userTeamDashboard .analyticsChartHeading h3{color:#f5f9ff;font-size:15px}.userTeamDashboard .analyticsChartCanvas{height:260px!important;min-height:260px!important;background:#0b1b2d;border:1px solid #315174;border-radius:9px;padding:8px}.userTeamDashboard .analyticsChartCanvas svg{height:244px!important;min-height:244px!important}.userTeamDashboard .analyticsChartCanvas svg text{font-size:12px!important;fill:#d7e8f8!important}.userTeamDashboard .analyticsDataNote{color:#9db6ce}`;

type DirectoryEmployee = { id?: string; name?: string; phone?: string; job_title?: string; employee_code?: string; department?: string; status?: string };

export function UserTeamDashboard({ mode, teamDirectory = [] }: { mode: Mode; teamDirectory?: DirectoryEmployee[] }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [data, setData] = useState<Data | null>(null);
  const [error, setError] = useState("");
  const [invitedEmployees, setInvitedEmployees] = useState<DirectoryEmployee[]>(() => teamDirectory.filter(employee => employee.status === "invited"));
  const [inviteNotice, setInviteNotice] = useState("");
  useEffect(() => { setInvitedEmployees(teamDirectory.filter(employee => employee.status === "invited")); }, [teamDirectory]);
  const activateInvitedEmployee = async (employee: DirectoryEmployee) => {
    if (!employee.id) return;
    setInviteNotice("A processar…");
    const response = await fetch("/api/employees", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ employeeId: employee.id, action: "activate" }) });
    const body = await response.json().catch(() => ({}));
    if (response.ok) { setInvitedEmployees(current => current.filter(item => item.id !== employee.id)); setInviteNotice("Acesso activado e auditado."); }
    else setInviteNotice(String(body.error || "Não foi possível activar este acesso."));
  };
  useEffect(() => {
    const params = new URLSearchParams({ period: filters.period });
    if (filters.from) params.set("from", filters.from);
    if (filters.to) params.set("to", filters.to);
    if (filters.platform) params.set("platform", filters.platform);
    if (filters.department) params.set("department", filters.department);
    if (filters.status) params.set("status", filters.status);
    let cancelled = false;
    let busy = false;
    const load = async () => {
      if (cancelled || busy) return;
      busy = true;
      try {
        const response = await fetch(`/api/analytics/users-team?${params.toString()}`, { cache: "no-store" });
        const body = await response.json();
        if (!response.ok) throw new Error(body.error || "Não foi possível carregar os indicadores.");
        if (!cancelled) { setData(body as Data); setError(""); }
      } catch (reason) {
        if (!cancelled) setError(reason instanceof Error ? reason.message : "Não foi possível actualizar os indicadores.");
      } finally { busy = false; }
    };
    void load();
    const timer = window.setInterval(() => void load(), 10_000);
    const refresh = () => void load();
    window.addEventListener("focus", refresh);
    return () => { cancelled = true; window.clearInterval(timer); window.removeEventListener("focus", refresh); };
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
    {mode === "team" && <div className="analyticsFilters" aria-label="Filtros de equipa"><label><span>Departamento</span><select value={filters.department || ""} onChange={event => setFilters({ ...filters, department: event.target.value || undefined })}><option value="">Todos os departamentos</option>{(data?.filters?.departments || []).map(department => <option value={String(department.code || department.id || "")} key={String(department.id || department.code)}>{String(department.name || department.code || "Departamento")}</option>)}</select></label><label><span>Estado</span><select value={filters.status || ""} onChange={event => setFilters({ ...filters, status: event.target.value || undefined })}><option value="">Todos os estados</option>{["active", "invited", "suspended", "completed", "in_progress", "pending", "cancelled"].map(status => <option value={status} key={status}>{labelize(status)}</option>)}</select></label></div>}
    {mode === "team" && invitedEmployees.length > 0 && <section className="invitedEmployeesPanel" aria-labelledby="invited-workers-title"><div><span>ACESSO PENDENTE</span><h3 id="invited-workers-title">Trabalhadores convidados sem primeiro acesso</h3><p>Estas contas ainda não iniciaram sessão na Central.</p></div><div className="invitedEmployeesList">{invitedEmployees.map(employee => <div className="invitedEmployeeRow" key={employee.id}><div><strong>{employee.name || "Trabalhador"}</strong><small>{employee.employee_code || "Sem código"} · {employee.phone || "Sem telefone"} · {employee.job_title || "Cargo pendente"}</small></div><button type="button" onClick={() => void activateInvitedEmployee(employee)}>Activar acesso</button></div>)}</div>{inviteNotice && <small className="invitedEmployeesNotice">{inviteNotice}</small>}</section>}
    {error && !data ? mode === "team" && teamDirectory.length ? <><div className="analyticsExecutiveGrid"><ChartContainer title="Equipa por departamento"><AnalyticsBarChart data={directoryDepartments} label="Trabalhadores" /></ChartContainer><ChartContainer title="Estados da equipa"><AnalyticsDonutChart data={directoryStatuses} /></ChartContainer></div><div className="analyticsDataNote">Resumo da lista autorizada. A leitura analítica será repetida automaticamente.</div></> : <EmptyState title="A carregar indicadores" description={error} /> : <>
      <KPIGrid items={kpis} />
      <DashboardFilters value={filters} onChange={setFilters} platforms={data?.filters?.platforms || []} />
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
      {mode === "users" && <ChartContainer title="Tipos de utilizador por plataforma" description="Papéis confirmados por cada uma das cinco plataformas."><AnalyticsHorizontalBarChart data={(users?.byPlatformRole || users?.byRole || []).map(item => ({ label: labelize(item.label), value: item.value }))} label="Utilizadores por plataforma e tipo" /></ChartContainer>}
      <div className="analyticsDataNote">{data?.limitations?.[0] || "Fonte actualizada no período seleccionado."}{team && <span> · Conclusões agregadas: <TrendIndicator changePercent={team.changePercent} /></span>}</div>
    </>}
  </section>;
}
