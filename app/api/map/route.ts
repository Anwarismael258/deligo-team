import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { corporateActor } from "@/lib/hq-server";

export const dynamic = "force-dynamic";
const STAGING_URL = "https://tpmsgvkdjzoidvyiwwfk.supabase.co";

export async function GET() {
  if (!(await cookies()).get("hq_access_token")?.value || !(await corporateActor())) {
    return NextResponse.json({ error: "Sessao corporativa necessaria." }, { status: 401 });
  }

  const anonKey = process.env.SUPABASE_ANON_KEY;
  const integrationSecret = process.env.DELIGO_STAGING_DB_PASSWORD;
  if (!anonKey || !integrationSecret) {
    return NextResponse.json({ error: "Integracao de localizacao nao configurada." }, { status: 503 });
  }

  try {
    const response = await fetch(`${process.env.SUPABASE_URL || STAGING_URL}/rest/v1/rpc/hq_live_map_v1`, {
      method: "POST",
      headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}`, "Content-Type": "application/json", "x-hq-integration-secret": integrationSecret },
      body: "{}",
      cache: "no-store",
      signal: AbortSignal.timeout(12_000),
    });
    if (!response.ok) throw new Error(`HQ_MAP_RPC_${response.status}`);
    return NextResponse.json(await response.json(), { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    // Live location is privacy-protected and optional. A stalled adapter must
    // not make the whole Central appear unavailable.
    return NextResponse.json({ checkedAt: new Date().toISOString(), markers: [] }, { headers: { "Cache-Control": "private, no-store" } });
  }
}
