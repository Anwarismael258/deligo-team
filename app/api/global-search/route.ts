import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRest } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

const safeQuery = (value: string) => value.replace(/[,%()]/g, " ").trim();
const roleLabel = (membership: Record<string, unknown>) => {
  const raw = membership.roles;
  const values: unknown[] = Array.isArray(raw) ? raw : typeof raw === "string" && raw.trim().startsWith("[") ? (() => { try { const parsed = JSON.parse(raw) as unknown; return Array.isArray(parsed) ? parsed : [raw]; } catch { return [raw]; } })() : [raw];
  const roles = values.filter((value): value is string => typeof value === "string" && Boolean(value.trim())).map(value => value.trim());
  if (roles.length) return roles.join(" / ");
  const slug = String(membership.app_slug || "").toLowerCase();
  return slug === "deligo" ? "Cliente / Restaurante / Estafeta" : slug === "comunhao" ? "Membro / Igreja" : slug === "taomoz" ? "Comprador / Vendedor / Entregador" : slug === "sarca" ? "Passageiro / Motorista" : slug === "mestre24" ? "Cliente / Profissional" : "Utilizador";
};

export async function GET(request: NextRequest) {
  const authorization = await corporateAuthorization();
  if (!authorization) return NextResponse.json({ error: "Sessão corporativa necessária." }, { status: 401 });
  const query = safeQuery(request.nextUrl.searchParams.get("q") || "");
  const userId = request.nextUrl.searchParams.get("userId")?.trim();
  const listAll = request.nextUrl.searchParams.get("list") === "all";
  if (!query && !userId && !listAll) return NextResponse.json({ data: [] });
  const scope = !authorization.isSuperAdmin && authorization.platformSlugs.length
    ? `&app_slug=in.(${authorization.platformSlugs.join(",")})`
    : !authorization.isSuperAdmin ? "&app_slug=eq.__forbidden__" : "";
  const where = userId ? `user_id=eq.${encodeURIComponent(userId)}` : listAll ? "" : `or=(full_name.ilike.*${encodeURIComponent(query)}*,display_name.ilike.*${encodeURIComponent(query)}*,primary_phone.ilike.*${encodeURIComponent(query)}*,primary_email.ilike.*${encodeURIComponent(query)}*)`;
  try {
    const memberships = await hqRest(`global_user_platforms_v1?select=*&${where}${scope}&order=last_seen_at.desc.nullslast&limit=${listAll ? 500 : 100}`) as Record<string, unknown>[];
    const users = new Map<string, Record<string, unknown>>();
    for (const membership of memberships) {
      const id = String(membership.user_id);
      const current = users.get(id) || { user_id: id, full_name: membership.full_name, display_name: membership.display_name, primary_phone: membership.primary_phone, primary_email: membership.primary_email, profile_status: membership.profile_status, avatar_url: membership.avatar_url || membership.profile_photo_url || membership.profile_image_url || null, profile_photo_url: membership.profile_photo_url || null, profile_image_url: membership.profile_image_url || null, photo_url: membership.photo_url || null, image_url: membership.image_url || null, apps: [] as Record<string, unknown>[] };
      (current.apps as Record<string, unknown>[]).push({ slug: membership.app_slug, name: membership.app_name, role: roleLabel(membership), status: membership.membership_status, joined_at: membership.joined_at, last_seen_at: membership.last_seen_at });
      users.set(id, current);
    }
    const result = await Promise.all([...users.values()].map(async (user) => {
      const id = String(user.user_id);
      const [kyc, activity] = await Promise.all([
        hqRest(`platform_kyc_cases?select=status,platforms!inner(slug,name)&subject_user_id=eq.${encodeURIComponent(id)}&order=updated_at.desc&limit=20`).catch(() => []),
        hqRest(`platform_events?select=event_type,entity_type,entity_id,occurred_at,platforms!inner(slug,name)&or=(user_id.eq.${encodeURIComponent(id)},actor_user_id.eq.${encodeURIComponent(id)})&order=occurred_at.desc&limit=20`).catch(() => []),
      ]);
      return { ...user, kyc, activity };
    }));
    return NextResponse.json({ data: result, checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Pesquisa corporativa indisponível." }, { status: 502 });
  }
}
