import { NextRequest, NextResponse } from "next/server";

const STAGING_URL = "https://tpmsgvkdjzoidvyiwwfk.supabase.co";

export async function POST(request: NextRequest) {
  const anonKey = process.env.SUPABASE_ANON_KEY;
  if (!anonKey) return NextResponse.json({ error: "Autenticação de staging não configurada." }, { status: 503 });
  const { email, password } = await request.json() as { email?: string; password?: string };
  if (!email || !password) return NextResponse.json({ error: "Email e palavra-passe são obrigatórios." }, { status: 400 });

  const authResponse = await fetch(`${process.env.SUPABASE_URL || STAGING_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email: email.trim().toLowerCase(), password }), cache: "no-store",
  });
  const payload = await authResponse.json() as { access_token?: string; refresh_token?: string; expires_in?: number; user?: { email?: string; user_metadata?: Record<string, unknown> }; error_description?: string; msg?: string };
  if (!authResponse.ok || !payload.access_token || !payload.refresh_token) {
    return NextResponse.json({ error: "Email ou palavra-passe inválidos." }, { status: 401 });
  }
  const response = NextResponse.json({ user: { email: payload.user?.email, ...payload.user?.user_metadata } });
  const secure = process.env.NODE_ENV === "production";
  response.cookies.set("hq_access_token", payload.access_token, { httpOnly: true, secure, sameSite: "strict", path: "/", maxAge: payload.expires_in || 3600 });
  response.cookies.set("hq_refresh_token", payload.refresh_token, { httpOnly: true, secure, sameSite: "strict", path: "/", maxAge: 60 * 60 * 24 * 7 });
  return response;
}
