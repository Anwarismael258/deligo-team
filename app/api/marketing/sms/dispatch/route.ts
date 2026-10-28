import { timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { hqRest } from "@/lib/hq-server";
import { dispatchSms, smsLiveEnabled, type SmsCampaign } from "@/lib/sms-campaign-server";
export const dynamic = "force-dynamic";
export const maxDuration = 120;
// Invoke with a private scheduler via POST. No query-string credentials or browser credentials.
export async function POST(request: NextRequest) {
  const expected = process.env.MOZESMS_MARKETING_WORKER_SECRET || "";
  const supplied = request.headers.get("authorization") || "";
  const target = `Bearer ${expected}`;
  if (expected.length < 32 || Buffer.byteLength(supplied) !== Buffer.byteLength(target) || !timingSafeEqual(Buffer.from(supplied), Buffer.from(target))) return NextResponse.json({ error: "Não autorizado." }, { status: 401 });
  if (!smsLiveEnabled()) return NextResponse.json({ error: "Envios desativados." }, { status: 409 });
  try {
    const campaigns = await hqRest("sms_campaigns?status=eq.ready&select=*&order=created_at.asc&limit=5") as SmsCampaign[];
    const results = [];
    for (const campaign of campaigns) results.push(await dispatchSms(campaign, campaign.created_by));
    return NextResponse.json({ results });
  } catch { return NextResponse.json({ error: "Falha no processamento; consulte os estados antes de reenviar." }, { status: 502 }); }
}
