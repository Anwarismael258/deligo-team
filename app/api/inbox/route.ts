import { NextRequest, NextResponse } from "next/server";
import { corporateActor, stagingRest } from "@/lib/hq-server";
import { inboxAreasForRole } from "@/lib/nominalia-mail";

const messageMeta = (message: Record<string, unknown>) => {
  const raw = message.meta;
  if (raw && typeof raw === "object") return raw as Record<string, unknown>;
  if (typeof raw === "string") {
    try { const parsed = JSON.parse(raw); return parsed && typeof parsed === "object" ? parsed as Record<string, unknown> : {}; } catch { return {}; }
  }
  return {};
};
const isOutbound = (message: Record<string, unknown>) => Boolean(messageMeta(message).outbound);

async function context() {
  const actor = await corporateActor();
  const areas = inboxAreasForRole(actor?.role);
  return actor && (actor.role === "SUPER_ADMIN" || actor.role === "CEO" || areas.length > 0) ? { actor, areas } : null;
}

export async function GET(req: NextRequest) {
  const ctx = await context();
  if (!ctx) return NextResponse.json({ error: "Sem acesso à caixa de entrada." }, { status: 403 });
  const requestedArea = req.nextUrl.searchParams.get("area");
  const selected = requestedArea && ctx.areas.includes(requestedArea) ? [requestedArea] : ctx.areas;
  if (!selected.length) return NextResponse.json({ messages: [], sentMessages: [], replies: [], allowedMailboxes: [], meta: { source: "staging.inbox_messages", received: 0, sent: 0, unread: 0 } });
  const query = new URLSearchParams({ select: "*", order: "created_at.desc", limit: "500", area: `in.(${selected.join(",")})` });
  try {
    const rawMessages = await stagingRest(`inbox_messages?${query.toString()}`) as Array<Record<string, unknown>>;
    const messages = rawMessages.filter(message => !isOutbound(message));
    const sentMessages = rawMessages.filter(isOutbound);
    const ids = new Set(rawMessages.map(message => String(message.id || "")));
    const allReplies = await stagingRest("inbox_replies?select=*&order=created_at.asc&limit=2000") as Array<Record<string, unknown>>;
    const replies = allReplies.filter(reply => ids.has(String(reply.message_id || "")));
    return NextResponse.json({ messages, sentMessages, replies, allowedMailboxes: ctx.areas, meta: { source: "staging.inbox_messages", received: messages.length, sent: sentMessages.length, unread: messages.filter(message => !messageMeta(message).read_at).length } });
  } catch { return NextResponse.json({ error: "Não foi possível carregar a caixa de entrada." }, { status: 500 }); }
}

export async function PATCH(req: NextRequest) {
  const ctx = await context();
  if (!ctx) return NextResponse.json({ error: "Sem acesso." }, { status: 403 });
  const body = await req.json() as { id?: string; status?: string; assigned_to?: string | null; kind?: "resposta" | "nota"; body?: string; read?: boolean };
  if (!body.id) return NextResponse.json({ error: "Mensagem inválida." }, { status: 400 });
  try {
    const message = (await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(body.id)}&select=*`))?.[0] as Record<string, unknown>;
    if (!message || !ctx.areas.includes(String(message.area))) return NextResponse.json({ error: "Mensagem fora do seu âmbito." }, { status: 403 });
    const currentMeta = messageMeta(message);
    if (body.status || body.assigned_to !== undefined || body.read !== undefined) await stagingRest(`inbox_messages?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ ...(body.status ? { status: body.status } : {}), ...(body.assigned_to !== undefined ? { assigned_to: body.assigned_to || null } : {}), ...(body.read !== undefined ? { meta: { ...currentMeta, read_at: body.read ? new Date().toISOString() : null } } : {}) }) });
    if (body.body?.trim()) await stagingRest("inbox_replies", { method: "POST", body: JSON.stringify({ message_id: body.id, author_id: ctx.actor.authUserId, kind: body.kind || "nota", body: body.body.trim(), send_status: "n/a" }) });
    return NextResponse.json({ ok: true });
  } catch { return NextResponse.json({ error: "Não foi possível guardar a alteração." }, { status: 409 }); }
}
