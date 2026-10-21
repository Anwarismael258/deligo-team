import nodemailer from "nodemailer";

export const inboxRecipients: Record<string, string> = {
  geral: "geral@deligotriunfal.site",
  comercial: "comercial@deligotriunfal.site",
  carreiras: "carreiras@deligotriunfal.site",
};

type InboxMessage = { id: string; area: string; source: string; subject: string; from_name: string; from_email: string; phone?: string | null; company?: string | null; body: string; created_at: string };

function configured() {
  return Boolean(process.env.NOMINALIA_SMTP_USER && process.env.NOMINALIA_SMTP_PASSWORD);
}

export async function sendInboxEmail(message: InboxMessage) {
  if (!configured()) throw new Error("NOMINALIA_SMTP_NOT_CONFIGURED");
  const recipient = inboxRecipients[message.area] || inboxRecipients.geral;
  const transporter = nodemailer.createTransport({ host: process.env.NOMINALIA_SMTP_HOST || "authsmtp.securemail.pro", port: Number(process.env.NOMINALIA_SMTP_PORT || 465), secure: true, auth: { user: process.env.NOMINALIA_SMTP_USER, pass: process.env.NOMINALIA_SMTP_PASSWORD } });
  const lines = [`Área: ${message.area}`, `Origem: ${message.source}`, `Nome: ${message.from_name}`, `Email: ${message.from_email}`, message.phone ? `Telefone: ${message.phone}` : "", message.company ? `Empresa: ${message.company}` : "", `Recebido: ${new Date(message.created_at).toLocaleString("pt-MZ")}`, "", message.body].filter(Boolean);
  await transporter.sendMail({ from: process.env.NOMINALIA_SMTP_USER, to: recipient, replyTo: message.from_email, subject: `[DeliGo Central] ${message.subject}`, text: lines.join("\n") });
  return recipient;
}
