import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { deligoTriunfalGovernance } from "@/lib/governance";
import { corporateActor } from "@/lib/hq-server";

export const dynamic = "force-dynamic";
const STAGING_URL = "https://tpmsgvkdjzoidvyiwwfk.supabase.co";

export async function GET() {
  const accessToken = (await cookies()).get("hq_access_token")?.value;
  if (!accessToken) return NextResponse.json({ error: "Sessão corporativa necessária." }, { status: 401 });
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) {
    return NextResponse.json({ error: "A integração de staging não está configurada neste ambiente." }, { status: 503 });
  }

  try {
    const actor = await corporateActor();
    if (!actor) return NextResponse.json({ error: "Sessão inválida, suspensa ou expirada." }, { status: 401 });
    const rpcHeaders = {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      };
    const [dashboardResponse, modulesResponse, mestre24Response] = await Promise.all([
      fetch(`${STAGING_URL}/rest/v1/rpc/hq_dashboard_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${STAGING_URL}/rest/v1/rpc/hq_platform_modules_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${STAGING_URL}/rest/v1/rpc/hq_mestre24_module_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
    ]);
    if (!dashboardResponse.ok || !modulesResponse.ok || !mestre24Response.ok) {
      console.error("HQ staging RPC failed", dashboardResponse.status, modulesResponse.status, mestre24Response.status);
      return NextResponse.json({ error: "O backend de staging não respondeu correctamente." }, { status: 502 });
    }
    const executiveResponse = actor.role === "SUPER_ADMIN" ? await fetch(`${process.env.SUPABASE_URL || STAGING_URL}/rest/v1/rpc/hq_executive_governance_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store" }) : null;
    const [dashboard, modules, mestre24, executive] = await Promise.all([dashboardResponse.json(), modulesResponse.json(), mestre24Response.json(), executiveResponse?.ok ? executiveResponse.json() : Promise.resolve(null)]) as [Record<string, unknown>, Record<string, unknown>, { platform: Record<string, unknown>; module: Record<string, unknown> }, unknown];
    const dashboardPlatforms = Array.isArray(dashboard.platforms) ? dashboard.platforms : [];
    const modulePlatforms = Array.isArray(modules.platforms) ? modules.platforms : [];
    const totalValue = Number(modules.totalValue || 0) + Number(mestre24.module.value || 0);
    const mergedModules = { ...modules, totalValue, platforms: [...modulePlatforms, mestre24.module] };
    return NextResponse.json({ ...dashboard, platforms: [...dashboardPlatforms, mestre24.platform], modules: mergedModules, governance: actor.role === "SUPER_ADMIN" ? deligoTriunfalGovernance : null, executive }, {
      headers: { "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" },
    });
  } catch (error) {
    console.error("HQ staging connection failed", error);
    return NextResponse.json({ error: "Não foi possível ligar ao backend de staging." }, { status: 502 });
  }
}
