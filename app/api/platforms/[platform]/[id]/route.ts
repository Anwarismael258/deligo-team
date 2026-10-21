import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, stagingRest } from "@/lib/hq-server";
import { platformRest, signPlatformPath } from "@/lib/platform-backends";

export const dynamic = "force-dynamic";
const allowed = ["deligo", "comunhao", "sarca", "taomoz", "mestre24"] as const;
type SupportedPlatform = (typeof allowed)[number];
const isPlatform = (value: string): value is SupportedPlatform => allowed.includes(value as SupportedPlatform);
const read = async (platform: SupportedPlatform, path: string) => {
  try {
    // DeliGo's operational records are held in the shared Central project;
    // use that canonical public schema for profile/KYC detail pages. The
    // platform gateway may point at a separate legacy project with no rows.
    return platform === "deligo" ? await stagingRest(path) : await platformRest(platform, path);
  } catch {
    return [];
  }
};
const mediaFields = ["photo_url", "avatar_url", "image_url", "document_url", "file_url", "selfie_url", "selfie", "document_front_path", "document_back_path", "document_front_url", "document_back_url", "id_front_url", "id_back_url", "selfie_path", "proof_url", "nuit_url", "bi_url", "photos", "documents", "document_references", "kyc_docs", "kyc_documents", "files", "attachments", "identity_document"];
const mediaPathFields = new Set(["url", "path", "reference", "storage_path", "file_url", "document_url", "photo_url", "image_url"]);
const signMediaValue = async (platform: SupportedPlatform, value: unknown): Promise<unknown> => {
  if (typeof value === "string") return value ? await signPlatformPath(platform, value) : value;
  if (Array.isArray(value)) return Promise.all(value.map(item => signMediaValue(platform, item)));
  if (!value || typeof value !== "object") return value;
  const object = { ...(value as Record<string, unknown>) };
  for (const [key, item] of Object.entries(object)) {
    if (mediaPathFields.has(key) && typeof item === "string" && item) object[key] = await signPlatformPath(platform, item);
    else if (item && typeof item === "object") object[key] = await signMediaValue(platform, item);
  }
  return object;
};
const signRow = async (platform: SupportedPlatform, value: unknown) => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  const row = { ...(value as Record<string, unknown>) };
  for (const field of mediaFields) {
    const item = row[field];
    if (item != null) row[field] = await signMediaValue(platform, item);
  }
  return row;
};

