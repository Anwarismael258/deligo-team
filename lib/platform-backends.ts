import { supabaseUrl } from "./hq-server";

export type PlatformBackend = "deligo" | "comunhao" | "sarca" | "taomoz";

const backendUrl = (platform: PlatformBackend) => {
  const envName = { deligo: "DELIGO_SUPABASE_URL", comunhao: "COMUNHAO_SUPABASE_URL", sarca: "SARCA_SUPABASE_URL", taomoz: "TAOMOZ_SUPABASE_URL" }[platform];
  return process.env[envName] || supabaseUrl();
};

const headers = () => {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
  return { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
};

export async function platformRest(platform: PlatformBackend, path: string, init: RequestInit = {}) {
  const response = await fetch(`${backendUrl(platform)}/rest/v1/${path}`, { ...init, headers: { ...headers(), ...(init.headers || {}) }, cache: "no-store" });
  if (!response.ok) throw new Error((await response.text()) || `PLATFORM_${platform.toUpperCase()}_FAILED`);
  return response.status === 204 ? null : response.json();
}

export async function platformFunction(platform: PlatformBackend, name: string, body: Record<string, unknown> = {}) {
  const response = await fetch(`${backendUrl(platform)}/functions/v1/${name}`, { method: "POST", headers: headers(), body: JSON.stringify(body), cache: "no-store" });
  if (!response.ok) throw new Error((await response.text()) || `PLATFORM_FUNCTION_${name}_FAILED`);
  return response.json();
}

export async function platformRpc(platform: PlatformBackend, name: string, body: Record<string, unknown> = {}) {
  const response = await fetch(`${backendUrl(platform)}/rest/v1/rpc/${name}`, { method: "POST", headers: headers(), body: JSON.stringify(body), cache: "no-store" });
  if (!response.ok) throw new Error((await response.text()) || `PLATFORM_RPC_${name}_FAILED`);
  return response.json();
}
