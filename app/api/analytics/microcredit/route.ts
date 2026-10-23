import { NextRequest, NextResponse } from "next/server";
import { corporateActor, stagingRest } from "@/lib/hq-server";

export const dynamic = "force-dynamic";
type Row = Record<string, unknown>;
type Period = "last_7_days" | "last_30_days" | "last_90_days" | "custom";
const staff = new Set(["SUPER_ADMIN", "FINANCE"]);
const dayMs = 86_400_000;
const dateOnly = (value: unknown) => typeof value === "string" ? value.slice(0, 10) : "";
const maputoDate = (date: Date) => new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Maputo", year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
const start = (date: string) => new Date(`${date}T00:00:00+02:00`);
const validDate = (value: string | null) => value && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
const range = (period: Period, from: string | null, to: string | null) => { const today = maputoDate(new Date()); const days = period === "last_7_days" ? 7 : period === "last_90_days" ? 90 : 30; if (period === "custom" && from && to) return { from, to, days: Math.max(1, Math.round((start(to).getTime() - start(from).getTime()) / dayMs) + 1) }; return { from: maputoDate(new Date(start(today).getTime() - (days - 1) * dayMs)), to: today, days }; };
const inRange = (value: unknown, current: { from: string; to: string }) => { const date = dateOnly(value); return Boolean(date && date >= current.from && date <= current.to); };
const countBy = (rows: Row[], getter: (row: Row) => string) => { const map = new Map<string, number>(); rows.forEach(row => { const key = getter(row) || "Não indicado"; map.set(key, (map.get(key) || 0) + 1); }); return [...map.entries()].map(([label, value]) => ({ label, value })); };
const moneySum = (rows: Row[], key: string) => { const values = rows.map(row => Number(row[key])).filter(Number.isFinite); return values.length ? Number(values.reduce((sum, value) => sum + value, 0).toFixed(2)) : null; };
const metric = (id: string, label: string, value: number | null, unit: string, source: string, formula: string) => ({ id, label, value, unit, source, formula, status: value == null ? "unavailable" : "fresh" });
async function read(path: string) { try { const rows = await stagingRest(path) as Row[]; return Array.isArray(rows) ? rows : []; } catch { return []; } }
function series(current: { from: string; to: string }, rows: Row[], dateKey: string) { const points = new Map<string, number>(); for (let cursor = start(current.from); cursor <= start(current.to); cursor = new Date(cursor.getTime() + dayMs)) points.set(maputoDate(cursor), 0); rows.forEach(row => { const date = dateOnly(row[dateKey]); if (points.has(date)) points.set(date, (points.get(date) || 0) + 1); }); return [...points.entries()].map(([date, value]) => ({ date, value })); }

