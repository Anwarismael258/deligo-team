import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission } from "@/lib/hq-server";
import { platformFunction, type PlatformBackend } from "@/lib/platform-backends";

export const dynamic = "force-dynamic";

type SafetyPlatform = PlatformBackend;
const platforms: SafetyPlatform[] = ["deligo", "comunhao", "taomoz", "sarca", "mestre24"];
const labels: Record<SafetyPlatform, string> = { deligo: "DeliGo", comunhao: "Comunhão", taomoz: "DeliGo Market", sarca: "SARCA", mestre24: "Mestre24" };
const configured = new Set<SafetyPlatform>(["sarca"]);

function validPlatform(value: string | null): SafetyPlatform {
  return platforms.includes(value as SafetyPlatform) ? value as SafetyPlatform : "sarca";
}

export async function GET(request: NextRequest) {
  const authorization = await requireCorporatePermission("field.view", "sarca");
  if (!authorization) return NextResponse.json({ error: "Sem permissão para consultar ocorrências de segurança." }, { status: 403 });
  const platform = validPlatform(request.nextUrl.searchParams.get("platform"));
  if (!configured.has(platform)) return NextResponse.json({ platform, label: labels[platform], configured: false, events: [], checkedAt: new Date().toISOString() });
  try {
    const result = await platformFunction(platform, "admin-list-sarca-safety-events");
    return NextResponse.json({ platform, label: labels[platform], configured: true, events: (result as { events?: unknown[] })?.events || [], checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return NextResponse.json({ platform, label: labels[platform], configured: true, events: [], checkedAt: new Date().toISOString(), error: error instanceof Error ? error.message : "Fonte de segurança indisponível." }, { status: 502 });
  }
}

export async function POST(request: NextRequest) {
  const authorization = await requireCorporatePermission("field.manage", "sarca");
  if (!authorization) return NextResponse.json({ error: "Sem permissão para alterar ocorrências de segurança." }, { status: 403 });
  const body = await request.json() as { platform?: string; eventId?: string; action?: "acknowledge" | "resolve"; resolutionNote?: string };
  const platform = validPlatform(body.platform || null);
  if (!configured.has(platform) || !body.eventId || !body.action) return NextResponse.json({ error: "Plataforma, ocorrência e ação são obrigatórias." }, { status: 400 });
  if (body.action === "resolve" && (body.resolutionNote || "").trim().length < 3) return NextResponse.json({ error: "A resolução exige uma nota." }, { status: 400 });
  try {
    const result = await platformFunction(platform, "admin-update-sarca-safety-event", { eventId: body.eventId, action: body.action, resolutionNote: body.resolutionNote?.trim() || undefined });
    return NextResponse.json({ ok: true, result });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Não foi possível actualizar a ocorrência." }, { status: 502 });
  }
}
