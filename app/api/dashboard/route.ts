import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";
const STAGING_URL = "https://tpmsgvkdjzoidvyiwwfk.supabase.co";

export async function GET() {
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const integrationSecret = process.env.DELIGO_STAGING_DB_PASSWORD;
  if (!anonKey || !integrationSecret) {
    return NextResponse.json({ error: "A integração de staging não está configurada neste ambiente." }, { status: 503 });
  }

  try {
    const rpcHeaders = {
        apikey: anonKey,
        Authorization: `Bearer ${anonKey}`,
        "Content-Type": "application/json",
        "x-hq-integration-secret": integrationSecret,
      };
    const [dashboardResponse, modulesResponse] = await Promise.all([
      fetch(`${process.env.SUPABASE_URL || STAGING_URL}/rest/v1/rpc/hq_dashboard_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${process.env.SUPABASE_URL || STAGING_URL}/rest/v1/rpc/hq_platform_modules_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
    ]);
    if (!dashboardResponse.ok || !modulesResponse.ok) {
      console.error("HQ staging RPC failed", dashboardResponse.status, modulesResponse.status);
      return NextResponse.json({ error: "O backend de staging não respondeu correctamente." }, { status: 502 });
    }
    const [dashboard, modules] = await Promise.all([dashboardResponse.json(), modulesResponse.json()]);
    return NextResponse.json({ ...dashboard, modules }, {
      headers: { "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" },
    });
  } catch (error) {
    console.error("HQ staging connection failed", error);
    return NextResponse.json({ error: "Não foi possível ligar ao backend de staging." }, { status: 502 });
  }
}
