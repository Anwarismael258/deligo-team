import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRest, hqRpc } from "@/lib/hq-server";
import { signPlatformPath, type PlatformBackend } from "@/lib/platform-backends";

export const dynamic = "force-dynamic";

const roles = new Set(["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "FIELD", "COMPLIANCE", "LEGAL"]);
const platforms = new Set<PlatformBackend>(["deligo", "sarca", "taomoz", "comunhao", "mestre24"]);

const permitted = (authorization: NonNullable<Awaited<ReturnType<typeof corporateAuthorization>>>) =>
  authorization.isSuperAdmin || roles.has(authorization.actor.role);

async function withSignedDocuments(row: Record<string, unknown>) {
  const platform = ((row.platforms as { slug?: string } | null)?.slug || "") as PlatformBackend;
  const documents = Array.isArray(row.document_references) ? row.document_references : [];
  if (!platforms.has(platform)) return row;
  const signed = await Promise.all(documents.map(async (document) => {
    const item = document as Record<string, unknown>;
    const path = typeof item.path === "string" ? item.path : "";
    return { ...item, signed_url: path ? await signPlatformPath(platform, path) : null };
  }));
  return { ...row, document_references: signed };
}

export async function GET(request: NextRequest) {
  const authorization = await corporateAuthorization();
  if (!authorization || !permitted(authorization)) return NextResponse.json({ error: "Sem permissão para a fila KYC corporativa." }, { status: 403 });
  const platform = request.nextUrl.searchParams.get("platform")?.trim().toLowerCase();
  if (platform && !platforms.has(platform as PlatformBackend)) return NextResponse.json({ error: "Plataforma KYC inválida." }, { status: 400 });
  if (platform && !authorization.isSuperAdmin && !authorization.platformSlugs.includes(platform)) return NextResponse.json({ error: "Sem acesso à plataforma solicitada." }, { status: 403 });
  const status = request.nextUrl.searchParams.get("status")?.trim().toLowerCase();
  const platformFilter = platform ? `&platforms.slug=eq.${encodeURIComponent(platform)}` : "";
  const statusFilter = status ? `&status=eq.${encodeURIComponent(status)}` : "";
  const scope = !platform && !authorization.isSuperAdmin && authorization.platformIds.length
    ? `&platform_id=in.(${authorization.platformIds.join(",")})`
    : "";
  try {
    const rows = await hqRest(`platform_kyc_cases?select=*,platforms!inner(slug,name,platform_code)&order=submitted_at.desc&limit=300${platformFilter}${statusFilter}${scope}`) as Record<string, unknown>[];
    return NextResponse.json({ data: await Promise.all(rows.map(withSignedDocuments)), checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Fila KYC indisponível." }, { status: 502 });
  }
}

export async function PATCH(request: NextRequest) {
  const authorization = await corporateAuthorization();
  if (!authorization || !permitted(authorization)) return NextResponse.json({ error: "Sem permissão para decidir casos KYC." }, { status: 403 });
  const body = await request.json() as { caseId?: string; decision?: string; reason?: string };
  if (!body.caseId || !["approve", "reject", "suspend", "correction"].includes(body.decision || "")) {
    return NextResponse.json({ error: "Caso e decisão KYC válidos são obrigatórios." }, { status: 400 });
  }
  if (body.decision !== "approve" && !body.reason?.trim()) return NextResponse.json({ error: "O motivo é obrigatório para rejeitar, suspender ou pedir correção." }, { status: 400 });
  try {
    const result = await hqRpc("hq_decide_platform_kyc_v1", {
      p_case_id: body.caseId,
      p_actor_auth_user_id: authorization.actor.authUserId,
      p_decision: body.decision,
      p_reason: body.reason?.trim() || null,
    });
    return NextResponse.json({ result });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "A decisão KYC não foi aplicada." }, { status: 409 });
  }
}
