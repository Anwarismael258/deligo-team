import { NextRequest, NextResponse } from "next/server";
import { hqRest, hqRpc, supabaseUrl } from "@/lib/hq-server";

type LoginActor = { employee_id?: string; role?: string; requested_role?: string; status?: string; name?: string; employee_code?: string };

async function lookupActor(authUserId: string | undefined, phone: string): Promise<LoginActor | null> {
  if (!authUserId) return null;
  try {
    const rpc = await hqRpc("hq_actor_context_for_login_v1", { p_auth_user_id: authUserId, p_phone_e164: phone });
    const actor = (Array.isArray(rpc) ? rpc[0] : rpc) as LoginActor | null;
    if (actor) return actor;
  } catch (error) {
    console.error("HQ_LOGIN_ACTOR_RPC_FAILED", error instanceof Error ? error.message : "unknown");
  }

  // Keep password login usable if the optional login RPC is unavailable or
  // slow. PostgREST still applies the service-role boundary and the employee
  // row must be active/invited and match the authenticated identity/phone.
  try {
    const fields = "id,employee_code,display_name,status,role,requested_role,auth_user_id,phone_e164";
    const byAuth = await hqRest(`employees?auth_user_id=eq.${encodeURIComponent(authUserId)}&status=in.(active,invited)&select=${fields}&limit=1`) as Array<Record<string, unknown>>;
    const row = byAuth?.[0] || (await hqRest(`employees?phone_e164=eq.${encodeURIComponent(phone)}&status=in.(active,invited)&select=${fields}&limit=1`) as Array<Record<string, unknown>>)?.[0];
    if (!row) return null;
    return {
      employee_id: String(row.id), employee_code: String(row.employee_code || ""),
      name: String(row.display_name || ""), role: String(row.role || row.requested_role || ""),
      requested_role: row.requested_role ? String(row.requested_role) : undefined,
      status: String(row.status || ""),
    };
  } catch (error) {
    console.error("HQ_LOGIN_ACTOR_REST_FALLBACK_FAILED", error instanceof Error ? error.message : "unknown");
    return null;
  }
}

export async function POST(request: NextRequest) {
  const anonKey = process.env.SUPABASE_ANON_KEY;
  if (!anonKey || !process.env.SUPABASE_URL) return NextResponse.json({ error: "Autenticação não configurada." }, { status: 503 });
  const { phone, password } = await request.json() as { phone?: string; password?: string };
  if (!phone || !password) return NextResponse.json({ error: "Telefone e palavra-passe são obrigatórios." }, { status: 400 });
  const digits = phone.replace(/\D/g, "");
  const normalizedPhone = digits.startsWith("258") ? `+${digits}` : `+258${digits.replace(/^0/, "")}`;
  if (!/^\+258\d{9}$/.test(normalizedPhone)) return NextResponse.json({ error: "Introduza um número moçambicano válido." }, { status: 400 });

  let authResponse: Response;
  try {
    authResponse = await fetch(`${supabaseUrl()}/auth/v1/token?grant_type=password`, {
      method: "POST", headers: { apikey: anonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ phone: normalizedPhone, password }), cache: "no-store",
      signal: AbortSignal.timeout(12000),
    });
  } catch (error) {
    console.error("HQ_LOGIN_AUTH_REQUEST_FAILED", error instanceof Error ? error.message : "unknown");
    return NextResponse.json({ error: "Não foi possível contactar o serviço de autenticação. Tente novamente." }, { status: 503 });
  }
  const payload = await authResponse.json() as { access_token?: string; refresh_token?: string; expires_in?: number; user?: { email?: string; user_metadata?: Record<string, unknown> }; error_description?: string; msg?: string };
  if (authResponse.status >= 500) {
    console.error("HQ_LOGIN_AUTH_UPSTREAM_UNAVAILABLE", { status: authResponse.status });
    return NextResponse.json({ error: "O serviço de autenticação está temporariamente indisponível. Tente novamente em alguns minutos." }, { status: 503 });
  }
  if (!authResponse.ok || !payload.access_token || !payload.refresh_token) {
    return NextResponse.json({ error: "Telefone ou palavra-passe inválidos." }, { status: 401 });
  }
  const authUserId = (payload as { user?: { id?: string } }).user?.id;
  let actor: LoginActor | null = await lookupActor(authUserId, normalizedPhone);
  const actorStatus = String(actor?.status || "").toLowerCase();
  // The first-access flow sets the Auth metadata flag to false only after the
  // worker has verified OTP and created a personal password. If the separate
  // activation update was interrupted, finish that state transition here.
  // Never activate an invited account while it still has the bootstrap flag.
  if (actorStatus === "invited" && payload.user?.user_metadata?.must_set_password === false && authUserId) {
    try {
      const activated = await hqRest(`employees?id=eq.${encodeURIComponent(String((actor as { employee_id?: string }).employee_id))}&status=eq.invited`, {
        method: "PATCH",
        body: JSON.stringify({ status: "active", last_login_at: new Date().toISOString() }),
      }) as Array<Record<string, unknown>>;
      if (activated?.length) actor = { ...actor, status: "active" };
    } catch (error) {
      console.error("HQ_LOGIN_ACTIVATION_FAILED", error instanceof Error ? error.message : "unknown");
    }
  }
  if (!actor || String(actor.status || "").toLowerCase() !== "active") return NextResponse.json({ error: actorStatus === "suspended" ? "Esta conta está suspensa." : "Conclua o primeiro acesso por OTP e defina a sua senha pessoal antes de entrar." }, { status: 403 });
  const response = NextResponse.json({ user: { email: payload.user?.email, ...payload.user?.user_metadata, hq_role: (actor as { role?: string }).role } });
  const secure = request.nextUrl.protocol === "https:";
  response.cookies.set("hq_access_token", payload.access_token, { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: payload.expires_in || 3600 });
  response.cookies.set("hq_refresh_token", payload.refresh_token, { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: 60 * 60 * 24 * 7 });
  return response;
}
