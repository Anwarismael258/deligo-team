import { NextRequest, NextResponse } from "next/server";
import { corporateActor, stagingRest } from "@/lib/hq-server";
import { configuredInboxSenders, sendComposedInboxEmail, sendInboxEmail } from "@/lib/nominalia-mail";

export async function GET() {
  const actor = await corporateActor();
  if (!actor || !["SUPER_ADMIN", "FINANCE"].includes(actor.role)) return NextResponse.json({ error: "Apenas o Administrador ou Finanças podem enviar email." }, { status: 403 });
  return NextResponse.json({ senders: configuredInboxSenders() });
}

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || !["SUPER_ADMIN", "FINANCE"].includes(actor.role)) return NextResponse.json({ error: "Apenas o Administrador ou Finanças podem enviar email." }, { status: 403 });
  const body = await request.json() as { id?: string; from?: string; to?: string; subject?: string; message?: string };
  if (body.to || body.subject || body.message || body.from) {
    if (!body.from || !body.to || !body.subject?.trim() || !body.message?.trim()) return NextResponse.json({ error: "Remetente, destinatário, assunto e mensagem são obrigatórios." }, { status: 400 });
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.to) || body.to.length > 320) return NextResponse.json({ error: "Destinatário inválido." }, { status: 400 });
    if (body.subject.length > 200 || body.message.length > 10000) return NextResponse.json({ error: "Assunto ou mensagem demasiado longos." }, { status: 400 });
    try {
      const recipient = await sendComposedInboxEmail({ from: body.from, to: body.to, subject: body.subject.trim(), text: body.message.trim() });
      return NextResponse.json({ ok: true, recipient });
    } catch (error) {
      const code = error instanceof Error ? error.message : "EMAIL_FAILED";
      return NextResponse.json({ error: code === "NOMINALIA_SMTP_NOT_CONFIGURED" ? "Configure o SMTP autorizado na Vercel." : code === "EMAIL_SENDER_NOT_ALLOWED" ? "Remetente não autorizado." : "Não foi possível enviar o email." }, { status: code === "NOMINALIA_SMTP_NOT_CONFIGURED" ? 503 : 502 });
    }
  }
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
