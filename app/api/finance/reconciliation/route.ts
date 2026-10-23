import { NextResponse } from "next/server";
import { requireCorporatePermission, hqServiceKey, supabaseUrl } from "@/lib/hq-server";
import { metricDefinition } from "@/lib/metric-registry";

export const dynamic = "force-dynamic";

const headersFor = (key: string): Record<string, string> => {
  const headers: Record<string, string> = { apikey: key, "Content-Type": "application/json", "Accept-Profile": "hq", "Content-Profile": "hq" };
  if (!key.startsWith("sb_secret_")) headers.Authorization = `Bearer ${key}`;
  return headers;
};

async function rpc(key: string, name: string) {
  const response = await fetch(`${supabaseUrl()}/rest/v1/rpc/${name}`, { method: "POST", headers: headersFor(key), body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) });
  return { ok: response.ok, value: response.ok ? await response.json() : null };
}

export async function GET() {
  const authorization = await requireCorporatePermission("finance.view");
  const actor = authorization?.actor;
  const key = hqServiceKey();
  if (!actor || !key || !["SUPER_ADMIN", "FINANCE", "FINANCE_DIRECTOR"].includes(actor.role)) return NextResponse.json({ error: "Sem acesso à auditoria financeira." }, { status: 403 });

  const [platformSummary, revenueSummary] = await Promise.all([
    rpc(key, "financial_platform_summary_v1"),
    rpc(key, "corporate_revenue_summary_v1"),
  ]);
  const platform = platformSummary.value && typeof platformSummary.value === "object" ? platformSummary.value as Record<string, unknown> : {};
  const revenue = revenueSummary.value && typeof revenueSummary.value === "object" ? revenueSummary.value as Record<string, unknown> : {};
  const definitions = ["finance.corporate_revenue_confirmed", "finance.user_wallets_available", "finance.corporate_wallet_available", "finance.custody_available"]
    .map(key => metricDefinition(key)).filter(Boolean);
  const sources = [
    { key: "finance.corporate_revenue_confirmed", label: definitions.find(metric => metric?.key === "finance.corporate_revenue_confirmed")?.label, value: Number(revenue.corporate_revenue_confirmed ?? platform.central_revenue_confirmed ?? 0), source: definitions.find(metric => metric?.key === "finance.corporate_revenue_confirmed")?.source, status: revenueSummary.ok ? "confirmed" : "unavailable" },
    { key: "finance.user_wallets_available", label: definitions.find(metric => metric?.key === "finance.user_wallets_available")?.label, value: Number(platform.user_wallets_available ?? 0), source: definitions.find(metric => metric?.key === "finance.user_wallets_available")?.source, status: platformSummary.ok ? "confirmed" : "unavailable" },
    { key: "finance.corporate_wallet_available", label: definitions.find(metric => metric?.key === "finance.corporate_wallet_available")?.label, value: Number(platform.corporate_wallet_available ?? revenue.corporate_wallet_available ?? 0), source: definitions.find(metric => metric?.key === "finance.corporate_wallet_available")?.source, status: platformSummary.ok || revenueSummary.ok ? "confirmed" : "unavailable" },
    { key: "finance.custody_available", label: definitions.find(metric => metric?.key === "finance.custody_available")?.label, value: Number(platform.total_funds_controlled_available ?? 0), source: definitions.find(metric => metric?.key === "finance.custody_available")?.source, status: platformSummary.ok ? "confirmed" : "unavailable" },
    { key: "finance.legacy_unclassified", label: "Movimentos antigos não classificados", value: Number(revenue.legacy_unclassified_revenue ?? platform.unclassified_legacy_corporate_amount ?? 0), source: "hq.ledger_operations", status: "excluded_from_revenue" },
  ];
  const allSourcesAvailable = platformSummary.ok && revenueSummary.ok;
  return NextResponse.json({ checkedAt: new Date().toISOString(), state: allSourcesAvailable ? "READ_ONLY_RECONCILIATION_READY" : "SOURCE_UNAVAILABLE", actor: { employeeId: actor.employee_id, role: actor.role }, sources, paysuite: { state: "NOT_VERIFIED", reason: "A API de saldo PaySuite não foi assumida sem endpoint oficial de leitura configurado." }, warnings: ["Esta auditoria não altera saldos, não cria movimentos e não executa levantamentos.", "PaySuite só poderá ser reconciliada quando existir uma resposta oficial de saldo autenticada."] }, { headers: { "Cache-Control": "private, no-store" } });
}
