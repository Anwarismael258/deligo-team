import { hqServiceKey, stagingRest, supabaseUrl } from "@/lib/hq-server";

type LoanApplication = Record<string, unknown>;
type PacketKind = "submitted" | "confirmed";

const normalizePhone = (value: unknown) => {
  const digits = String(value || "").replace(/\D/g, "");
  const normalized = digits.startsWith("258") ? `+${digits}` : `+258${digits.replace(/^0/, "")}`;
  return /^\+258\d{9}$/.test(normalized) ? normalized : null;
};

const pdfText = (value: unknown) => String(value ?? "").replace(/[^\x20-\x7e]/g, "?").replace(/\\/g, "\\\\").replace(/\(/g, "\\(").replace(/\)/g, "\\)");

function makePdf(lines: string[]) {
  const content = `BT /F1 10 Tf 40 800 Td ${lines.slice(0, 52).map((line, index) => `${index ? "0 -16 Td " : ""}(${pdfText(line.slice(0, 110))}) Tj`).join(" ")} ET`;
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
  ];
  let output = "%PDF-1.4\n";
  const offsets = [0];
  objects.forEach((object, index) => { offsets.push(output.length); output += `${index + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = output.length;
  output += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n${offsets.slice(1).map(offset => `${String(offset).padStart(10, "0")} 00000 n `).join("\n")}\ntrailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return Buffer.from(output, "latin1");
}

function privilegedHeaders(extra: Record<string, string> = {}) {
  const key = hqServiceKey();
  if (!key) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
  return { apikey: key, ...(key.startsWith("sb_secret_") ? {} : { Authorization: `Bearer ${key}` }), ...extra };
}

async function uploadPdf(application: LoanApplication, kind: PacketKind) {
  const id = String(application.id || "");
  const path = `loan-packets/${id}/${kind}.pdf`;
  const response = await fetch(`${supabaseUrl()}/storage/v1/object/loan-documents/${path}`, {
    method: "POST",
    headers: privilegedHeaders({ "Content-Type": "application/pdf", "x-upsert": "true" }),
    body: makePdf([
      "DELiGO TRIUNFAL, LDA.",
      kind === "confirmed" ? "CONFIRMACAO DO PEDIDO DE MICROCredITO" : "COMPROVATIVO DE PEDIDO DE MICROCredITO",
      "",
      `Referencia: ${application.reference || id}`,
      `Cliente: ${application.full_name || "-"}`,
      `Telefone: ${application.phone || "-"}`,
      `Valor: ${application.amount || 0} MZN`,
      `Total a pagar: ${application.total_due || 0} MZN`,
      `Estado: ${kind === "confirmed" ? "CONFIRMADO" : "RECEBIDO"}`,
      `Data: ${new Date().toLocaleString("pt-MZ")}`,
      "",
      kind === "confirmed" ? "A Central confirmou a recepcao e analise deste pedido." : "Este documento confirma a recepcao do pedido pela Central.",
    ]),
    cache: "no-store",
  });
  if (!response.ok) throw new Error(`MICROCREDIT_PDF_UPLOAD_FAILED:${await response.text()}`);
  const signedResponse = await fetch(`${supabaseUrl()}/storage/v1/object/sign/loan-documents/${path}`, {
    method: "POST", headers: privilegedHeaders({ "Content-Type": "application/json" }), body: JSON.stringify({ expiresIn: 900 }), cache: "no-store",
  });
  if (!signedResponse.ok) throw new Error(`MICROCREDIT_PDF_SIGN_FAILED:${await signedResponse.text()}`);
  const signedBody = await signedResponse.json() as { signedURL?: string; signedUrl?: string };
  const signedUrl = signedBody.signedURL || signedBody.signedUrl;
  if (!signedUrl) throw new Error("MICROCREDIT_PDF_SIGN_MISSING");
  return { path, url: signedUrl.startsWith("http") ? signedUrl : `${supabaseUrl()}${signedUrl}` };
}

async function sendViaLovableWhatsApp(to: string, url: string, filename: string, caption: string) {
  const endpoint = process.env.LOVABLE_WHATSAPP_DISPATCH_URL?.trim();
  if (!endpoint) return null;
  const secret = process.env.LOVABLE_WHATSAPP_DISPATCH_SECRET?.trim();
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (secret) headers.Authorization = `Bearer ${secret}`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers,
    body: JSON.stringify({
      channel: "whatsapp",
      recipient: to,
      document_url: url,
      filename,
      caption,
    }),
    cache: "no-store",
  });
  const result = await response.json().catch(() => ({})) as { message_id?: string; id?: string; error?: string };
  if (!response.ok) throw new Error(`LOVABLE_WHATSAPP_SEND_FAILED:${result.error || response.status}`);
  return result.message_id || result.id || null;
}

async function sendWhatsAppDocument(to: string, url: string, filename: string, caption: string) {
  const lovableMessageId = await sendViaLovableWhatsApp(to, url, filename, caption);
  if (process.env.LOVABLE_WHATSAPP_DISPATCH_URL?.trim()) return lovableMessageId;
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER || process.env.WHATSAPP_PHONE_NUMBER_ID;
  if (!token || !phoneNumberId) throw new Error("WHATSAPP_OUTBOUND_NOT_CONFIGURED");
  const response = await fetch(`https://graph.facebook.com/v22.0/${phoneNumberId}/messages`, {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", recipient_type: "individual", to: to.replace(/^\+/, ""), type: "document", document: { link: url, filename, caption } }), cache: "no-store",
  });
  const result = await response.json().catch(() => ({})) as { error?: { message?: string }; messages?: Array<{ id?: string }> };
  if (!response.ok) throw new Error(`WHATSAPP_SEND_FAILED:${result.error?.message || response.status}`);
  return result.messages?.[0]?.id || null;
}

