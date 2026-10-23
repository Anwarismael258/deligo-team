import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, supabaseUrl } from "@/lib/hq-server";

const allowedRoles = new Set(["SUPER_ADMIN", "SUPERVISOR", "CUSTOMER_SUPPORT", "FINANCE", "ACCOUNTING"]);
const allowedTypes = new Set(["image/jpeg", "image/png", "image/webp", "image/gif", "application/pdf"]);
const maxBytes = 10 * 1024 * 1024;

export async function POST(request: NextRequest) {
  const authorization = await corporateAuthorization();
  const role = String(authorization?.actor?.role || "").toUpperCase();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const bucket = process.env.HQ_SUPPORT_ATTACHMENTS_BUCKET;
  if (!authorization || !key || !allowedRoles.has(role)) return NextResponse.json({ error: "Sem permissão para anexar ficheiros." }, { status: 403 });
  if (!bucket) return NextResponse.json({ error: "O armazenamento de anexos de suporte ainda não está configurado no deployment." }, { status: 503 });
  const form = await request.formData();
  const ticketId = String(form.get("ticketId") || "");
  const channel = String(form.get("channel") || "").toLowerCase();
  const contact = String(form.get("contact") || "").replace(/[^0-9]/g, "");
  const file = form.get("file");
  if (!ticketId || !(file instanceof File)) return NextResponse.json({ error: "Selecione um ficheiro e um atendimento." }, { status: 400 });
  if (!allowedTypes.has(file.type)) return NextResponse.json({ error: "Formato não permitido. Use JPG, PNG, WEBP, GIF ou PDF." }, { status: 400 });
  if (file.size <= 0 || file.size > maxBytes) return NextResponse.json({ error: "O ficheiro deve ter até 10 MB." }, { status: 400 });
  const safeName = file.name.normalize("NFKD").replace(/[^a-zA-Z0-9._-]/g, "_").slice(-120) || "anexo";
  const path = `support/${ticketId}/${crypto.randomUUID()}-${safeName}`;
  const upload = await fetch(`${supabaseUrl()}/storage/v1/object/${encodeURIComponent(bucket)}/${path.split("/").map(encodeURIComponent).join("/")}`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": file.type, "x-upsert": "false" },
    body: await file.arrayBuffer(),
    cache: "no-store",
  });
  if (!upload.ok) return NextResponse.json({ error: "Não foi possível guardar o anexo no armazenamento seguro." }, { status: 502 });
  let whatsappMessageId: string | null = null;
  if (channel === "whatsapp") {
    const token = process.env.WHATSAPP_ACCESS_TOKEN;
    const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER||process.env.WHATSAPP_PHONE_NUMBER_ID;
    if (!token || !phoneNumberId || !contact) return NextResponse.json({ error: "WhatsApp não está configurado para este atendimento." }, { status: 503 });
    const mediaForm = new FormData();
    mediaForm.append("messaging_product", "whatsapp");
    mediaForm.append("type", file.type);
    mediaForm.append("file", file, file.name);
    const mediaResponse = await fetch(`https://graph.facebook.com/v22.0/${phoneNumberId}/media`, { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: mediaForm, cache: "no-store" });
    const mediaResult = await mediaResponse.json() as { id?: string; error?: { message?: string } };
    if (!mediaResponse.ok || !mediaResult.id) return NextResponse.json({ error: `WhatsApp recusou o anexo: ${mediaResult.error?.message || "media inválida"}` }, { status: 502 });
    const mediaType = file.type === "application/pdf" ? "document" : "image";
    const messageResponse = await fetch(`https://graph.facebook.com/v22.0/${phoneNumberId}/messages`, { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify({ messaging_product: "whatsapp", recipient_type: "individual", to: contact, type: mediaType, [mediaType]: { id: mediaResult.id, ...(mediaType === "document" ? { filename: file.name } : {}) } }), cache: "no-store" });
    const messageResult = await messageResponse.json() as { messages?: Array<{ id?: string }>; error?: { message?: string } };
    if (!messageResponse.ok) return NextResponse.json({ error: `WhatsApp recusou o envio: ${messageResult.error?.message || "não foi possível enviar"}` }, { status: 502 });
    whatsappMessageId = messageResult.messages?.[0]?.id || null;
  }
  return NextResponse.json({ storage_reference: `${bucket}/${path}`, file_name: file.name, mime_type: file.type, size_bytes: file.size, whatsapp_message_id: whatsappMessageId }, { status: 201 });
}
