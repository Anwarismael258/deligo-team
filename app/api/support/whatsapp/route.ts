import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization } from "@/lib/hq-server";

const allowed = new Set(["SUPER_ADMIN", "FINANCE", "ADMIN", "ADMINISTRATOR", "SUPERVISOR", "OPERATIONS_SUPERVISOR", "CUSTOMER_SUPPORT", "SUPPORT_AGENT"]);

export async function POST(request: NextRequest) {
  const authorization = await corporateAuthorization();
  const actor = authorization?.actor;
  if (!actor || !allowed.has(String(actor.role).toUpperCase())) return NextResponse.json({ error: "Sem permissão para enviar WhatsApp." }, { status: 403 });
  const body = await request.json().catch(() => ({})) as { phone?: string; message?: string };
  const phone = String(body.phone || "").replace(/[^0-9]/g, "");
  const message = String(body.message || "").trim();
  if (phone.length < 9 || message.length < 1 || message.length > 4096) return NextResponse.json({ error: "Número ou mensagem inválidos." }, { status: 400 });
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER||process.env.WHATSAPP_PHONE_NUMBER_ID;
  if (!token || !phoneNumberId) return NextResponse.json({ error: "WhatsApp não está configurado no deployment." }, { status: 503 });
  const response = await fetch(`https://graph.facebook.com/v22.0/${phoneNumberId}/messages`, { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify({ messaging_product: "whatsapp", recipient_type: "individual", to: phone, type: "text", text: { preview_url: false, body: message } }), cache: "no-store" });
  const result = await response.json().catch(() => ({})) as { messages?: Array<{ id?: string }>; error?: { message?: string } };
  if (!response.ok) {
    const providerMessage = String(result.error?.message || "");
    if (/authentication|oauth|access token|invalid token/i.test(providerMessage)) return NextResponse.json({ error: "A Meta rejeitou a autenticação do WhatsApp. Gere um token válido com whatsapp_business_messaging e confirme o Phone Number ID no Vercel." }, { status: 502 });
    return NextResponse.json({ error: providerMessage || "A Meta recusou o envio. Fora da janela de 24 horas, use um template aprovado." }, { status: 502 });
  }
  return NextResponse.json({ ok: true, messageId: result.messages?.[0]?.id || null });
}
