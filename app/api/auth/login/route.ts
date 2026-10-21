import { NextRequest, NextResponse } from "next/server";
import { hqRpc, supabaseUrl } from "@/lib/hq-server";

export async function POST(request: NextRequest) {
  const anonKey = process.env.SUPABASE_ANON_KEY;
  if (!anonKey || !process.env.SUPABASE_URL) return NextResponse.json({ error: "Autenticação não configurada." }, { status: 503 });
  const { phone, password } = await request.json() as { phone?: string; password?: string };
  if (!phone || !password) return NextResponse.json({ error: "Telefone e palavra-passe são obrigatórios." }, { status: 400 });
  const digits = phone.replace(/\D/g, "");
  const normalizedPhone = digits.startsWith("258") ? `+${digits}` : `+258${digits.replace(/^0/, "")}`;
  if (!/^\+258\d{9}$/.test(normalizedPhone)) return NextResponse.json({ error: "Introduza um número moçambicano válido." }, { status: 400 });

  const authResponse = await fetch(`${supabaseUrl()}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ phone: normalizedPhone, password }), cache: "no-store",
  });
  const payload = await authResponse.json() as { access_token?: string; refresh_token?: string; expires_in?: number; user?: { email?: string; user_metadata?: Record<string, unknown> }; error_description?: string; msg?: string };
  if (!authResponse.ok || !payload.access_token || !payload.refresh_token) {
    return NextResponse.json({ error: "Telefone ou palavra-passe inválidos." }, { status: 401 });
  }
  const authUserId = (payload as { user?: { id?: string } }).user?.id;
  let actor: { status?: string } | null = null;
  try {
    actor = authUserId
      ? await hqRpc("hq_actor_context_for_login_v1", { p_auth_user_id: authUserId, p_phone_e164: normalizedPhone })
      : null;
  } catch (error) {
    console.error("HQ_LOGIN_ACTOR_LOOKUP_FAILED", error instanceof Error ? error.message : "unknown");
    return NextResponse.json({ error: "Não foi possível validar o acesso corporativo. Contacte a Administração." }, { status: 503 });
  }
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
