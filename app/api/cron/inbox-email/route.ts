import { NextRequest, NextResponse } from "next/server";
import { stagingRest } from "@/lib/hq-server";
import { sendInboxEmail } from "@/lib/nominalia-mail";

export async function GET(request: NextRequest) {
  const expected = process.env.CRON_SECRET;
  if (!expected) return NextResponse.json({ error: "CRON_SECRET não configurado." }, { status: 503 });
  if (request.headers.get("authorization") !== `Bearer ${expected}`) return NextResponse.json({ error: "Não autorizado." }, { status: 401 });
  try {
    const messages = await stagingRest("inbox_messages?select=*&order=created_at.asc&limit=100&meta->>email_sent_at=is.null") as Array<Record<string, unknown>>;
    let sent = 0;
    for (const message of messages) {
      const recipient = await sendInboxEmail(message as never);
      const meta = { ...((message.meta as Record<string, unknown> | null) || {}), email_sent_at: new Date().toISOString(), email_recipient: recipient };
      await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(String(message.id))}`, { method: "PATCH", body: JSON.stringify({ meta }) });
      sent += 1;
    }
    return NextResponse.json({ ok: true, sent });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "EMAIL_FAILED" }, { status: 502 }); }
}
