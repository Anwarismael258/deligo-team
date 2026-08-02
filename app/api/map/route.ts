import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { corporateActor } from "@/lib/hq-server";

export const dynamic = "force-dynamic";
const STAGING_URL = "https://tpmsgvkdjzoidvyiwwfk.supabase.co";

export async function GET() {
  if (!(await cookies()).get("hq_access_token")?.value || !(await corporateActor())) {
    return NextResponse.json({ error: "Sessão corporativa necessária." }, { status: 401 });
  }

  const anonKey = process.env.SUPABASE_ANON_KEY;
  const integrationSecret = process.env.DELIGO_STAGING_DB_PASSWORD;
  if (!anonKey || !integrationSecret) {
    return NextResponse.json({ error: "A integração de localização não está configurada." }, { status: 503 });
  }

  const response = await fetch(`${process.env.SUPABASE_URL || STAGING_URL}/rest/v1/rpc/hq_live_map_v1`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}`, "Content-Type": "application/json", "x-hq-integration-secret": integrationSecret },
    body: "{}",
    cache: "no-store",
    signal: AbortSignal.timeout(12_000),
  });
  if (!response.ok) return NextResponse.json({ error: "Não foi possível actualizar o mapa operacional." }, { status: 502 });
  return NextResponse.json(await response.json(), { headers: { "Cache-Control": "private, no-store" } });
}
