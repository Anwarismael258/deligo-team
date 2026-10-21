import { cookies } from "next/headers";

/** Production HQ must never silently fall back to a staging project. */
export const supabaseUrl = () => {
  const url = process.env.SUPABASE_URL?.trim();
  if (!url) throw new Error("SUPABASE_URL_NOT_CONFIGURED");
  return url.replace(/\/$/, "");
};

function hqServiceKey() {
  return process.env.SUPABASE_SECRET_KEY?.trim() || process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() || "";
}

function privilegedHeaders(serviceKey: string, extra: Record<string, string> = {}) {
  const headers: Record<string, string> = { apikey: serviceKey, "Content-Type": "application/json", ...extra };
  if (!serviceKey.startsWith("sb_secret_")) headers.Authorization = `Bearer ${serviceKey}`;
  return headers;
}

export async function corporateActor() {
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const serviceKey = hqServiceKey();
  const token = (await cookies()).get("hq_access_token")?.value;
  if (!anonKey || !serviceKey || !token) return null;
  const identity = await fetch(`${supabaseUrl()}/auth/v1/user`, { headers: { apikey: anonKey, Authorization: `Bearer ${token}` }, cache: "no-store" });
  if (!identity.ok) return null;
  const user = await identity.json() as { id: string; phone?: string | null };
  let context: Record<string, unknown> | null = null;
  try {
    context = await hqRpc("hq_actor_context_v1", { p_auth_user_id: user.id }) as Record<string, unknown> | null;
  } catch {
    context = null;
  }
  // Keep the session lookup aligned with the OTP/password login path. The
  // canonical login RPC also resolves an existing Auth identity by phone,
  // which covers older employee rows whose auth_user_id was not backfilled.
  if (!context && user.phone) {
    try {
      context = await hqRpc("hq_actor_context_for_login_v1", { p_auth_user_id: user.id, p_phone_e164: user.phone }) as Record<string, unknown> | null;
    } catch {
      context = null;
    }
  }
  if (!context || context.status !== "active") return null;
  return { authUserId: user.id, ...context } as { authUserId: string; employee_id: string; employee_code: string; name: string; role: string; status: string };
}

export type CorporateAuthorization = {actor:NonNullable<Awaited<ReturnType<typeof corporateActor>>>;permissions:string[];platformIds:string[];platformSlugs:string[];isSuperAdmin:boolean};

export async function corporateAuthorization():Promise<CorporateAuthorization|null>{
  const actor=await corporateActor();
  if(!actor)return null;
  const result=await hqRpc("hq_actor_authorization_v1",{p_employee_id:actor.employee_id}) as {permissions?:string[];platform_ids?:string[];platform_slugs?:string[];is_super_admin?:boolean};
  const isSuperAdmin=Boolean(result.is_super_admin)||actor.role==="SUPER_ADMIN";
  return{actor,permissions:isSuperAdmin?[...(result.permissions||[]),"platform.manage"]:result.permissions||[],platformIds:result.platform_ids||[],platformSlugs:result.platform_slugs||[],isSuperAdmin};
}

export async function requireCorporatePermission(permission:string,platform?:string){
  const authorization=await corporateAuthorization();
  if(!authorization||(!authorization.isSuperAdmin&&!authorization.permissions.includes(permission)))return null;
  if(platform&&!authorization.isSuperAdmin&&!authorization.platformSlugs.includes(platform)&&!authorization.platformIds.includes(platform))return null;
  return authorization;
}

export async function hqRpc(name: string, body: Record<string, unknown> = {}) {
  const serviceKey = hqServiceKey();
  if (!serviceKey) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
  const response = await fetch(`${supabaseUrl()}/rest/v1/rpc/${name}`, { method: "POST", headers: privilegedHeaders(serviceKey), body: JSON.stringify(body), cache: "no-store" });
  if (!response.ok) throw new Error((await response.text()) || "HQ_RPC_FAILED");
  return response.json();
}

export async function stagingRest(path: string, init: RequestInit = {}) {
  const serviceKey = hqServiceKey();
  if (!serviceKey) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init,
    headers: { ...privilegedHeaders(serviceKey), Prefer: "return=representation", ...(init.headers || {}) },
    cache: "no-store",
  });
  if (!response.ok) throw new Error((await response.text()) || "STAGING_REST_FAILED");
  if (response.status === 204) return null;
  return response.json();
}

export async function hqRest(path: string, init: RequestInit = {}) {
  const serviceKey = hqServiceKey();
  if (!serviceKey) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init,
    headers: { ...privilegedHeaders(serviceKey, { "Accept-Profile": "hq", "Content-Profile": "hq" }), Prefer: "return=representation", ...(init.headers || {}) },
    cache: "no-store",
  });
  if (!response.ok) throw new Error((await response.text()) || "HQ_REST_FAILED");
  return response.status === 204 ? null : response.json();
}
