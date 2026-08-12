import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRest } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const authorization = await corporateAuthorization();
  if (!authorization || (!authorization.isSuperAdmin && !authorization.permissions.includes("platform.dashboard.read"))) {
    return NextResponse.json({ error: "Sem permissão para consultar a atividade corporativa." }, { status: 403 });
  }

  const requestedPlatform = request.nextUrl.searchParams.get("platform")?.trim().toLowerCase();
  if (requestedPlatform && !authorization.isSuperAdmin && !authorization.platformSlugs.includes(requestedPlatform)) {
    return NextResponse.json({ error: "Sem acesso à plataforma solicitada." }, { status: 403 });
  }
  const platformFilter = requestedPlatform ? `&platforms.slug=eq.${encodeURIComponent(requestedPlatform)}` : "";
  const scopedFilter = !requestedPlatform && !authorization.isSuperAdmin && authorization.platformIds.length
    ? `&platform_id=in.(${authorization.platformIds.join(",")})`
    : "";
  try {
    const data = await hqRest(
      `platform_events?select=id,source_app,event_type,entity_type,entity_id,user_id,actor_user_id,payload,occurred_at,created_at,platforms!inner(slug,name,platform_code)&order=occurred_at.desc&limit=200${platformFilter}${scopedFilter}`,
    );
    return NextResponse.json({ data, checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Atividade corporativa indisponível." }, { status: 502 });
  }
}
