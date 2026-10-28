import { NextRequest, NextResponse } from "next/server";
import { corporateActor, stagingRest } from "@/lib/hq-server";
import { centralSubject, configuredInboxSenders, inboxRecipients, inboxSendersForRole, sendComposedInboxEmail, sendInboxEmail } from "@/lib/nominalia-mail";

export const runtime = "nodejs";

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "EMAIL_FAILED";
}

function validAddressList(value: string) {
  return value.split(",").map(item => item.trim()).filter(Boolean).every(item => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(item));
}

function normalized(value: string) { return value.trim().toLowerCase(); }
function permittedSenders(role: string | null | undefined) { return new Set(inboxSendersForRole(role).map(normalized)); }
function areaForSender(sender: string) {
  const match = Object.entries(inboxRecipients).find(([, address]) => normalized(address) === normalized(sender));
  return match?.[0] || "geral";
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
    const allowed = actor && permittedSenders(actor.role);
    if (!actor || !allowed?.size) return NextResponse.json({ error: "Não existe uma caixa de email autorizada para este cargo." }, { status: 403 });
    return NextResponse.json({ senders: configuredInboxSenders().filter(sender => allowed.has(normalized(sender))) });
  } catch (error) {
    console.error("INBOX_EMAIL_GET_FAILED", errorMessage(error));
    return emailError(error, "Não foi possível carregar os remetentes autorizados.");
  }
}

export async function POST(request: NextRequest) {
  let actor;
  let body: { id?: string; replyToId?: string; from?: string; to?: string; cc?: string; bcc?: string; subject?: string; message?: string };
  try {
    actor = await corporateActor();
    if (!actor || !permittedSenders(actor.role).size) return NextResponse.json({ error: "Este cargo não tem acesso direto às caixas de email." }, { status: 403 });
    body = await request.json() as { id?: string; replyToId?: string; from?: string; to?: string; cc?: string; bcc?: string; subject?: string; message?: string };
  } catch (error) {
    console.error("INBOX_EMAIL_REQUEST_FAILED", errorMessage(error));
    return emailError(error, "Não foi possível preparar o envio de email.");
  }
  if (body.replyToId) {
    if (!body.from?.trim() || !body.to?.trim() || !body.subject?.trim() || !body.message?.trim()) return NextResponse.json({ error: "Remetente, destinatário, assunto e mensagem são obrigatórios." }, { status: 400 });
    if (!validAddressList(body.to) || body.to.length > 320) return NextResponse.json({ error: "Destinatário inválido." }, { status: 400 });
    if (body.subject.length > 200 || body.message.length > 10000) return NextResponse.json({ error: "Assunto ou mensagem demasiado longos." }, { status: 400 });
    try {
      const original = (await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(body.replyToId)}&select=*`))?.[0] as { area?: string; subject?: string; body?: string } | undefined;
      if (!original) return NextResponse.json({ error: "Mensagem original não encontrada." }, { status: 404 });
      const senderAllowed = permittedSenders(actor?.role).has(normalized(body.from));
      if (!senderAllowed || !inboxSendersForRole(actor?.role).some(address => areaForSender(address) === String(original.area || ""))) return NextResponse.json({ error: "Esta caixa não está autorizada para o seu cargo." }, { status: 403 });
      const quoted = [`${body.message.trim()}`, "", "--- Mensagem original ---", original.body?.trim() || "Sem conteúdo."].join("\n");
      const delivery = await sendComposedInboxEmail({ from: body.from, to: body.to, subject: centralSubject(body.subject.trim(), true), text: quoted });
      const replyMeta = { reply_smtp_accepted_at: new Date().toISOString(), reply_recipient: delivery.recipient, reply_smtp_message_id: delivery.messageId, reply_smtp_response: delivery.response, reply_smtp_accepted: delivery.accepted, reply_smtp_rejected: delivery.rejected };
      try {
        await stagingRest("inbox_replies", { method: "POST", body: JSON.stringify({ message_id: body.replyToId, author_id: actor.authUserId, kind: "resposta", body: body.message.trim(), send_status: "smtp_accepted" }) });
        const source = (await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(body.replyToId)}&select=meta`))?.[0] as { meta?: Record<string, unknown> | null } | undefined;
        await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(body.replyToId)}`, { method: "PATCH", body: JSON.stringify({ status: "respondido", meta: { ...(source?.meta || {}), ...replyMeta } }) });
      } catch (persistenceError) {
        console.error("INBOX_REPLY_PERSIST_FAILED", persistenceError instanceof Error ? persistenceError.message : "unknown");
      }
      return NextResponse.json({ ok: true, recipient: delivery.recipient, delivery: { status: "smtp_accepted", messageId: delivery.messageId, response: delivery.response, accepted: delivery.accepted, rejected: delivery.rejected } });
    } catch (error) {
      console.error("INBOX_REPLY_SEND_FAILED", errorMessage(error));
      return emailError(error, "Não foi possível enviar a resposta por email.");
    }
  }
  if (body.to || body.subject || body.message || body.from) {
    if (!body.from?.trim() || !body.to?.trim() || !body.subject?.trim() || !body.message?.trim()) return NextResponse.json({ error: "Remetente, destinatário, assunto e mensagem são obrigatórios." }, { status: 400 });
    if (!validAddressList(body.to) || body.to.length > 320) return NextResponse.json({ error: "Destinatário inválido." }, { status: 400 });
    if ((body.cc && (!validAddressList(body.cc) || body.cc.length > 320)) || (body.bcc && (!validAddressList(body.bcc) || body.bcc.length > 320))) return NextResponse.json({ error: "Cc ou Cco inválido." }, { status: 400 });
    if (body.subject.length > 200 || body.message.length > 10000) return NextResponse.json({ error: "Assunto ou mensagem demasiado longos." }, { status: 400 });
    try {
      if (!permittedSenders(actor?.role).has(normalized(body.from))) return NextResponse.json({ error: "Este remetente não está autorizado para o seu cargo." }, { status: 403 });
      const delivery = await sendComposedInboxEmail({ from: body.from, to: body.to, cc: body.cc, bcc: body.bcc, subject: body.subject.trim(), text: body.message.trim() });
      const recipient = delivery.recipient;
      try {
        const outbound = (await stagingRest("inbox_messages", { method: "POST", body: JSON.stringify({ area: areaForSender(body.from), source: "email", subject: body.subject.trim(), from_name: "Central HQ", from_email: body.from.trim().toLowerCase(), body: body.message.trim(), meta: { outbound: true, recipient } }) }))?.[0];
        if (outbound?.id) {
          // inbox_replies is a shared staging contract and does not have a
          // metadata column in production. Keep delivery evidence on the
          // outbound message instead of making the whole send look failed.
          await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(outbound.id)}`, {
            method: "PATCH",
            body: JSON.stringify({
              meta: {
                outbound: true,
                recipient,
                smtp_message_id: delivery.messageId,
                smtp_response: delivery.response,
                smtp_accepted: delivery.accepted,
                smtp_rejected: delivery.rejected,
                sent_at: new Date().toISOString(),
              },
            }),
          });
          await stagingRest("inbox_replies", { method: "POST", body: JSON.stringify({ message_id: outbound.id, author_id: actor.authUserId, kind: "resposta", body: `Para: ${recipient}\n\n${body.message.trim()}`, send_status: "smtp_accepted" }) });
        }
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
    if (!inboxSendersForRole(actor?.role).some(address => areaForSender(address) === String(message.area || ""))) return NextResponse.json({ error: "Esta caixa não está autorizada para o seu cargo." }, { status: 403 });
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