async function claimDelivery(applicationId: string, kind: PacketKind, recipientType: string, recipientPhone: string, pdfPath: string) {
  const existing = await stagingRest(`loan_application_deliveries?application_id=eq.${encodeURIComponent(applicationId)}&packet_type=eq.${kind}&recipient_type=eq.${recipientType}&recipient_phone=eq.${encodeURIComponent(recipientPhone)}&select=id,status&limit=1`) as Array<Record<string, unknown>>;
  if (existing?.[0]) {
    if (existing[0].status === "sent" || existing[0].status === "sending") return null;
    await stagingRest(`loan_application_deliveries?id=eq.${encodeURIComponent(String(existing[0].id))}`, { method: "PATCH", body: JSON.stringify({ status: "sending", error_message: null, pdf_path: pdfPath }) });
    return existing[0];
  }
  const rows = await stagingRest("loan_application_deliveries", {
    method: "POST",
    headers: { Prefer: "resolution=ignore-duplicates,return=representation" },
    body: JSON.stringify({ application_id: applicationId, packet_type: kind, recipient_type: recipientType, recipient_phone: recipientPhone, pdf_path: pdfPath, status: "sending" }),
  }) as Array<Record<string, unknown>>;
  return rows?.[0] || null;
}

async function finishDelivery(id: string, patch: Record<string, unknown>) {
  await stagingRest(`loan_application_deliveries?id=eq.${encodeURIComponent(id)}`, { method: "PATCH", body: JSON.stringify(patch) });
}

export async function dispatchMicrocreditPacket(application: LoanApplication, kind: PacketKind) {
  const applicationId = String(application.id || "");
  if (!applicationId) throw new Error("MICROCREDIT_APPLICATION_ID_MISSING");
  const clientPhone = normalizePhone(application.phone);
  const companyPhone = normalizePhone(process.env.MICROCREDIT_COMPANY_WHATSAPP || process.env.WHATSAPP_MICROCREDIT_RECIPIENT);
  const recipients = [
    clientPhone ? { type: "client", phone: clientPhone } : null,
    companyPhone ? { type: "company", phone: companyPhone } : null,
  ].filter(Boolean) as Array<{ type: string; phone: string }>;
  if (!recipients.length) throw new Error("MICROCREDIT_WHATSAPP_RECIPIENTS_NOT_CONFIGURED");
  const packet = await uploadPdf(application, kind);
  const results: Array<{ recipient: string; sent: boolean; messageId?: string | null }> = [];
  for (const recipient of recipients) {
    const claimed = await claimDelivery(applicationId, kind, recipient.type, recipient.phone, packet.path);
    if (!claimed) { results.push({ recipient: recipient.type, sent: true }); continue; }
    try {
      const messageId = await sendWhatsAppDocument(recipient.phone, packet.url, `${kind === "confirmed" ? "confirmacao" : "pedido"}-${application.reference || applicationId}.pdf`, kind === "confirmed" ? "Pedido de microcrédito confirmado pela Central DeliGo Triunfal." : "Pedido de microcrédito recebido pela Central DeliGo Triunfal.");
      await finishDelivery(String(claimed.id), { status: "sent", whatsapp_message_id: messageId, sent_at: new Date().toISOString() });
      results.push({ recipient: recipient.type, sent: true, messageId });
    } catch (error) {
      await finishDelivery(String(claimed.id), { status: "failed", error_message: error instanceof Error ? error.message.slice(0, 500) : "unknown" });
      throw error;
    }
  }
  return { packetPath: packet.path, results };
}

export function microcreditDispatchSecretMatches(value: string | null) {
  const expected = process.env.MICROCREDIT_INGEST_SECRET?.trim();
  return Boolean(expected && value && value === expected);
}

