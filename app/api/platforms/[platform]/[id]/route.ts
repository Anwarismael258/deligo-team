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
const mediaFields = ["photo_url", "avatar_url", "profile_photo_url", "profile_image_url", "image_url", "logo_url", "cover_url", "menu_image_url", "menu_images", "gallery", "document_url", "file_url", "selfie_url", "selfie", "document_front_path", "document_back_path", "document_front_url", "document_back_url", "id_front_url", "id_back_url", "selfie_path", "proof_url", "nuit_url", "bi_url", "photos", "documents", "document_references", "kyc_docs", "kyc_documents", "files", "attachments", "identity_document"];
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
const uniqueRows = (rows: unknown[]) => rows.filter((row, index, all) => {
  if (!row || typeof row !== "object") return false;
  const value = row as Record<string, unknown>;
  const key = String(value.id || value.reference || `${value.created_at || value.updated_at || "row"}-${index}`);
  return all.findIndex(candidate => {
    if (!candidate || typeof candidate !== "object") return false;
    const other = candidate as Record<string, unknown>;
    return String(other.id || other.reference || `${other.created_at || other.updated_at || "row"}-${all.indexOf(candidate)}`) === key;
  }) === index;
}) as Record<string, unknown>[];
const readMany = async (platform: SupportedPlatform, paths: string[]) => uniqueRows((await Promise.all(paths.map(path => read(platform, path)))).flat());
const relationPaths = (table: string, keys: string[], id: string, select = "*") => keys.map(key => `${table}?${key}=eq.${encodeURIComponent(id)}&select=${select}&order=created_at.desc&limit=50`);

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
  const ids = uniqueRows([{ id: initialId }, { id: resolvedId }, { id: profile?.user_id }, { id: profile?.profile_id }]).map(row => String(row.id)).filter(Boolean);
  const kycPaths = ids.flatMap(value => platform === "mestre24"
    ? relationPaths("kyc_verifications", ["user_id", "profile_id"], value)
    : platform === "sarca"
      ? relationPaths("driver_documents", ["driver_id", "user_id"], value)
      : platform === "comunhao"
        ? relationPaths("church_applications", ["id", "user_id", "owner_id"], value)
        : relationPaths("kyc_submissions", ["id", "user_id", "profile_id", "owner_id"], value));
  const walletPaths = ids.flatMap(value => relationPaths("wallets", ["owner_id", "user_id", "profile_id"], value));
  const operationPaths = platform === "mestre24"
    ? ids.flatMap(value => relationPaths("service_requests", ["client_id", "professional_id", "provider_id", "user_id"], value))
    : platform === "sarca"
      ? ids.flatMap(value => relationPaths("trips", ["driver_id", "rider_id", "passenger_id", "user_id"], value))
      : ids.flatMap(value => relationPaths("orders", ["user_id", "customer_id", "buyer_id", "seller_id", "restaurant_id", "courier_id", "rider_id"], value));
  const disputePaths = platform === "mestre24"
    ? ids.flatMap(value => relationPaths("reports", ["reporter_id", "client_id", "professional_id", "user_id"], value))
    : platform === "deligo"
      ? ids.flatMap(value => relationPaths("order_disputes", ["user_id", "customer_id", "restaurant_id", "courier_id"], value))
      : ids.flatMap(value => relationPaths("disputes", ["user_id", "owner_id", "customer_id", "driver_id", "professional_id"], value));
  const activityPaths = platform === "mestre24"
    ? ids.flatMap(value => relationPaths("reviews", ["client_id", "professional_id", "user_id"], value))
    : platform === "deligo"
      ? ids.flatMap(value => relationPaths("admin_actions_log", ["target_id", "user_id"], value))
      : ids.flatMap(value => relationPaths("internal_notifications", ["user_id", "owner_id"], value));
  const extraPaths = platform === "comunhao"
    ? ids.flatMap(value => [
      ...relationPaths("church_events", ["church_id", "owner_id", "user_id"], value),
      ...relationPaths("church_subscriptions", ["church_id", "owner_id", "user_id"], value),
      ...relationPaths("donations", ["church_id", "owner_id", "user_id"], value),
    ])
    : [];
  const [kyc, wallets, orders, disputes, activity, extras] = await Promise.all([
    readMany(platform, kycPaths),
    readMany(platform, walletPaths),
    readMany(platform, operationPaths),
    readMany(platform, disputePaths),
    readMany(platform, activityPaths),
    readMany(platform, extraPaths),
  ]);
  const kycRows = uniqueRows([...sourceKyc, ...kyc]);
  const history = [
    ...orders.map(row => ({ ...row, _history_type: platform === "mestre24" ? "Pedido de serviço" : platform === "sarca" ? "Viagem" : "Pedido" })),
    ...extras.map(row => ({ ...row, _history_type: "Registo da plataforma" })),
    ...disputes.map(row => ({ ...row, _history_type: platform === "mestre24" ? "Relatório" : "Disputa" })),
    ...activity.map(row => ({ ...row, _history_type: platform === "mestre24" ? "Avaliação" : "Actividade" })),
  ].sort((a, b) => { const newer = (row: Record<string, unknown>) => Date.parse(String(row.created_at || row.updated_at || "")); return newer(b) - newer(a); });
  const signed = async (items: unknown[]) => Promise.all(items.map(item => signRow(platform, item)));
  return NextResponse.json({ platform, id: resolvedId, profile: await signRow(platform, profile), kyc: await signed(kycRows), wallets: await signed(wallets), orders: await signed(orders), disputes: await signed(disputes), activity: await signed(activity), extras: await signed(extras), history: await signed(history), counts: { kyc: kycRows.length, wallets: wallets.length, operations: orders.length, disputes: disputes.length, activity: activity.length, history: history.length } }, { headers: { "Cache-Control": "private, no-store" } });
}
