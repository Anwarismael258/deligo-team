import { NextResponse } from "next/server";
import { requireCorporatePermission, supabaseUrl } from "@/lib/hq-server";

const headers = (key: string) => ({ apikey: key, Authorization: `Bearer ${key}`, "Accept-Profile": "hq", "Content-Profile": "hq" });
const get = async (key: string, resource: string) => {
  const response = await fetch(`${supabaseUrl()}/rest/v1/${resource}`, { headers: headers(key), cache: "no-store" });
  if (!response.ok) return [];
  return response.json();
};
const write = async (key: string, resource: string, body: unknown, method = "POST") => {
  const response = await fetch(`${supabaseUrl()}/rest/v1/${resource}`, { method, headers: { ...headers(key), "Content-Type": "application/json", Prefer: "return=representation" }, body: JSON.stringify(body), cache: "no-store" });
  if (!response.ok) throw new Error(await response.text());
  return response.status === 204 ? null : response.json();
};

/** Read-only cross-module view: HR -> payroll -> field operations -> map. */
export async function GET() {
  const authorization = await requireCorporatePermission("dashboard.view");
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!authorization || !key) return NextResponse.json({ error: "Sessão HQ ou serviço central indisponível." }, { status: 401 });
  const [employees, payrollRuns, fieldVisits, map] = await Promise.all([
    get(key, "employees?select=id,employee_code,display_name,name,status,department_id,job_title&limit=500"),
    get(key, "payroll_runs?select=id,period_label,status,period_start,period_end,created_at&order=created_at.desc&limit=20"),
    get(key, "field_visits?select=id,subject,status,worker_id,planned_at,checked_in_at,checked_out_at,latitude,longitude,platform_id&order=created_at.desc&limit=200"),
    get(key, "rpc/hq_live_map_v1"),
  ]);
  const activeEmployees = (employees as Array<Record<string, unknown>>).filter(employee => employee.status === "active");
  const activeIds = new Set(activeEmployees.map(employee => String(employee.id)));
  const operations = (fieldVisits as Array<Record<string, unknown>>).map(operation => ({
    ...operation,
    worker: activeEmployees.find(employee => String(employee.id) === String(operation.worker_id)) || null,
    workerActive: activeIds.has(String(operation.worker_id)),
  }));
  return NextResponse.json({
    flow: { source: "hr", payroll: "finance", operations: "field", destination: "map" },
    employees: activeEmployees,
    payrollRuns,
    operations,
    map: Array.isArray(map) ? map : map?.markers || [],
    checkedAt: new Date().toISOString(),
  }, { headers: { "Cache-Control": "private, no-store" } });
}

/** Idempotent month-end test flow for HR: payroll plus worker lifecycle snapshot. */
export async function POST(request: Request) {
  const authorization = await requireCorporatePermission("hr.viewSalary");
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!authorization || !key) return NextResponse.json({ error: "Sem permissão para processar a folha." }, { status: 403 });
  const body = await request.json().catch(() => ({})) as { periodStart?: string; periodEnd?: string; label?: string };
  const periodStart = body.periodStart || new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().slice(0, 10);
  const periodEnd = body.periodEnd || new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).toISOString().slice(0, 10);
  const label = body.label || `Folha de ${periodStart.slice(0, 7)}`;
  try {
    const active = (await get(key, "employees?status=eq.active&select=id,employee_code,display_name,name,status,job_title,department_id&limit=500")) as Array<Record<string, unknown>>;
    const existing = (await get(key, `payroll_runs?period_start=eq.${periodStart}&period_end=eq.${periodEnd}&select=id,period_label,status&limit=1`))?.[0];
    const run = existing || (await write(key, "payroll_runs", { period_start: periodStart, period_end: periodEnd, period_label: label, status: "draft", idempotency_key: `month-end:${periodStart}:${periodEnd}`, prepared_by: authorization.actor.employee_id }))?.[0];
    const lines = active.map(employee => ({ payroll_run_id: run.id, employee_id: employee.id, status: "calculated" }));
    if (lines.length) await write(key, "payroll_lines?on_conflict=payroll_run_id,employee_id", lines);
    await write(key, `payroll_runs?id=eq.${encodeURIComponent(String(run.id))}`, { status: "calculated" }, "PATCH");
    const lifecycle = {
      active: active.length,
      hiring: active.filter(employee => String(employee.status) === "active").length,
      offboarding: 0,
      workers: active,
    };
    return NextResponse.json({ ok: true, period: { id: run.id, start: periodStart, end: periodEnd, label, status: "calculated" }, payrollLines: lines.length, lifecycle }, { status: existing ? 200 : 201 });
  } catch {
    return NextResponse.json({ error: "Não foi possível processar a folha do período." }, { status: 409 });
  }
}
