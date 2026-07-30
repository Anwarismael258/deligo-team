import { cookies } from "next/headers";
import { NextResponse } from "next/server";

const STAGING_URL = "https://tpmsgvkdjzoidvyiwwfk.supabase.co";

export async function GET() {
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const token = (await cookies()).get("hq_access_token")?.value;
  if (!anonKey || !token) return NextResponse.json({ authenticated: false }, { status: 401 });
  const response = await fetch(`${process.env.SUPABASE_URL || STAGING_URL}/auth/v1/user`, { headers: { apikey: anonKey, Authorization: `Bearer ${token}` }, cache: "no-store" });
  if (!response.ok) return NextResponse.json({ authenticated: false }, { status: 401 });
  const user = await response.json() as { email?: string; user_metadata?: Record<string, unknown> };
  return NextResponse.json({ authenticated: true, user: { email: user.email, ...user.user_metadata } }, { headers: { "Cache-Control": "private, no-store" } });
}
