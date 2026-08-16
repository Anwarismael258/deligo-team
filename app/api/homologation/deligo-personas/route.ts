import { NextRequest, NextResponse } from "next/server";
import { supabaseUrl } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

/**
 * Proxies the current HQ session to the staging-only provisioning function.
 * The access token stays HTTP-only and the Edge Function is the authoritative
 * Super Admin verifier. Keeping this check in one place avoids a stale HQ
 * permission projection denying a valid corporate session.
 */
export async function POST(request: NextRequest) {
  const testPassword = String((await request.json().catch(() => ({})) as { testPassword?: unknown }).testPassword ?? "");
  if (testPassword.length < 8) {
    return NextResponse.json({ error: "Defina uma palavra-passe de teste com pelo menos 8 caracteres." }, { status: 400 });
  }

  const token = request.cookies.get("hq_access_token")?.value;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  if (!token || !anonKey) return NextResponse.json({ error: "A sessão de homologação expirou. Entre novamente." }, { status: 401 });

  const response = await fetch(`${supabaseUrl()}/functions/v1/hq-provision-deligo-test-personas`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ test_password: testPassword }),
    cache: "no-store",
  });
  const payload = await response.json().catch(() => ({ error: "Resposta inválida da homologação." }));
  return NextResponse.json(payload, { status: response.status, headers: { "Cache-Control": "private, no-store" } });
}
