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

export async function hqRpc(name: string, body: Record<string, unknown> = {}) {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
  const response = await fetch(`${supabaseUrl()}/rest/v1/rpc/${name}`, { method: "POST", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify(body), cache: "no-store" });
  if (!response.ok) throw new Error((await response.text()) || "HQ_RPC_FAILED");
  return response.json();
}
