import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission } from "@/lib/hq-server";
import { platformRest, signPlatformPath, type PlatformBackend } from "@/lib/platform-backends";

export const dynamic = "force-dynamic";
const allowed = ["deligo", "comunhao", "sarca", "taomoz"] as const;
const isPlatform = (value: string): value is PlatformBackend => allowed.includes(value as PlatformBackend);
const read = async (platform: PlatformBackend, path: string) => { try { return await platformRest(platform, path); } catch { return []; } };
const mediaFields = ["photo_url", "image_url", "document_url", "file_url", "selfie_url", "document_front_path", "document_back_path", "selfie_path", "proof_url", "photos", "documents", "files", "attachments"];
const signRow = async (platform: PlatformBackend, value: unknown) => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  const row = { ...(value as Record<string, unknown>) };
  for (const field of mediaFields) {
    const item = row[field];
    if (typeof item === "string" && item) row[field] = await signPlatformPath(platform, item);
    if (Array.isArray(item)) row[field] = await Promise.all(item.map(entry => typeof entry === "string" ? signPlatformPath(platform, entry) : entry));
  }
  return row;
};

export async function GET(_request: NextRequest, context: { params: Promise<{ platform: string; id: string }> }) {
  const { platform, id } = await context.params;
  if (!isPlatform(platform)) return NextResponse.json({ error: "Plataforma inválida." }, { status: 400 });
  const authorization=await requireCorporatePermission("platform.manage",platform);
  if (!authorization) return NextResponse.json({ error: "Sem permissão para consultar este perfil ou plataforma." }, { status: 403 });
  const encoded = encodeURIComponent(id);
  const profile = platform === "comunhao"
    ? (await read(platform, `church_applications?id=eq.${encoded}&select=*&limit=1`))[0] || null
    : platform === "sarca"
      ? (await read(platform, `driver_profiles?id=eq.${encoded}&select=*&limit=1`))[0] || (await read(platform, `profiles?id=eq.${encoded}&select=*&limit=1`))[0] || null
      : (await read(platform, `profiles?id=eq.${encoded}&select=*&limit=1`))[0] || null;
  const [kyc, wallets, orders, disputes, activity] = await Promise.all([
    read(platform, platform === "comunhao" ? `church_applications?id=eq.${encoded}&select=*&limit=1` : platform === "sarca" ? `driver_documents?driver_id=eq.${encoded}&select=*&limit=50` : platform === "taomoz" ? `kyc_submissions?user_id=eq.${encoded}&select=*&limit=20` : `profiles?id=eq.${encoded}&select=*&limit=1`),
    read(platform, platform === "taomoz" ? `wallets?user_id=eq.${encoded}&select=*&limit=20` : `wallets?owner_id=eq.${encoded}&select=*&limit=20`),
    read(platform, platform === "sarca" ? `trips?driver_id=eq.${encoded}&select=*&order=created_at.desc&limit=20` : `orders?user_id=eq.${encoded}&select=*&order=created_at.desc&limit=20`),
    read(platform, platform === "deligo" ? `order_disputes?user_id=eq.${encoded}&select=*&order=created_at.desc&limit=20` : `disputes?user_id=eq.${encoded}&select=*&order=created_at.desc&limit=20`),
    read(platform, platform === "deligo" ? `admin_actions_log?target_id=eq.${encoded}&select=*&order=created_at.desc&limit=20` : `internal_notifications?user_id=eq.${encoded}&select=*&order=created_at.desc&limit=20`),
  ]);
  const signed = async (items: unknown[]) => Promise.all(items.map(item => signRow(platform, item)));
  return NextResponse.json({ platform, id, profile: await signRow(platform, profile), kyc: await signed(kyc), wallets: await signed(wallets), orders: await signed(orders), disputes: await signed(disputes), activity: await signed(activity) }, { headers: { "Cache-Control": "private, no-store" } });
}
