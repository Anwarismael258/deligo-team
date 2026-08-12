import { supabaseUrl } from "./hq-server";

export type PlatformBackend = "deligo" | "comunhao" | "sarca" | "taomoz" | "mestre24";

const backendUrl = (platform: PlatformBackend) => {
  const envName = { deligo: "DELIGO_SUPABASE_URL", comunhao: "COMUNHAO_SUPABASE_URL", sarca: "SARCA_SUPABASE_URL", taomoz: "TAOMOZ_SUPABASE_URL", mestre24: "MESTRE24_SUPABASE_URL" }[platform];
  return process.env[envName] || supabaseUrl();
};

const platformKey = (platform: PlatformBackend) => process.env[`${platform.toUpperCase()}_SUPABASE_SERVICE_ROLE_KEY`] || process.env.SUPABASE_SERVICE_ROLE_KEY;

const headers = (platform: PlatformBackend, authenticatedWrite = false) => {
  const key = platformKey(platform);
  if (!key) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
  const actorToken = authenticatedWrite ? process.env[`${platform.toUpperCase()}_ADMIN_ACCESS_TOKEN`] : null;
  return { apikey: key, Authorization: `Bearer ${actorToken || key}`, "Content-Type": "application/json" };
};

const storageBuckets: Record<PlatformBackend, string[]> = { deligo: ["kyc"], comunhao: ["church-application-branding", "profile-media"], sarca: ["driver-kyc", "profile-media"], taomoz: ["kyc-documents"], mestre24: ["mestre24-kyc", "mestre24-portfolio"] };

export async function signPlatformPath(platform: PlatformBackend, path: string) {
  if (!path || /^https?:\/\//i.test(path)) return path;
  for (const bucket of storageBuckets[platform]) {
    const response = await fetch(`${backendUrl(platform)}/storage/v1/object/sign/${bucket}/${path.split("/").map(encodeURIComponent).join("/")}`, { method: "POST", headers: headers(platform), body: JSON.stringify({ expiresIn: 900 }), cache: "no-store" });
    if (response.ok) { const result = await response.json() as { signedURL?: string }; if (result.signedURL) return result.signedURL.startsWith("http") ? result.signedURL : `${backendUrl(platform)}${result.signedURL}`; }
  }
  return path;
}

export async function platformRest(platform: PlatformBackend, path: string, init: RequestInit = {}) {
  const schemaHeaders = platform === "mestre24" ? { "Accept-Profile": "mestre24", "Content-Profile": "mestre24" } : {};
  const response = await fetch(`${backendUrl(platform)}/rest/v1/${path}`, { ...init, headers: { ...headers(platform), ...schemaHeaders, ...(init.headers || {}) }, cache: "no-store" });
  if (!response.ok) throw new Error((await response.text()) || `PLATFORM_${platform.toUpperCase()}_FAILED`);
  return response.status === 204 ? null : response.json();
}

export async function platformFunction(platform: PlatformBackend, name: string, body: Record<string, unknown> = {}) {
  const response = await fetch(`${backendUrl(platform)}/functions/v1/${name}`, { method: "POST", headers: headers(platform, true), body: JSON.stringify(body), cache: "no-store" });
  if (!response.ok) throw new Error((await response.text()) || `PLATFORM_FUNCTION_${name}_FAILED`);
  return response.json();
}

export async function platformRpc(platform: PlatformBackend, name: string, body: Record<string, unknown> = {}) {
  const response = await fetch(`${backendUrl(platform)}/rest/v1/rpc/${name}`, { method: "POST", headers: headers(platform, true), body: JSON.stringify(body), cache: "no-store" });
  if (!response.ok) throw new Error((await response.text()) || `PLATFORM_RPC_${name}_FAILED`);
  return response.json();
}
