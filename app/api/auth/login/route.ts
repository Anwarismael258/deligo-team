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
  if (!actor || actor.status !== "active") return NextResponse.json({ error: actor?.status === "suspended" ? "Esta conta está suspensa." : "A conta não está associada a um funcionário activo. Contacte o Super Administrador." }, { status: 403 });
  const response = NextResponse.json({ user: { email: payload.user?.email, ...payload.user?.user_metadata } });
  const secure = request.nextUrl.protocol === "https:";
  response.cookies.set("hq_access_token", payload.access_token, { httpOnly: true, secure, sameSite: "strict", path: "/", maxAge: payload.expires_in || 3600 });
  response.cookies.set("hq_refresh_token", payload.refresh_token, { httpOnly: true, secure, sameSite: "strict", path: "/", maxAge: 60 * 60 * 24 * 7 });
  return response;
}
