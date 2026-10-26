import { NextRequest } from "next/server";
import { corporateActor, hqServiceKey, supabaseUrl } from "@/lib/hq-server";

const allowedRoles = new Set(["SUPER_ADMIN", "FINANCE"]);

function safePath(value: string, folder: string) {
  let path = value.trim();
  // Accept legacy full Storage URLs, but strip host/query/token before
  // authorizing the object against the private loan-documents bucket.
  if (/^https?:\/\//i.test(path)) {
    try {
      const parsed = new URL(path);
      const marker = "/storage/v1/object/";
      const markerIndex = parsed.pathname.indexOf(marker);
      if (markerIndex < 0) return null;
      const objectPath = parsed.pathname.slice(markerIndex + marker.length);
      const bucketIndex = objectPath.indexOf("loan-documents/");
      if (bucketIndex < 0) return null;
      path = objectPath.slice(bucketIndex + "loan-documents/".length);
    } catch {
      return null;
    }
  }
  path = path.replace(/\\/g, "/").replace(/^\/+/, "");
  const safeFolder = folder.trim().replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");
  if (path.startsWith("loan-documents/")) path = path.slice("loan-documents/".length);
  if (!path || path.includes("..") || path.includes("://") || path.includes("\0")) return null;
  if (!path.includes("/") && safeFolder) path = `${safeFolder}/${path}`;
  if (safeFolder && !path.startsWith(`${safeFolder}/`)) return null;
  return path;
}

export async function GET(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || !allowedRoles.has(actor.role)) return new Response("Não autorizado", { status: 403 });
  const path = safePath(request.nextUrl.searchParams.get("path") || "", request.nextUrl.searchParams.get("folder") || "");
  const key = hqServiceKey();
  if (!path || !key) return new Response("Documento indisponível", { status: 404 });
  const headers: Record<string, string> = { apikey: key };
  if (!key.startsWith("sb_secret_")) headers.Authorization = `Bearer ${key}`;
  const response = await fetch(`${supabaseUrl()}/storage/v1/object/loan-documents/${path.split("/").map(encodeURIComponent).join("/")}`, { headers, cache: "no-store" });
  if (!response.ok) return new Response("Documento indisponível", { status: response.status === 404 ? 404 : 502 });
  const contentType = response.headers.get("content-type") || "application/octet-stream";
  return new Response(await response.arrayBuffer(), { headers: { "Content-Type": contentType, "Cache-Control": "private, no-store" } });
}
