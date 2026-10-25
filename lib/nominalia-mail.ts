import nodemailer from "nodemailer";

export const inboxRecipients: Record<string, string> = {
  geral: "geral@deligotriunfal.site",
  comercial: "comercial@deligotriunfal.site",
  carreiras: "carreiras@deligotriunfal.site",
};

const senderDisplayNames: Record<string, string> = {
  "geral@deligotriunfal.site": "DeliGo Geral",
  "comercial@deligotriunfal.site": "DeliGo Comercial",
  "carreiras@deligotriunfal.site": "DeliGo Carreiras",
};

function displayFrom(address: string) {
  const normalized = normalizeAddress(address);
  return `${senderDisplayNames[normalized] || "DeliGo Triunfal"} <${normalized}>`;
}

type InboxMessage = { id: string; area: string; source: string; subject: string; from_name: string; from_email: string; phone?: string | null; company?: string | null; body: string; created_at: string };

type SmtpMailbox = { address: string; user: string; password: string };

function env(name: string) {
  const value = process.env[name];
  return typeof value === "string" ? value.trim() : "";
}

function configured() {
  return Boolean(env("NOMINALIA_SMTP_USER") && env("NOMINALIA_SMTP_PASSWORD")) ||
    Object.keys(inboxRecipients).some(area => Boolean(env(`NOMINALIA_SMTP_${area.toUpperCase()}_PASSWORD`) || env(`NOMINALIA_IMAP_${area.toUpperCase()}_PASSWORD`)));
}

function normalizeAddress(value: string) {
  return value.trim().toLowerCase();
}

function transporterOptions(mailbox: SmtpMailbox) {
  const port = Number(env("NOMINALIA_SMTP_PORT") || 465);
  return {
    host: env("NOMINALIA_SMTP_HOST") || "authsmtp.securemail.pro",
    port,
    secure: port === 465,
    requireTLS: port === 587,
    connectionTimeout: 15_000,
    greetingTimeout: 15_000,
    socketTimeout: 20_000,
    auth: { user: mailbox.user, pass: mailbox.password },
  };
}

function smtpMailbox(address: string): SmtpMailbox | null {
  const normalized = normalizeAddress(address);
  const area = Object.entries(inboxRecipients).find(([, value]) => normalizeAddress(value) === normalized)?.[0];
  if (area) {
    const prefix = `NOMINALIA_SMTP_${area.toUpperCase()}`;
    const user = env(`${prefix}_USER`) || env(`NOMINALIA_IMAP_${area.toUpperCase()}_USER`) || normalized;
    const password = env(`${prefix}_PASSWORD`) || env(`NOMINALIA_IMAP_${area.toUpperCase()}_PASSWORD`);
    if (user && password) return { address: normalized, user, password };
  }
  const user = env("NOMINALIA_SMTP_USER");
  const password = env("NOMINALIA_SMTP_PASSWORD");
  if (user && password && normalizeAddress(user) === normalized) return { address: normalized, user, password };
  return null;
}

function configuredAddresses() {
  return [...new Set([
    ...Object.values(inboxRecipients),
    env("NOMINALIA_SMTP_USER"),
    env("NOMINALIA_FROM_EMAIL"),
    env("NOMINALIA_SUPPORT_EMAIL"),
  ].flatMap(value => String(value || "").split(",").map(normalizeAddress).filter(value => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value))))];
}

export async function sendInboxEmail(message: InboxMessage) {
  if (!configured()) throw new Error("NOMINALIA_SMTP_NOT_CONFIGURED");
  const recipient = inboxRecipients[message.area] || inboxRecipients.geral;
  const mailbox = smtpMailbox(recipient);
  if (!mailbox) throw new Error("NOMINALIA_SMTP_NOT_CONFIGURED");
  const transporter = nodemailer.createTransport(transporterOptions(mailbox));
  const lines = [`Área: ${message.area}`, `Origem: ${message.source}`, `Nome: ${message.from_name}`, `Email: ${message.from_email}`, message.phone ? `Telefone: ${message.phone}` : "", message.company ? `Empresa: ${message.company}` : "", `Recebido: ${new Date(message.created_at).toLocaleString("pt-MZ")}`, "", message.body].filter(Boolean);
  const info = await transporter.sendMail({
    from: displayFrom(mailbox.user),
    envelope: { from: mailbox.user, to: recipient },
    to: recipient,
    replyTo: message.from_email,
    subject: `[DeliGo Central] ${message.subject}`,
    text: lines.join("\n"),
  });
  return { recipient, messageId: info.messageId, response: info.response, accepted: info.accepted, rejected: info.rejected };
}

export function configuredInboxSenders() {
  return configuredAddresses().filter(address => Boolean(smtpMailbox(address)));
}

export async function sendComposedInboxEmail(input: { from: string; to: string; subject: string; text: string }) {
  if (!configured()) throw new Error("NOMINALIA_SMTP_NOT_CONFIGURED");
  const from = normalizeAddress(input.from);
  const mailbox = smtpMailbox(from);
  if (!mailbox) throw new Error("EMAIL_SENDER_NOT_ALLOWED");
  const transporter = nodemailer.createTransport(transporterOptions(mailbox));
  const recipient = input.to.trim();
  const info = await transporter.sendMail({
    from: displayFrom(mailbox.user),
    envelope: { from: mailbox.user, to: recipient },
    replyTo: mailbox.user,
    to: recipient,
    subject: input.subject,
    text: input.text,
  });
  return { recipient, messageId: info.messageId, response: info.response, accepted: info.accepted, rejected: info.rejected };
}
