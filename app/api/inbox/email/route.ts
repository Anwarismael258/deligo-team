import { NextRequest, NextResponse } from "next/server";
import { corporateActor, stagingRest } from "@/lib/hq-server";
import { configuredInboxSenders, sendComposedInboxEmail, sendInboxEmail } from "@/lib/nominalia-mail";

export const runtime = "nodejs";

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "EMAIL_FAILED";
}

function emailError(error: unknown, fallback: string) {
  const code = errorMessage(error);
  const normalized = code.toLowerCase();
  const message = code === "NOMINALIA_SMTP_NOT_CONFIGURED"
    ? "SMTP da caixa selecionada não está configurado no ambiente de produção."
    : code === "EMAIL_SENDER_NOT_ALLOWED"
      ? "Remetente não autorizado. Escolha uma das caixas Nominalia configuradas."
      : /eauth|authentication|invalid login|535/.test(normalized)
        ? "A autenticação SMTP falhou. Confirme a palavra-passe da caixa selecionada na Vercel."
        : /timeout|timed out|enotfound|econn|connection/.test(normalized)
          ? "Não foi possível ligar ao servidor SMTP da Nominalia."
          : /rejected|recipient|550|553/.test(normalized)
            ? "O servidor SMTP rejeitou o envio ou o destinatário."
            : fallback;
  console.error("INBOX_EMAIL_SAFE_ERROR", { code: code.slice(0, 240) });
  return NextResponse.json({ error: message }, { status: code === "NOMINALIA_SMTP_NOT_CONFIGURED" ? 503 : 502 });
}

export async function GET() {
  try {
    const actor = await corporateActor();
    if (!actor || !["SUPER_ADMIN", "FINANCE"].includes(actor.role)) return NextResponse.json({ error: "Apenas o Administrador ou Finanças podem enviar email." }, { status: 403 });
    return NextResponse.json({ senders: configuredInboxSenders() });
  } catch (error) {
    console.error("INBOX_EMAIL_GET_FAILED", errorMessage(error));
    return emailError(error, "Não foi possível carregar os remetentes autorizados.");
  }
}

export async function POST(request: NextRequest) {
  let actor;
  let body: { id?: string; from?: string; to?: string; subject?: string; message?: string };
  try {
    actor = await corporateActor();
    if (!actor || !["SUPER_ADMIN", "FINANCE"].includes(actor.role)) return NextResponse.json({ error: "Apenas o Administrador ou Finanças podem enviar email." }, { status: 403 });
    body = await request.json() as { id?: string; from?: string; to?: string; subject?: string; message?: string };
  } catch (error) {
    console.error("INBOX_EMAIL_REQUEST_FAILED", errorMessage(error));
    return emailError(error, "Não foi possível preparar o envio de email.");
  }
  if (body.to || body.subject || body.message || body.from) {
    if (!body.from?.trim() || !body.to?.trim() || !body.subject?.trim() || !body.message?.trim()) return NextResponse.json({ error: "Remetente, destinatário, assunto e mensagem são obrigatórios." }, { status: 400 });
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.to) || body.to.length > 320) return NextResponse.json({ error: "Destinatário inválido." }, { status: 400 });
    if (body.subject.length > 200 || body.message.length > 10000) return NextResponse.json({ error: "Assunto ou mensagem demasiado longos." }, { status: 400 });
    try {
      const delivery = await sendComposedInboxEmail({ from: body.from, to: body.to, subject: body.subject.trim(), text: body.message.trim() });
      const recipient = delivery.recipient;
      try {
        const outbound = (await stagingRest("inbox_messages", { method: "POST", body: JSON.stringify({ area: "geral", source: "email", subject: body.subject.trim(), from_name: "Central HQ", from_email: body.from.trim().toLowerCase(), body: body.message.trim(), meta: { outbound: true, recipient } }) }))?.[0];
        if (outbound?.id) await stagingRest("inbox_replies", { method: "POST", body: JSON.stringify({ message_id: outbound.id, author_id: actor.authUserId, kind: "resposta", body: `Para: ${recipient}\n\n${body.message.trim()}`, send_status: "smtp_accepted", metadata: { message_id: delivery.messageId, response: delivery.response, accepted: delivery.accepted, rejected: delivery.rejected } }) });
      } catch (persistenceError) {
        console.error("INBOX_OUTBOUND_EMAIL_PERSIST_FAILED", persistenceError instanceof Error ? persistenceError.message : "unknown");
      }
      return NextResponse.json({ ok: true, recipient, delivery: { status: "smtp_accepted", messageId: delivery.messageId, response: delivery.response, accepted: delivery.accepted, rejected: delivery.rejected } });
    } catch (error) {
      console.error("INBOX_EMAIL_SEND_FAILED", errorMessage(error));
      return emailError(error, "Não foi possível enviar o email.");
    }
  }
  if (!body.id) return NextResponse.json({ error: "Mensagem inválida." }, { status: 400 });
  try {
    const message = (await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(body.id)}&select=*`))[0];
    if (!message) return NextResponse.json({ error: "Mensagem não encontrada." }, { status: 404 });
    const delivery = await sendInboxEmail(message);
    const recipient = delivery.recipient;
    const meta = { ...(message.meta || {}), email_smtp_accepted_at: new Date().toISOString(), email_recipient: recipient, smtp_message_id: delivery.messageId, smtp_response: delivery.response, smtp_accepted: delivery.accepted, smtp_rejected: delivery.rejected };
    await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ meta }) });
    return NextResponse.json({ ok: true, recipient, delivery: { status: "smtp_accepted", messageId: delivery.messageId, response: delivery.response, accepted: delivery.accepted, rejected: delivery.rejected } });
  } catch (error) {
    console.error("INBOX_EMAIL_EXISTING_SEND_FAILED", errorMessage(error));
    return emailError(error, "Não foi possível enviar o email.");
  }
}
