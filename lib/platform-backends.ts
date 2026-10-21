import { supabaseUrl } from "./hq-server";

export type PlatformBackend = "deligo" | "comunhao" | "sarca" | "taomoz" | "mestre24";

const backendUrl = (platform: PlatformBackend) => {
  const envName = { deligo: "DELIGO_SUPABASE_URL", comunhao: "COMUNHAO_SUPABASE_URL", sarca: "SARCA_SUPABASE_URL", taomoz: "TAOMOZ_SUPABASE_URL", mestre24: "MESTRE24_SUPABASE_URL" }[platform];
  // Mestre24 is currently hosted in the same Supabase project as the HQ.
  // Keep platform-specific URLs supported, but do not hide the schema when
  // its optional dedicated URL is not configured.
  const url = process.env[envName]?.trim() || process.env.SUPABASE_URL?.trim() || "";
  if (!url) throw new Error(`PLATFORM_${platform.toUpperCase()}_URL_NOT_CONFIGURED`);
  return url.replace(/\/$/, "");
};

const platformKey = (platform: PlatformBackend) => process.env[`${platform.toUpperCase()}_SUPABASE_SERVICE_ROLE_KEY`]?.trim() || process.env[`${platform.toUpperCase()}_SUPABASE_SECRET_KEY`]?.trim() || process.env.SUPABASE_SECRET_KEY?.trim() || process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

const headers = (platform: PlatformBackend, authenticatedWrite = false) => {
  const key = platformKey(platform);
  if (!key) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
  const actorToken = authenticatedWrite ? process.env[`${platform.toUpperCase()}_ADMIN_ACCESS_TOKEN`] : null;
  const result = new Headers({ apikey: key, "Content-Type": "application/json" });
  if (!key.startsWith("sb_secret_")) result.set("Authorization", `Bearer ${actorToken || key}`);
  return result;
};

const storageBuckets: Record<PlatformBackend, string[]> = { deligo: ["kyc"], comunhao: ["church-application-branding", "profile-media"], sarca: ["driver-kyc", "profile-media"], taomoz: ["kyc-documents"], mestre24: ["mestre24-kyc", "mestre24-portfolio"] };

export type PlatformStorageObject = { name: string; id?: string; created_at?: string; updated_at?: string; metadata?: Record<string, unknown> | null };

export async function listPlatformStorageObjects(platform: PlatformBackend, bucket: string, prefix: string) {
  if (!storageBuckets[platform].includes(bucket)) throw new Error("PLATFORM_STORAGE_BUCKET_NOT_ALLOWED");
  const response = await fetch(`${backendUrl(platform)}/storage/v1/object/list/${encodeURIComponent(bucket)}`, {
    method: "POST",
    headers: headers(platform),
    body: JSON.stringify({ prefix, limit: 100, offset: 0, sortBy: { column: "created_at", order: "asc" } }),
    cache: "no-store",
  });
  if (!response.ok) throw new Error((await response.text()) || `PLATFORM_${platform.toUpperCase()}_STORAGE_LIST_FAILED`);
  const result = await response.json() as unknown;
  return Array.isArray(result) ? result.filter((item): item is PlatformStorageObject => Boolean(item && typeof item === "object" && typeof (item as PlatformStorageObject).name === "string")) : [];
}

export async function signPlatformPath(platform: PlatformBackend, path: string) {
  if (!path || /^https?:\/\//i.test(path)) return path;
  for (const bucket of storageBuckets[platform]) {
    const response = await fetch(`${backendUrl(platform)}/storage/v1/object/sign/${bucket}/${path.split("/").map(encodeURIComponent).join("/")}`, { method: "POST", headers: headers(platform), body: JSON.stringify({ expiresIn: 900 }), cache: "no-store" });
    if (response.ok) {
      const result = await response.json() as { signedURL?: string };
      if (result.signedURL) {
        if (result.signedURL.startsWith("http")) return result.signedURL;
        const relative = result.signedURL.startsWith("/object/") ? `/storage/v1${result.signedURL}` : result.signedURL.startsWith("/storage/v1/") ? result.signedURL : `/${result.signedURL.replace(/^\//, "")}`;
        return `${backendUrl(platform)}${relative}`;
      }
    }
  }
  return path;
}

export async function platformRest(platform: PlatformBackend, path: string, init: RequestInit = {}) {
  const schemaHeaders = platform === "mestre24" ? { "Accept-Profile": "mestre24", "Content-Profile": "mestre24" } : {};
  const response = await fetch(`${backendUrl(platform)}/rest/v1/${path}`, { ...init, headers: { ...headers(platform), ...schemaHeaders, ...Object.fromEntries(new Headers(init.headers).entries()) }, cache: "no-store" });
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
