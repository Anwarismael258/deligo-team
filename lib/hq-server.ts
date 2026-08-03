import { cookies } from "next/headers";

const STAGING_URL = "https://tpmsgvkdjzoidvyiwwfk.supabase.co";
export const supabaseUrl = () => process.env.SUPABASE_URL || STAGING_URL;

export async function corporateActor() {
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const token = (await cookies()).get("hq_access_token")?.value;
  if (!anonKey || !serviceKey || !token) return null;
  const identity = await fetch(`${supabaseUrl()}/auth/v1/user`, { headers: { apikey: anonKey, Authorization: `Bearer ${token}` }, cache: "no-store" });
  if (!identity.ok) return null;
  const user = await identity.json() as { id: string };
  const context = await hqRpc("hq_actor_context_v1", { p_auth_user_id: user.id });
  if (!context || context.status !== "active") return null;
  return { authUserId: user.id, ...context } as { authUserId: string; employee_id: string; employee_code: string; name: string; role: string; status: string };
}

export type CorporateAuthorization = {actor:NonNullable<Awaited<ReturnType<typeof corporateActor>>>;permissions:string[];platformIds:string[];platformSlugs:string[];isSuperAdmin:boolean};

export async function corporateAuthorization():Promise<CorporateAuthorization|null>{
  const actor=await corporateActor();
  if(!actor)return null;
  const result=await hqRpc("hq_actor_authorization_v1",{p_employee_id:actor.employee_id}) as {permissions?:string[];platform_ids?:string[];platform_slugs?:string[];is_super_admin?:boolean};
  return{actor,permissions:result.permissions||[],platformIds:result.platform_ids||[],platformSlugs:result.platform_slugs||[],isSuperAdmin:Boolean(result.is_super_admin)};
}

export async function requireCorporatePermission(permission:string,platform?:string){
  const authorization=await corporateAuthorization();
  if(!authorization||(!authorization.isSuperAdmin&&!authorization.permissions.includes(permission)))return null;
  if(platform&&!authorization.isSuperAdmin&&!authorization.platformSlugs.includes(platform)&&!authorization.platformIds.includes(platform))return null;
  return authorization;
}

export async function hqRpc(name: string, body: Record<string, unknown> = {}) {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
  const response = await fetch(`${supabaseUrl()}/rest/v1/rpc/${name}`, { method: "POST", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify(body), cache: "no-store" });
  if (!response.ok) throw new Error((await response.text()) || "HQ_RPC_FAILED");
  return response.json();
}

export async function stagingRest(path: string, init: RequestInit = {}) {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json", Prefer: "return=representation", ...(init.headers || {}) },
    cache: "no-store",
  });
  if (!response.ok) throw new Error((await response.text()) || "STAGING_REST_FAILED");
  if (response.status === 204) return null;
  return response.json();
}
