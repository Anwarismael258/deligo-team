import { ImapFlow } from "imapflow";
import { stagingRest } from "@/lib/hq-server";

type Mailbox = { area: "geral" | "comercial" | "carreiras"; user: string; password: string };
type ImapResult = { mailbox: string; scanned: number; imported: number; skipped: number; error?: string };

const configuredHost = (process.env.NOMINALIA_IMAP_HOST || process.env.NOMINALIA_IMAP_SERVER || "pop.securemail.pro").trim();
const port = Number(process.env.NOMINALIA_IMAP_PORT || process.env.NOMINALIA_IMAP_SSL_PORT || 993);
const imapTimeoutMs = 20_000;

async function withTimeout<T>(operation: Promise<T>, label: string) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([operation, new Promise<T>((_, reject) => { timer = setTimeout(() => reject(new Error("IMAP_" + label + "_TIMEOUT")), imapTimeoutMs); })]);
  } finally { if (timer) clearTimeout(timer); }
}
function headerValue(raw: string, name: string) { return raw.match(new RegExp("^" + name + ":\\s*(.+(?:\\r?\\n[ \\t].+)*)$", "im"))?.[1].replace(/\r?\n[ \t]+/g, " ").trim() || ""; }
function decodeHeader(value: string) { return value.replace(/=\?UTF-8\?B\?([^?]+)\?=/gi, (_, encoded: string) => Buffer.from(encoded, "base64").toString("utf8")).replace(/=\?UTF-8\?Q\?([^?]+)\?=/gi, (_, encoded: string) => encoded.replace(/_/g, " ").replace(/=([0-9A-F]{2})/gi, (_match: string, hex: string) => String.fromCharCode(parseInt(hex, 16)))); }
function parseAddress(value: string) { const match = value.match(/^(?:.*?\s)?<([^<>\s]+@[^<>\s]+)>?$/); return match?.[1]?.trim().toLowerCase() || value.trim().toLowerCase(); }
function decodeTransfer(value: string, encoding: string) { if (encoding.toLowerCase() === "base64") return Buffer.from(value.replace(/\s/g, ""), "base64").toString("utf8"); if (encoding.toLowerCase() === "quoted-printable") return value.replace(/=\r?\n/g, "").replace(/=([0-9A-F]{2})/gi, (_, hex: string) => String.fromCharCode(parseInt(hex, 16))); return value; }
function stripHtml(value: string) { return value.replace(/<style[\s\S]*?<\/style>/gi, "").replace(/<script[\s\S]*?<\/script>/gi, "").replace(/<br\s*\/?>/gi, "\n").replace(/<\/p>/gi, "\n").replace(/<[^>]+>/g, "").replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&").replace(/&lt;/gi, "<").replace(/&gt;/gi, ">").replace(/\n{3,}/g, "\n\n").trim(); }
function mimeText(source: string, output: { plain: string[]; html: string[] }) {
  const split = source.search(/\r?\n\r?\n/); const header = split >= 0 ? source.slice(0, split) : source; const body = split >= 0 ? source.slice(split).replace(/^\r?\n\r?\n/, "") : "";
  const contentType = headerValue(header, "Content-Type") || "text/plain"; const transfer = headerValue(header, "Content-Transfer-Encoding");
  const boundaryMatch = contentType.match(/boundary\s*=\s*(?:"([^"]+)"|([^;\s]+))/i); const boundary = boundaryMatch?.[1] || boundaryMatch?.[2];
  if (boundary) { body.split("--" + boundary).slice(1).forEach(part => { if (!part.trim().startsWith("--")) mimeText(part, output); }); return; }
  const decoded = decodeTransfer(body, transfer); if (/^text\/html/i.test(contentType)) output.html.push(decoded); else if (/^text\//i.test(contentType)) output.plain.push(decoded);
}
function parseMail(source: Buffer) {
  const text = source.toString("utf8"); const split = text.search(/\r?\n\r?\n/); const header = split >= 0 ? text.slice(0, split) : text; const bodies = { plain: [] as string[], html: [] as string[] }; mimeText(text, bodies);
  const body = bodies.plain.join("\n\n").trim() || bodies.html.map(stripHtml).join("\n\n").trim(); const from = headerValue(header, "From");
  return { messageId: headerValue(header, "Message-ID") || headerValue(header, "Message-Id") || "raw-" + Buffer.from(source).toString("base64url").slice(0, 48), subject: decodeHeader(headerValue(header, "Subject") || "Sem assunto"), fromEmail: parseAddress(from), fromName: from.replace(/<[^>]+>/, "").replace(/"/g, "").trim() || parseAddress(from), body: body.slice(0, 50000), date: headerValue(header, "Date") };
}
async function fetchMailbox(mailbox: Mailbox, connectionHost: string): Promise<Buffer[]> {
  const client = new ImapFlow({ host: connectionHost, port, secure: true, auth: { user: mailbox.user, pass: mailbox.password }, logger: false, connectionTimeout: 20_000, greetingTimeout: 20_000, socketTimeout: 30_000 });
  await withTimeout(client.connect(), "CONNECT"); const lock = await withTimeout(client.getMailboxLock("INBOX"), "MAILBOX");
  try {
    const searchResult = await withTimeout(client.search({ all: true }, { uid: true }), "SEARCH"); const uids = Array.isArray(searchResult) ? searchResult : []; const messages: Buffer[] = [];
    await withTimeout((async () => { for await (const message of client.fetch(uids.slice(-50), { source: true }, { uid: true })) if (message.source) messages.push(Buffer.isBuffer(message.source) ? message.source : Buffer.from(message.source)); })(), "FETCH"); return messages;
  } finally { lock.release(); try { await withTimeout(client.logout(), "LOGOUT"); } catch { client.close(); } }
}
function mailboxFor(area: Mailbox["area"]): Mailbox | null {
  const key = area.toUpperCase();
  // Accept the documented IMAP names and the equivalent Nominalia names used
  // by older production environments. Secrets remain server-only.
  const user = process.env["NOMINALIA_IMAP_" + key + "_USER"]
    || process.env["NOMINALIA_IMAP_" + key + "_USERNAME"]
    || process.env["NOMINALIA_" + key + "_USER"]
    || process.env["NOMINALIA_" + key + "_USERNAME"]
    || process.env["NOMINALIA_" + key + "_EMAIL"]
    || process.env["NOMINALIA_" + key + "_ADDRESS"];
  const password = process.env["NOMINALIA_IMAP_" + key + "_PASSWORD"]
    || process.env["NOMINALIA_" + key + "_PASSWORD"]
    || process.env["NOMINALIA_" + key + "_PASS"];
  return user && password ? { area, user: user.trim(), password } : null;
}
function safeError(error: unknown) {
  const value = error && typeof error === "object" ? error as { message?: unknown; code?: unknown; name?: unknown } : {};
  const message = String(value.message || error || "unknown");
  const code = String(value.code || "").toUpperCase();
  if (/authentication|login|invalid credentials|auth|AUTHENTICATIONFAILED/i.test(message) || /AUTH|LOGIN|INVALID/i.test(code)) return "autenticação IMAP recusada";
  if (/certificate|TLS|SSL|handshake/i.test(message) || /CERT|TLS|SSL/i.test(code)) return "certificado/TLS IMAP recusado";
  if (/timeout|timed out|ETIMEDOUT|ECONNRESET/i.test(message) || /TIMEOUT|ETIMEDOUT|ECONNRESET/i.test(code)) return "tempo esgotado na ligação IMAP";
  if (/ENOTFOUND|EAI_AGAIN|ECONNREFUSED|EHOSTUNREACH/i.test(message) || /ENOTFOUND|EAI_AGAIN|ECONNREFUSED|EHOSTUNREACH/i.test(code)) return "servidor IMAP indisponível";
  return "ligação IMAP falhou";
}
export async function syncNominaliaMailboxes(): Promise<ImapResult[]> {
  const existing = await stagingRest("inbox_messages?select=meta&source=eq.nominalia_imap&limit=3000") as Array<{ meta?: Record<string, unknown> | null }>; const known = new Set(existing.map(row => String(row.meta?.message_id || "")).filter(Boolean));
  const results = await Promise.all((["geral", "comercial", "carreiras"] as const).map(async area => {
    const mailbox = mailboxFor(area); if (!mailbox) return { mailbox: area, scanned: 0, imported: 0, skipped: 0, error: "credenciais não configuradas" };
    try {
      const hosts = [...new Set([configuredHost, "pop.securemail.pro", "imap.securemail.pro"])].filter(Boolean); let sources: Buffer[] = []; let lastError: unknown;
      for (const connectionHost of hosts) { try { sources = await fetchMailbox(mailbox, connectionHost); lastError = undefined; break; } catch (error) { lastError = error; } } if (lastError) throw lastError;
      let imported = 0; let skipped = 0; for (const source of sources) { const mail = parseMail(source); if (known.has(mail.messageId)) { skipped += 1; continue; } await stagingRest("inbox_messages", { method: "POST", body: JSON.stringify({ area, source: "nominalia_imap", subject: mail.subject, from_name: mail.fromName, from_email: mail.fromEmail, body: mail.body, meta: { mailbox: mailbox.user, message_id: mail.messageId, received_at: mail.date || new Date().toISOString(), unread: true } }) }); known.add(mail.messageId); imported += 1; }
      return { mailbox: mailbox.user, scanned: sources.length, imported, skipped };
    } catch (error) { const safe = safeError(error); console.error("NOMINALIA_IMAP_MAILBOX_FAILED", { mailbox: mailbox.user, area, error: safe }); return { mailbox: mailbox.user, scanned: 0, imported: 0, skipped: 0, error: safe }; }
  }));
  return results;
}
