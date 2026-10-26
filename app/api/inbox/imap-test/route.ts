import { NextRequest, NextResponse } from "next/server";
import { corporateActor } from "@/lib/hq-server";
import { testNominaliaMailbox } from "@/lib/nominalia-imap";

const allowed = new Set(["geral", "comercial", "carreiras"] as const);

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || !["SUPER_ADMIN", "FINANCE", "CUSTOMER_SUPPORT", "SUPERVISOR", "MARKETING"].includes(actor.role)) return NextResponse.json({ error: "Sem permissão para testar a caixa." }, { status: 403 });
  const body = await request.json().catch(() => null) as { area?: string } | null;
  const area = body?.area;
  if (!area || !allowed.has(area as "geral" | "comercial" | "carreiras")) return NextResponse.json({ error: "Indique uma caixa válida." }, { status: 400 });
  try {
    const result = await testNominaliaMailbox(area as "geral" | "comercial" | "carreiras");
    return NextResponse.json({ ok: result.status === "connected", result }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "Não foi possível testar a caixa sem expor credenciais." }, { status: 502 });
  }
}
