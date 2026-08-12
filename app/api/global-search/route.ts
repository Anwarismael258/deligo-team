import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRest } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

const safeQuery = (value: string) => value.replace(/[,%()]/g, " ").trim();

export async function GET(request: NextRequest) {
  const authorization = await corporateAuthorization();
  if (!authorization) return NextResponse.json({ error: "Sessão corporativa necessária." }, { status: 401 });
  const query = safeQuery(request.nextUrl.searchParams.get("q") || "");
  const userId = request.nextUrl.searchParams.get("userId")?.trim();
  if (!query && !userId) return NextResponse.json({ data: [] });
  const scope = !authorization.isSuperAdmin && authorization.platformSlugs.length
    ? `&app_slug=in.(${authorization.platformSlugs.join(",")})`
    : !authorization.isSuperAdmin ? "&app_slug=eq.__forbidden__" : "";
  const where = userId ? `user_id=eq.${encodeURIComponent(userId)}` : `or=(full_name.ilike.*${encodeURIComponent(query)}*,display_name.ilike.*${encodeURIComponent(query)}*,primary_phone.ilike.*${encodeURIComponent(query)}*,primary_email.ilike.*${encodeURIComponent(query)}*)`;
  try {
    const memberships = await hqRest(`global_user_platforms_v1?select=*&${where}${scope}&order=last_seen_at.desc.nullslast&limit=100`) as Record<string, unknown>[];
    const users = new Map<string, Record<string, unknown>>();
    for (const membership of memberships) {
      const id = String(membership.user_id);
      const current = users.get(id) || { user_id: id, full_name: membership.full_name, display_name: membership.display_name, primary_phone: membership.primary_phone, primary_email: membership.primary_email, profile_status: membership.profile_status, apps: [] as Record<string, unknown>[] };
      (current.apps as Record<string, unknown>[]).push({ slug: membership.app_slug, name: membership.app_name, role: membership.roles, status: membership.membership_status, joined_at: membership.joined_at, last_seen_at: membership.last_seen_at });
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