export async function GET(request: NextRequest) {
  const currentActor = await corporateActor();
  if (!currentActor || !staff.has(currentActor.role)) return NextResponse.json({ error: "Sem acesso ao analytics de microcrédito." }, { status: 403 });
  const query = request.nextUrl.searchParams; const periodParam = query.get("period"); const period = (["last_7_days", "last_30_days", "last_90_days", "custom"].includes(periodParam || "") ? periodParam : "last_30_days") as Period; const periodRange = range(period, validDate(query.get("from")), validDate(query.get("to"))); const status = (query.get("status") || "").toLowerCase(); const loanType = (query.get("loan_type") || query.get("type") || "").toLowerCase(); const collateralType = (query.get("collateral_type") || "").toLowerCase();
  try {
    const [applications, contracts, disbursements, repayments, collaterals, history] = await Promise.all([
      read("loan_applications?select=*&order=created_at.desc&limit=3000"),
      read("loan_contracts?select=*&limit=3000"),
      read("loan_disbursements?select=*&limit=3000"),
      read("loan_repayments?select=*&limit=5000"),
      read("loan_collaterals?select=*&limit=3000"),
      read("loan_application_history?select=*&limit=5000"),
    ]);
    const filtered = applications.filter(row => (!status || String(row.status || "").toLowerCase() === status) && (!loanType || String(row.loan_type || row.product_type || row.type || "").toLowerCase() === loanType));
    const currentApplications = filtered.filter(row => inRange(row.created_at, periodRange));
    const approved = filtered.filter(row => ["aprovado", "approved"].includes(String(row.status || "").toLowerCase()));
    const rejected = filtered.filter(row => ["recusado", "rejected"].includes(String(row.status || "").toLowerCase()));
    const analysis = filtered.filter(row => ["em_analise", "in_review", "under_review", "pending", "pendente"].includes(String(row.status || "").toLowerCase()));
    const activeContracts = contracts.filter(row => ["active", "ativo", "open"].includes(String(row.status || "").toLowerCase()));
    const selectedCollaterals = collaterals.filter(row => !collateralType || String(row.type || row.collateral_type || "").toLowerCase() === collateralType);
    const confirmedDisbursements = disbursements.filter(row => ["confirmed", "completed", "paid", "desembolsado"].includes(String(row.status || "").toLowerCase()));
    const confirmedRepayments = repayments.filter(row => ["confirmed", "completed", "paid", "pago"].includes(String(row.status || "").toLowerCase()));
    const overdueRepayments = repayments.filter(row => { const due = row.due_at || row.due_date; return due && new Date(String(due)).getTime() < Date.now() && !["confirmed", "completed", "paid", "pago"].includes(String(row.status || "").toLowerCase()); });
    const kpis = [
      metric("received", "Pedidos recebidos", currentApplications.length, "count", "loan_applications", "created_at no período"),
      metric("analysis", "Pedidos em análise", analysis.length, "count", "loan_applications", "estado de análise"),
      metric("approved", "Pedidos aprovados", approved.length, "count", "loan_applications", "status aprovado"),
      metric("rejected", "Pedidos rejeitados", rejected.length, "count", "loan_applications", "status recusado"),
      metric("active_contracts", "Contratos ativos", contracts.length ? activeContracts.length : null, "count", contracts.length ? "loan_contracts" : "indisponível", "status ativo"),
      metric("disbursed", "Montante desembolsado", confirmedDisbursements.length ? moneySum(confirmedDisbursements, "amount") : null, "MZN", disbursements.length ? "loan_disbursements" : "indisponível", "pagamentos confirmados"),
      metric("recovered", "Montante recuperado", confirmedRepayments.length ? moneySum(confirmedRepayments, "amount") : null, "MZN", repayments.length ? "loan_repayments" : "indisponível", "pagamentos confirmados"),
      metric("overdue", "Pagamentos vencidos", repayments.length ? moneySum(overdueRepayments, "amount") : null, "MZN", repayments.length ? "loan_repayments" : "indisponível", "vencido e não confirmado"),
      metric("collaterals", "Garantias registadas", collaterals.length ? selectedCollaterals.length : null, "count", collaterals.length ? "loan_collaterals" : "indisponível", "registos de garantia"),
    ];
    return NextResponse.json({ timezone: "Africa/Maputo", period, range: periodRange, data: { kpis, requestedAmount: moneySum(currentApplications, "amount"), byStatus: countBy(filtered, row => String(row.status || "não indicado")), byLoanType: countBy(filtered, row => String(row.loan_type || row.product_type || row.type || "não indicado")), byCollateralType: countBy(selectedCollaterals, row => String(row.type || row.collateral_type || "não indicado")), applicationsSeries: series(periodRange, filtered, "created_at"), disbursementSeries: series(periodRange, confirmedDisbursements, "created_at"), repaymentSeries: series(periodRange, confirmedRepayments, "created_at"), overdue: overdueRepayments.length ? { count: overdueRepayments.length, amount: moneySum(overdueRepayments, "amount") } : null }, sources: { applications: "staging.loan_applications", deliveries: "staging.loan_application_deliveries (PDF/WhatsApp; não é pagamento)", contracts: contracts.length ? "staging.loan_contracts" : "indisponível nesta instalação", disbursements: disbursements.length ? "staging.loan_disbursements" : "indisponível nesta instalação", repayments: repayments.length ? "staging.loan_repayments" : "indisponível nesta instalação", collaterals: collaterals.length ? "staging.loan_collaterals" : "indisponível nesta instalação", history: history.length ? "staging.loan_application_history" : "indisponível nesta instalação" }, limitations: ["Pedidos aprovados não são tratados como desembolsos.", "Contratos, desembolsos, pagamentos, garantias e histórico só são apresentados quando as fontes correspondentes existem e têm registos.", "Não há pontuação de risco pessoal nem decisão automática de crédito."] }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Analytics de microcrédito indisponível." }, { status: 502 }); }
}
