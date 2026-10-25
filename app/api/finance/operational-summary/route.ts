import { NextResponse } from "next/server";
import { corporateAuthorization, hqServiceKey, supabaseUrl } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

const rolePermission: Record<string, string> = {
  SUPERVISOR: "operations.view",
  CUSTOMER_SUPPORT: "support.viewTickets",
  MARKETING: "marketing.view",
  FIELD: "field.view",
};

export async function GET() {
  const authorization = await corporateAuthorization();
  const role = authorization?.actor.role || "";
  const permission = rolePermission[role];
  if (!authorization || (!authorization.isSuperAdmin && (!permission || !authorization.permissions.includes(permission)))) {
    return NextResponse.json({ error: "Sem permissão para consultar o total operacional." }, { status: 403 });
  }
  const key = hqServiceKey();
  if (!key) return NextResponse.json({ error: "Fonte operacional não configurada." }, { status: 503 });
  try {
    const response = await fetch(`${supabaseUrl()}/rest/v1/rpc/financial_platform_summary_v1`, {
      method: "POST",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Accept-Profile": "hq", "Content-Profile": "hq", "Content-Type": "application/json" },
      body: "{}",
      cache: "no-store",
    });
    if (!response.ok) throw new Error("OPERATIONAL_SUMMARY_FAILED");
    const data = await response.json() as Record<string, unknown>;
    return NextResponse.json({ available: Number(data.user_wallets_available || 0), currency: "MZN", checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    return NextResponse.json({ error: "Fonte operacional temporariamente indisponível." }, { status: 503 });
  }
}
