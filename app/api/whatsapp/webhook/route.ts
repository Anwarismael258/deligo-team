import { createHmac, timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { hqRpc, supabaseUrl } from "@/lib/hq-server";

export const runtime = "nodejs";

const entity = "10000000-0000-0000-0000-000000000001";
const supportDepartment = "30000000-0000-0000-0000-000000000010";
const platformIds: Record<string, string> = {
  deligo: "20000000-0000-0000-0000-000000000001",
  comunhao: "20000000-0000-0000-0000-000000000002",
  taomoz: "20000000-0000-0000-0000-000000000003",
  sarca: "20000000-0000-0000-0000-000000000004",
  mestre24: "20000000-0000-0000-0000-000000000005",
};

function validVerifyToken(token: string | null) {
  const expected = process.env.WHATSAPP_VERIFY||process.env.WHATSAPP_VERIFY_TOKEN;
  return Boolean(token && expected && token.length === expected.length &&
    timingSafeEqual(Buffer.from(token), Buffer.from(expected)));
}
function validSignature(raw: string, signature: string | null) {
  const secret = process.env.META_APP_SECRET;
  if (!secret || !signature?.startsWith("sha256=")) return false;
  const suppliedHex = signature.slice(7);
  if (!/^[a-f0-9]{64}$/i.test(suppliedHex)) return false;
  const expected = createHmac("sha256", secret).update(raw).digest();
  const supplied = Buffer.from(suppliedHex, "hex");
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}
const apiHeaders = (key: string, schema: "hq" | "core" = "hq") => ({
  apikey: key, Authorization: `Bearer ${key}`,
  "Accept-Profile": schema, "Content-Profile": schema,
  "Content-Type": "application/json", Prefer: "return=representation",
});
async function rest(key: string, path: string, init: RequestInit = {}) {
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init, headers: { ...apiHeaders(key), ...(init.headers || {}) }, cache: "no-store",
  });
  if (!response.ok) throw new Error(`SUPPORT_DB_${response.status}: ${await response.text()}`);
  return response.status === 204 ? null : response.json();
}
function messageText(message: Record<string, any>): string {
  const type = String(message.type || "unknown");
  if (type === "text") return String(message.text?.body || "").trim();
  if (type === "button") return String(message.button?.text || "Resposta por botão").trim();
  if (type === "interactive") {
    const interactive = message.interactive || {};
    return String(interactive.button_reply?.title || interactive.list_reply?.title || "Resposta interativa").trim();
  }
  const caption = String(message[ type ]?.caption || "").trim();
  return caption ? `[${type}] ${caption}` : `[Mensagem WhatsApp do tipo: ${type}]`;
}
function escapeFilter(value: string) { return value.replace(/[,()"]/g, ""); }

// Meta verifies the webhook URL using this challenge.
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  if (params.get("hub.mode") === "subscribe" &&
      validVerifyToken(params.get("hub.verify_token")) &&
      params.get("hub.challenge") !== null) {
    return new NextResponse(params.get("hub.challenge"), { status: 200, headers: { "Content-Type": "text/plain" } });
  }
  return NextResponse.json({ error: "Webhook verification failed" }, { status: 403 });
}

export async function POST(request: NextRequest) {
  const raw = await request.text();
  if (!validSignature(raw, request.headers.get("x-hub-signature-256"))) {
    return NextResponse.json({ error: "Invalid webhook signature" }, { status: 401 });
  }

  let event: any;
  try { event = JSON.parse(raw); }
  catch { return NextResponse.json({ error: "Invalid JSON payload" }, { status: 400 }); }

  const changes = (event?.entry || []).flatMap((entry: any) => entry?.changes || []);
  const messageEvents = changes.flatMap((change: any) => {
    const value = change?.value || {};
    return (value.messages || []).map((message: any) => ({
      value, message, metadata: value.metadata || {},
      contacts: value.contacts || [],
    }));
  });
  // Delivery/read status events do not create support tickets.
  if (!messageEvents.length) return NextResponse.json({ received: true });

  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) {
    console.error("WHATSAPP_SUPPORT_NOT_CONFIGURED", { serviceKeyConfigured: false });
    return NextResponse.json({ error: "WhatsApp support integration is not fully configured" }, { status: 503 });
  }
  let systemEmployeeId = process.env.WHATSAPP_SYSTEM_EMPLOYEE_ID;
  try {
    if (!systemEmployeeId) {
      const systemEmployees = await rest(key, "employees?employee_code=eq.SYS-WHATSAPP&status=eq.active&select=id&limit=1");
      systemEmployeeId = Array.isArray(systemEmployees) ? systemEmployees[0]?.id : undefined;
    }
    if (!systemEmployeeId) {
      console.error("WHATSAPP_SYSTEM_EMPLOYEE_MISSING");
      return NextResponse.json({ error: "Apply the WhatsApp support migration or configure WHATSAPP_SYSTEM_EMPLOYEE_ID" }, { status: 503 });
    }
    let processed = 0;
    for (const item of messageEvents) {
      const message = item.message as Record<string, any>;
      const externalId = String(message.id || "");
      const sender = String(message.from || "").replace(/[^0-9]/g, "");
      const phoneNumberId = String(item.metadata.phone_number_id || "");
      if (!externalId || !sender || !phoneNumberId) continue;

      const expectedPhoneId = process.env.WHATSAPP_PHONE_NUMBER||process.env.WHATSAPP_PHONE_NUMBER_ID;
      if (expectedPhoneId && phoneNumberId !== expectedPhoneId) {
        console.warn("WHATSAPP_PHONE_NUMBER_ID_NOT_CONFIGURED_FOR_THIS_WEBHOOK", phoneNumberId);
        continue;
      }
      const platformSlug = (process.env.WHATSAPP_PLATFORM_SLUG || "deligo").toLowerCase();
      const platformId = platformIds[platformSlug];
      if (!platformId) {
        console.error("WHATSAPP_PLATFORM_SLUG_INVALID", platformSlug);
        return NextResponse.json({ error: "Invalid WhatsApp platform configuration" }, { status: 503 });
      }

      const duplicate = await rest(key, `support_conversations?select=id&external_message_id=eq.${encodeURIComponent(externalId)}&limit=1`);
      if (Array.isArray(duplicate) && duplicate.length) continue;

      const contact = (item.contacts || []).find((candidate: any) => String(candidate?.wa_id || "").replace(/[^0-9]/g, "") === sender);
      const customerName = String(contact?.profile?.name || sender);
      const text = messageText(message);
      if (!text) continue;

      let tickets = await rest(key,
        `support_tickets?select=*&source_channel=eq.whatsapp&platform_id=eq.${platformId}&customer_contact=eq.${encodeURIComponent("+" + sender)}&status=in.(open,in_analysis,waiting_customer,escalated)&order=updated_at.desc&limit=1`);
      if (!Array.isArray(tickets) || !tickets.length) {
        const created = await rest(key, "support_tickets", {
          method: "POST",
          body: JSON.stringify({
            platform_id: platformId, legal_entity_id: entity,
            department_id: supportDepartment, current_department_id: supportDepartment,
            created_by: systemEmployeeId, status: "open", priority: "normal",
            ticket_type: "whatsapp_message", category: "customer_support",
            subject: `WhatsApp — ${customerName}`, description: text,
            customer_name: customerName, customer_contact: "+" + sender,
            external_reference: `whatsapp:${sender}`, source_channel: "whatsapp",
          }),
        });
        const ticket = created?.[0];
        if (!ticket?.id) throw new Error("WHATSAPP_TICKET_CREATE_FAILED");
        tickets = [ticket];
        // Keep the shared routing/workflow logic. A dedicated system employee is configured in Vercel.
        await hqRpc("hq_route_support_ticket_v1", {
          p_ticket_id: ticket.id, p_department_code: "SUPPORT",
          p_actor_employee_id: systemEmployeeId,
          p_reason: "Novo contacto recebido pelo WhatsApp",
        });
      }
      const ticket = tickets[0];
      await rest(key, "support_conversations", {
        method: "POST",
        body: JSON.stringify({
          ticket_id: ticket.id, sender_type: "customer",
          sender_customer_reference: sender, message: text,
          is_internal: false, source_channel: "whatsapp", external_message_id: externalId,
        }),
      });
      await rest(key, `support_tickets?id=eq.${ticket.id}`, {
        method: "PATCH",
        body: JSON.stringify({ updated_at: new Date().toISOString(), status: "open", customer_name: customerName }),
      });
      await rest(key, "support_history", {
        method: "POST",
        body: JSON.stringify({
          ticket_id: ticket.id, event_type: "whatsapp_message_received",
          description: "Mensagem recebida pelo WhatsApp",
          actor_employee_id: systemEmployeeId,
          metadata: { external_message_id: externalId, source_channel: "whatsapp", message_type: message.type || "unknown" },
        }),
      });
      processed++;
    }
    return NextResponse.json({ received: true, processed });
  } catch (error) {
    console.error("WHATSAPP_SUPPORT_INGESTION_FAILED", String(error));
    return NextResponse.json({ error: "Could not persist WhatsApp support event" }, { status: 503 });
  }
}