export async function GET(_request: NextRequest, context: { params: Promise<{ platform: string; id: string }> }) {
  const { platform, id } = await context.params;
  if (!isPlatform(platform)) return NextResponse.json({ error: "Plataforma inválida." }, { status: 400 });
  const authorization=await requireCorporatePermission("platform.manage",platform);
  if (!authorization) return NextResponse.json({ error: "Sem permissão para consultar este perfil ou plataforma." }, { status: 403 });
  const encoded = encodeURIComponent(id);
  const initialId = id;
  let profile = platform === "mestre24"
    ? (await read(platform, `profiles?user_id=eq.${encoded}&select=*&limit=1`))[0] || null
    : platform === "comunhao"
    ? (await read(platform, `church_applications?id=eq.${encoded}&select=*&limit=1`))[0] || null
    : platform === "sarca"
      ? (await read(platform, `driver_profiles?id=eq.${encoded}&select=*&limit=1`))[0] || (await read(platform, `profiles?id=eq.${encoded}&select=*&limit=1`))[0] || null
      : (await read(platform, `profiles?id=eq.${encoded}&select=*&limit=1`))[0] || null;
  // Field cards may carry the KYC case id rather than the platform profile id.
  // Resolve the subject first so the detail view never silently loses identity/media.
  let resolvedId = initialId;
  let sourceKyc: Record<string, unknown>[] = [];
  if (platform === "deligo") {
    // Depending on the originating app, the Central card can carry either
    // the KYC submission id or the person's profile/user id. Look up both so
    // an approved DeliGo Eats case always opens its real profile and media.
    const lookup = await Promise.all([
      read(platform, `kyc_submissions?id=eq.${encoded}&select=*&limit=50`),
      read(platform, `kyc_submissions?user_id=eq.${encoded}&select=*&limit=50`),
      read(platform, `kyc_submissions?profile_id=eq.${encoded}&select=*&limit=50`),
      read(platform, `kyc_submissions?owner_id=eq.${encoded}&select=*&limit=50`),
    ]);
    sourceKyc = lookup.flat().filter((row, index, all) => all.findIndex(item => String(item.id || "") === String(row.id || "")) === index) as Record<string, unknown>[];
    const subject = sourceKyc[0];
    const candidate = subject?.user_id || subject?.profile_id || subject?.owner_id || subject?.submitted_by;
    if (candidate) {
      resolvedId = String(candidate);
      const resolvedProfile = await read(platform, `profiles?id=eq.${encodeURIComponent(resolvedId)}&select=*&limit=1`);
      if (resolvedProfile[0]) profile = resolvedProfile[0];
    }
    // A KYC submission can be the only profile record available to the HQ.
    // Keep it as a fallback identity so the gallery still renders all files.
    if (!profile && subject) profile = { ...subject, id: resolvedId };
  }
  const subjectEncoded = encodeURIComponent(resolvedId);
  const [kyc, wallets, orders, disputes, activity] = await Promise.all([
    read(platform, platform === "mestre24" ? `kyc_verifications?user_id=eq.${subjectEncoded}&select=*&limit=20` : platform === "comunhao" ? `church_applications?id=eq.${subjectEncoded}&select=*&limit=1` : platform === "sarca" ? `driver_documents?driver_id=eq.${subjectEncoded}&select=*&limit=50` : platform === "taomoz" ? `kyc_submissions?user_id=eq.${subjectEncoded}&select=*&limit=20` : `kyc_submissions?user_id=eq.${subjectEncoded}&select=*&limit=20`),
    read(platform, platform === "taomoz" ? `wallets?user_id=eq.${subjectEncoded}&select=*&limit=20` : `wallets?owner_id=eq.${subjectEncoded}&select=*&limit=20`),
    read(platform, platform === "mestre24" ? `service_requests?client_id=eq.${subjectEncoded}&select=*&order=created_at.desc&limit=20` : platform === "sarca" ? `trips?driver_id=eq.${subjectEncoded}&select=*&order=created_at.desc&limit=20` : `orders?user_id=eq.${subjectEncoded}&select=*&order=created_at.desc&limit=20`),
    read(platform, platform === "mestre24" ? `reports?reporter_id=eq.${subjectEncoded}&select=*&order=created_at.desc&limit=20` : platform === "deligo" ? `order_disputes?user_id=eq.${subjectEncoded}&select=*&order=created_at.desc&limit=20` : `disputes?user_id=eq.${subjectEncoded}&select=*&order=created_at.desc&limit=20`),
    read(platform, platform === "mestre24" ? `reviews?client_id=eq.${subjectEncoded}&select=*&order=created_at.desc&limit=20` : platform === "deligo" ? `admin_actions_log?target_id=eq.${subjectEncoded}&select=*&order=created_at.desc&limit=20` : `internal_notifications?user_id=eq.${subjectEncoded}&select=*&order=created_at.desc&limit=20`),
  ]);
  const kycRows = [...sourceKyc, ...(kyc as Record<string, unknown>[])].filter((row, index, all) => all.findIndex(item => String(item.id || "") === String(row.id || "")) === index);
  const signed = async (items: unknown[]) => Promise.all(items.map(item => signRow(platform, item)));
  return NextResponse.json({ platform, id: resolvedId, profile: await signRow(platform, profile), kyc: await signed(kycRows), wallets: await signed(wallets), orders: await signed(orders), disputes: await signed(disputes), activity: await signed(activity) }, { headers: { "Cache-Control": "private, no-store" } });
}
