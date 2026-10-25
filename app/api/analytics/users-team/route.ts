import { NextRequest, NextResponse } from "next/server";
import { hqRest, hqRpc, requireCorporatePermission } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

type Row = Record<string, unknown>;
type Period = "today" | "last_7_days" | "last_30_days" | "last_90_days" | "this_year" | "custom";
const dayMs = 86_400_000;

function dateOnly(value: unknown) { return typeof value === "string" ? value.slice(0, 10) : ""; }
function maputoDate(date: Date) { return new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Maputo", year: "numeric", month: "2-digit", day: "2-digit" }).format(date); }
function start(date: string) { return new Date(`${date}T00:00:00+02:00`); }
function validDate(value: string | null) { return value && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null; }

function range(period: Period, from: string | null, to: string | null) {
  const today = maputoDate(new Date());
  const end = period === "custom" ? to : today;
  const days = period === "today" ? 1 : period === "last_7_days" ? 7 : period === "last_90_days" ? 90 : 30;
  if (period === "this_year") return { from: `${today.slice(0, 4)}-01-01`, to: today, days: Math.max(1, Math.round((start(today).getTime() - start(`${today.slice(0, 4)}-01-01`).getTime()) / dayMs) + 1) };
  if (period === "custom" && from && end) {
    return { from, to: end, days: Math.max(1, Math.round((start(end).getTime() - start(from).getTime()) / dayMs) + 1) };
  }
  const endDate = start(end || today);
  return { from: maputoDate(new Date(endDate.getTime() - (days - 1) * dayMs)), to: end || today, days };
}

function previous(current: { from: string; to: string; days: number }) {
  const end = new Date(start(current.from).getTime() - dayMs);
  return { from: maputoDate(new Date(end.getTime() - (current.days - 1) * dayMs)), to: maputoDate(end), days: current.days };
}

function inRange(value: unknown, current: { from: string; to: string }) {
  const date = dateOnly(value);
  return Boolean(date && date >= current.from && date <= current.to);
}

function percent(current: number, prior: number) { return prior === 0 ? null : Number((((current - prior) / prior) * 100).toFixed(2)); }
function emptyPoint(date: string) { return { date, newUsers: 0, memberships: 0, tasksCreated: 0, tasksCompleted: 0 }; }
function seriesFor(current: { from: string; to: string }, users: Row[], tasks: Row[]) {
  const points = new Map<string, ReturnType<typeof emptyPoint>>();
  for (let cursor = start(current.from); cursor <= start(current.to); cursor = new Date(cursor.getTime() + dayMs)) points.set(maputoDate(cursor), emptyPoint(maputoDate(cursor)));
  const firstJoin = new Map<string, string>();
  users.forEach(row => { const id = String(row.user_id || ""); const joined = dateOnly(row.joined_at || row.created_at); if (id && joined && (!firstJoin.has(id) || joined < firstJoin.get(id)!)) firstJoin.set(id, joined); });
  firstJoin.forEach(date => { const point = points.get(date); if (point) point.newUsers += 1; });
  users.forEach(row => { const point = points.get(dateOnly(row.joined_at || row.created_at)); if (point) point.memberships += 1; });
  tasks.forEach(row => { const created = points.get(dateOnly(row.created_at)); if (created) created.tasksCreated += 1; const completed = points.get(dateOnly(row.completed_at)); if (completed && String(row.status) === "completed") completed.tasksCompleted += 1; });
  return [...points.values()];
}

function appName(row: Row) { return String(row.app_name || row.platform_name || row.app_slug || "Plataforma não indicada"); }
function state(row: Row) { return String(row.profile_status || row.membership_status || row.status || "indisponível").toLowerCase(); }

export async function GET(request: NextRequest) {
  const periodParam = request.nextUrl.searchParams.get("period") as Period | null;
  const period: Period = ["today", "last_7_days", "last_30_days", "last_90_days", "this_year", "custom"].includes(String(periodParam)) ? periodParam as Period : "last_30_days";
  const current = range(period, validDate(request.nextUrl.searchParams.get("from")), validDate(request.nextUrl.searchParams.get("to")));
  const prior = previous(current);
  const selectedPlatform = request.nextUrl.searchParams.get("platform")?.trim() || "";
  const selectedDepartment = request.nextUrl.searchParams.get("department")?.trim() || "";
  const selectedStatus = request.nextUrl.searchParams.get("status")?.trim().toLowerCase() || "";
  const authorization = await requireCorporatePermission("users.view", selectedPlatform || undefined);
  if (!authorization) return NextResponse.json({ error: "Sem permissão para consultar utilizadores e equipa." }, { status: 403 });

  const allowedPlatforms = authorization.isSuperAdmin ? "" : authorization.platformSlugs.length ? `&app_slug=in.(${authorization.platformSlugs.join(",")})` : "&app_slug=eq.__forbidden__";
  const platformFilter = selectedPlatform ? `&app_slug=eq.${encodeURIComponent(selectedPlatform)}` : allowedPlatforms;
  try {
    const [users, employees, tasks, departments] = await Promise.all([
      hqRest(`global_user_platforms_v1?select=user_id,app_slug,app_name,roles,profile_status,membership_status,joined_at,last_seen_at&limit=5000${platformFilter}`) as Promise<Row[]>,
      hqRpc("hq_employee_directory_v1") as Promise<Row[]>,
      hqRest("tasks?select=id,status,assigned_to,department_id,due_at,created_at,completed_at,updated_at&limit=5000") as Promise<Row[]>,
      hqRest("departments?select=id,code,name,active&limit=100") as Promise<Row[]>,
    ]);
    const uniqueUsers = new Map<string, Row>();
    for (const user of users || []) if (!uniqueUsers.has(String(user.user_id))) uniqueUsers.set(String(user.user_id), user);
    const firstJoin = new Map<string, string>();
    for (const user of users || []) { const id = String(user.user_id || ""); const joined = dateOnly(user.joined_at); if (id && joined && (!firstJoin.has(id) || joined < firstJoin.get(id)!)) firstJoin.set(id, joined); }
    const usersByPlatform = new Map<string, number>();
    const usersByRole = new Map<string, number>();
    const userStates = new Map<string, number>();
    for (const user of users || []) {
      usersByPlatform.set(appName(user), (usersByPlatform.get(appName(user)) || 0) + 1);
      const role = String(user.roles || "não indicado"); usersByRole.set(role, (usersByRole.get(role) || 0) + 1);
      const status = state(user); userStates.set(status, (userStates.get(status) || 0) + 1);
    }
    const userCountIn = (r: { from: string; to: string }) => [...firstJoin.values()].filter(value => value >= r.from && value <= r.to).length;
    const filteredEmployees = (employees || []).filter(employee => (!selectedDepartment || String(employee.department_code || employee.department || employee.department_name || "") === selectedDepartment) && (!selectedStatus || String(employee.status || "").toLowerCase() === selectedStatus));
    const tasksForPeriod = (r: { from: string; to: string }) => (tasks || []).filter(task => inRange(task.created_at, r) || inRange(task.completed_at, r));
    const currentTasks = tasksForPeriod(current);
    const priorTasks = tasksForPeriod(prior);
    const completed = (rows: Row[]) => rows.filter(row => String(row.status) === "completed" && inRange(row.completed_at, current)).length;
    const taskStates = new Map<string, number>();
    for (const task of tasks || []) { const key = String(task.status || "indisponível"); taskStates.set(key, (taskStates.get(key) || 0) + 1); }
    const departmentsOut = new Map<string, number>();
    for (const employee of filteredEmployees) { const key = String(employee.department_name || employee.department || employee.department_code || "Sem departamento"); departmentsOut.set(key, (departmentsOut.get(key) || 0) + 1); }
    const overdue = (tasks || []).filter(task => task.due_at && new Date(String(task.due_at)).getTime() < Date.now() && !["completed", "cancelled"].includes(String(task.status))).length;
    const currentSeries = seriesFor(current, users || [], currentTasks);
    const priorSeries = seriesFor(prior, users || [], priorTasks);
    return NextResponse.json({
      timezone: "Africa/Maputo", period, range: current, previousRange: prior,
      users: { total: uniqueUsers.size, newUsers: userCountIn(current), previousNewUsers: userCountIn(prior), changePercent: percent(userCountIn(current), userCountIn(prior)), active: userStates.get("active") ?? null, suspended: userStates.get("suspended") ?? null, pending: userStates.get("pending") ?? userStates.get("invited") ?? null, byPlatform: [...usersByPlatform.entries()].map(([label, value]) => ({ label, value })), byRole: [...usersByRole.entries()].map(([label, value]) => ({ label, value })), byStatus: [...userStates.entries()].map(([label, value]) => ({ label, value })) },
      team: { total: filteredEmployees.length, active: filteredEmployees.filter(employee => String(employee.status) === "active").length, byDepartment: [...departmentsOut.entries()].map(([label, value]) => ({ label, value })), tasksCreated: currentTasks.filter(task => inRange(task.created_at, current)).length, tasksCompleted: completed(currentTasks), previousTasksCompleted: priorTasks.filter(task => String(task.status) === "completed" && inRange(task.completed_at, prior)).length, tasksOverdue: overdue, taskStates: [...taskStates.entries()].map(([label, value]) => ({ label, value })), changePercent: percent(completed(currentTasks), priorTasks.filter(task => String(task.status) === "completed" && inRange(task.completed_at, prior)).length) },
      series: currentSeries, previousSeries: priorSeries,
      filters: { platforms: authorization.isSuperAdmin ? [...new Set((users || []).map(row => String(row.app_slug || "")).filter(Boolean))] : authorization.platformSlugs, departments: (departments || []).filter(department => department.active !== false).map(department => ({ id: department.id, code: department.code, name: department.name })) },
      sources: { users: "hq.global_user_platforms_v1 · user_id deduplicado · joined_at", team: "hq_employee_directory_v1", tasks: "hq.tasks · created_at/completed_at/status" },
      limitations: ["Utilizadores activos só são apresentados quando o estado da fonte é explicitamente active.", "A produtividade individual não é calculada; apenas volume agregado de tarefas.", "A série não infere novos utilizadores a partir de last_seen_at."],
    }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Dashboard de utilizadores e equipa indisponível." }, { status: 502 });
  }
}
