import { NextRequest, NextResponse } from "next/server";
import { corporateActor, stagingRest } from "@/lib/hq-server";
import { sendInboxEmail } from "@/lib/nominalia-mail";

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || actor.role !== "SUPER_ADMIN") return NextResponse.json({ error: "Apenas o administrador pode enviar email." }, { status: 403 });
  const body = await request.json() as { id?: string };
  if (!body.id) return NextResponse.json({ error: "Mensagem inválida." }, { status: 400 });
  try {
    const message = (await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(body.id)}&select=*`))[0];
    if (!message) return NextResponse.json({ error: "Mensagem não encontrada." }, { status: 404 });
    const recipient = await sendInboxEmail(message);
    const meta = { ...(message.meta || {}), email_sent_at: new Date().toISOString(), email_recipient: recipient };
    await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ meta }) });
    return NextResponse.json({ ok: true, recipient });
  } catch (error) {
    const code = error instanceof Error ? error.message : "EMAIL_FAILED";
    return NextResponse.json({ error: code === "NOMINALIA_SMTP_NOT_CONFIGURED" ? "Configure o utilizador e a palavra-passe SMTP da Nominalia na Vercel." : "Não foi possível enviar o email." }, { status: code === "NOMINALIA_SMTP_NOT_CONFIGURED" ? 503 : 502 });
  }
}
