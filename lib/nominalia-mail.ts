import nodemailer from "nodemailer";

export const inboxRecipients: Record<string, string> = {
  geral: "geral@deligotriunfal.site",
  comercial: "comercial@deligotriunfal.site",
  carreiras: "carreiras@deligotriunfal.site",
};

/** Mailbox access is enforced server-side and mirrored by the UI. */
export const inboxAreas = Object.keys(inboxRecipients);
const inboxAreasByRole: Record<string, string[]> = {
  SUPER_ADMIN: inboxAreas,
  CEO: inboxAreas,
  SUPERVISOR: ["geral", "comercial"],
  OPERATIONS_SUPERVISOR: ["geral", "comercial"],
  CUSTOMER_SUPPORT: ["geral"],
  MARKETING: ["comercial"],
  FINANCE: [],
  FINANCE_DIRECTOR: [],
  FIELD: [],
};

export function inboxAreasForRole(role: string | null | undefined) {
  return [...(inboxAreasByRole[String(role || "").toUpperCase()] || [])];
}

export function canAccessInboxArea(role: string | null | undefined, area: string | null | undefined) {
  return Boolean(area && inboxAreasForRole(role).includes(area));
}

export function inboxSendersForRole(role: string | null | undefined) {
  return inboxAreasForRole(role).map(area => inboxRecipients[area]).filter(Boolean);
}

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

function escapeHtml(value: string) {
  return value.replace(/[&<>\"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '\"': "&quot;", "'": "&#39;" }[character] || character));
}

function letterheadHtml(message: string) {
  const body = escapeHtml(message).replace(/\r?\n/g, "<br>");
  return `<!doctype html><html><body style="margin:0;background:#f4f6f8;font-family:Arial,sans-serif;color:#17202b"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f8"><tr><td align="center" style="padding:16px 8px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:760px;background:#ffffff;border:1px solid #d9e0e7"><tr><td style="padding:18px 24px 14px;border-top:5px solid #b8172b;border-bottom:2px solid #d9a400"><div style="font-size:24px;font-weight:800;letter-spacing:1px;color:#171717">DELIGO</div><div style="margin-top:2px;font-size:13px;font-weight:700;letter-spacing:2px;color:#b8172b">TRIUNFAL, LDA.</div><div style="margin-top:9px;font-size:11px;color:#5f6b76">Technology · Digital Solutions · Innovation</div><div style="margin-top:7px;font-size:10px;color:#5f6b76">geral@deligotriunfal.site · comercial@deligotriunfal.site · carreiras@deligotriunfal.site</div></td></tr><tr><td style="padding:24px;vertical-align:top;font-size:16px;line-height:1.55;word-break:break-word"><div style="white-space:normal">${body}</div></td></tr><tr><td style="padding:12px 24px;border-top:1px solid #e6eaee;font-size:10px;color:#687582">DeliGo Triunfal, Lda. · Maputo, Moçambique</td></tr></table></td></tr></table></body></html>`;
}

function configuredAddresses() {
  return [...new Set([
    ...Object.values(inboxRecipients),
    env("NOMINALIA_SMTP_USER"),
    env("NOMINALIA_FROM_EMAIL"),
    env("NOMINALIA_SUPPORT_EMAIL"),
  ].flatMap(value => String(value || "").split(",").map(normalizeAddress).filter(value => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value))))];
}
export function centralSubject(subject: string, reply = false) {
  const base = subject.replace(/^(?:\s*re:\s*)+/i, "").replace(/^(?:\s*\[deligo central\]\s*)+/i, "").trim() || "Sem assunto";
  return `${reply ? "Re: " : ""}[DeliGo Central] ${base}`;
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
    subject: centralSubject(message.subject),
    text: lines.join("\n"),
    html: letterheadHtml(lines.join("\n")),
  });
  return { recipient, messageId: info.messageId, response: info.response, accepted: info.accepted, rejected: info.rejected };
}

export function configuredInboxSenders() {
  return configuredAddresses().filter(address => Boolean(smtpMailbox(address)));
}

export async function sendComposedInboxEmail(input: { from: string; to: string; cc?: string; bcc?: string; subject: string; text: string }) {
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
    ...(input.cc?.trim() ? { cc: input.cc.trim() } : {}),
    ...(input.bcc?.trim() ? { bcc: input.bcc.trim() } : {}),
    subject: input.subject,
    text: input.text,
    html: letterheadHtml(input.text),
  });
  return { recipient, messageId: info.messageId, response: info.response, accepted: info.accepted, rejected: info.rejected };
}
