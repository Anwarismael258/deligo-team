import { NextResponse } from "next/server";
import { metricRegistry } from "@/lib/metric-registry";
import { requireCorporatePermission } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

export async function GET() {
  const authorization = await requireCorporatePermission("reports.view");
  if (!authorization?.actor) return NextResponse.json({ error: "Sem acesso ao catálogo de métricas." }, { status: 403 });
  return NextResponse.json({ checkedAt: new Date().toISOString(), metrics: metricRegistry }, { headers: { "Cache-Control": "private, no-store" } });
}
