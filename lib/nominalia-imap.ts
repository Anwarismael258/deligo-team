import { ImapFlow } from "imapflow";
import { stagingRest } from "@/lib/hq-server";

type Mailbox = { area: "geral" | "comercial" | "carreiras"; user: string; password: string };
type ImapResult = { mailbox: string; scanned: number; imported: number; skipped: number; error?: string };

const host = process.env.NOMINALIA_IMAP_HOST || "pop.securemail.pro";
const port = Number(process.env.NOMINALIA_IMAP_PORT || 993);

function headerValue(raw: string, name: string) { return raw.match(new RegExp(`^${name}:\\s*(.+(?:\\r?\\n[ \\t].+)*)$`, "im"))?.[1].replace(/\\r?\\n[ \\t]+/g, " ").trim() || ""; }
function decodeHeader(value: string) { return value.replace(/=\\?UTF-8\\?B\\?([^?]+)\\?=/gi, (_, encoded: string) => Buffer.from(encoded, "base64").toString("utf8")).replace(/=\\?UTF-8\\?Q\\?([^?]+)\\?=/gi, (_, encoded: string) => encoded.replace(/_/g, " ").replace(/=([0-9A-F]{2})/gi, (_match: string, hex: string) => String.fromCharCode(parseInt(hex, 16)))); }
function parseAddress(value: string) { const match = value.match(/^(?:.*?\\s)?<?([^<>\\s]+@[^<>\\s]+)>?$/); return match?.[1]?.trim().toLowerCase() || value.trim().toLowerCase(); }
function parseMail(source: Buffer) {
  const text = source.toString("utf8");
  const split = text.search(/\\r?\\n\\r?\\n/);
  const header = split >= 0 ? text.slice(0, split) : text;
  const body = split >= 0 ? text.slice(split).replace(/^\\r?\\n\\r?\\n/, "") : "";
  const messageId = headerValue(header, "Message-ID") || headerValue(header, "Message-Id") || `raw-${Buffer.from(source).toString("base64url").slice(0, 48)}`;
  const from = headerValue(header, "From");
  return { messageId, subject: decodeHeader(headerValue(header, "Subject") || "Sem assunto"), fromEmail: parseAddress(from), fromName: from.replace(/<[^>]+>/, "").replace(/"/g, "").trim() || parseAddress(from), body: body.slice(0, 50000), date: headerValue(header, "Date") };
}

async function fetchMailbox(mailbox: Mailbox): Promise<Buffer[]> {
  const client = new ImapFlow({ host, port, secure: true, auth: { user: mailbox.user, pass: mailbox.password }, logger: false, connectionTimeout: 20_000, greetingTimeout: 20_000, socketTimeout: 30_000 });
  await client.connect();
  const lock = await client.getMailboxLock("INBOX");
  try {
    const searchResult = await client.search({ all: true }, { uid: true });
    const uids = Array.isArray(searchResult) ? searchResult : [];
    const messages: Buffer[] = [];
    for await (const message of client.fetch(uids.slice(-50), { source: true }, { uid: true })) {
      if (message.source) messages.push(Buffer.isBuffer(message.source) ? message.source : Buffer.from(message.source));
    }
    return messages;
  } finally { lock.release(); await client.logout(); }
}

function mailboxFor(area: Mailbox["area"]): Mailbox | null {
  const key = area.toUpperCase();
  const user = process.env[`NOMINALIA_IMAP_${key}_USER`] || process.env[`NOMINALIA_IMAP_${key}_USERNAME`] || process.env[`NOMINALIA_${key}_EMAIL`];
  const password = process.env[`NOMINALIA_IMAP_${key}_PASSWORD`];
  return user && password ? { area, user, password } : null;
}

function safeError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error || "unknown");
  if (/authentication|login|invalid credentials|auth/i.test(message)) return "autenticação IMAP recusada";
  if (/timeout|timed out|ETIMEDOUT|ECONNRESET/i.test(message)) return "tempo esgotado na ligação IMAP";
  if (/ENOTFOUND|EAI_AGAIN|ECONNREFUSED/i.test(message)) return "servidor IMAP indisponível";
  return "ligação IMAP falhou";
}

export async function syncNominaliaMailboxes(): Promise<ImapResult[]> {
  const existing = await stagingRest("inbox_messages?select=meta&source=eq.nominalia_imap&limit=3000") as Array<{ meta?: Record<string, unknown> | null }>;
  const known = new Set(existing.map(row => String(row.meta?.message_id || "")).filter(Boolean));
  const results: ImapResult[] = [];
  const mailboxResults = await Promise.all(([
    "geral", "comercial", "carreiras",
  ] as const).map(async (area) => {
    const mailbox = mailboxFor(area);
    if (!mailbox) return { mailbox: area, scanned: 0, imported: 0, skipped: 0, error: "credenciais não configuradas" };
    try {
      const sources = await fetchMailbox(mailbox); let imported = 0; let skipped = 0;
      for (const source of sources) {
        const mail = parseMail(source);
        if (known.has(mail.messageId)) { skipped += 1; continue; }
        await stagingRest("inbox_messages", { method: "POST", body: JSON.stringify({ area, source: "nominalia_imap", subject: mail.subject, from_name: mail.fromName, from_email: mail.fromEmail, body: mail.body, meta: { mailbox: mailbox.user, message_id: mail.messageId, received_at: mail.date || new Date().toISOString(), unread: true } }) });
        known.add(mail.messageId); imported += 1;
      }
      return { mailbox: mailbox.user, scanned: sources.length, imported, skipped };
    } catch (error) {
      const safe = safeError(error);
      console.error("NOMINALIA_IMAP_MAILBOX_FAILED", { mailbox: mailbox.user, area, error: safe });
      return { mailbox: mailbox.user, scanned: 0, imported: 0, skipped: 0, error: safe };
    }
  }));
  results.push(...mailboxResults);
  return results;
}
