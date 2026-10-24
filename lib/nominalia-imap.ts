import tls from "node:tls";
import { stagingRest } from "@/lib/hq-server";

type Mailbox = { area: "geral" | "comercial" | "carreiras"; user: string; password: string };
type ImapResult = { mailbox: string; scanned: number; imported: number; skipped: number; error?: string };

const host = process.env.NOMINALIA_IMAP_HOST || "pop.securemail.pro";
const port = Number(process.env.NOMINALIA_IMAP_PORT || 993);

function quote(value: string) { return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`; }
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

class ImapConnection {
  private socket: tls.TLSSocket;
  private buffer = Buffer.alloc(0);
  private tag = 0;
  private welcome: Promise<void>;
  constructor(private readonly user: string, private readonly password: string) {
    this.socket = tls.connect({ host, port, servername: host, rejectUnauthorized: true });
    this.socket.setTimeout(20_000);
    this.socket.on("data", chunk => { this.buffer = Buffer.concat([this.buffer, chunk]); });
    this.welcome = new Promise((resolve, reject) => { const onData = () => { if (this.buffer.includes(Buffer.from("\r\n"))) { this.socket.off("data", onData); resolve(); } }; this.socket.on("data", onData); this.socket.once("error", reject); });
  }
  private async command(command: string) {
    await this.welcome;
    const current = `A${String(++this.tag).padStart(4, "0")}`;
    const start = this.buffer.length;
    return await new Promise<Buffer>((resolve, reject) => {
      let settled = false;
      let timer: ReturnType<typeof setTimeout> | undefined;
      const finish = (callback: () => void) => { if (settled) return; settled = true; if (timer) clearTimeout(timer); this.socket.off("data", onData); this.socket.off("error", onError); callback(); };
      const onError = (error: Error) => finish(() => reject(error));
      const onData = () => { const text = this.buffer.subarray(start).toString("latin1"); if (new RegExp(`\\r?\\n${current} (OK|NO|BAD)`).test(text)) finish(() => resolve(this.buffer.subarray(start))); };
      this.socket.on("data", onData); this.socket.once("error", onError);
      this.socket.write(`${current} ${command}\r\n`);
      onData();
      timer = setTimeout(() => finish(() => reject(new Error(`IMAP_TIMEOUT_${command.split(" ")[0]}`))), 25_000);
    });
  }
  async fetchLatest() {
    await this.command(`LOGIN ${quote(this.user)} ${quote(this.password)}`);
    await this.command("SELECT INBOX");
    const search = (await this.command("UID SEARCH ALL")).toString("latin1");
    const ids = (search.match(/\\* SEARCH ([0-9 ]+)/)?.[1] || "").trim().split(/\\s+/).filter(Boolean).slice(-50);
    const messages: Buffer[] = [];
    for (const uid of ids) {
      const result = await this.command(`UID FETCH ${uid} (BODY.PEEK[])`);
      const text = result.toString("latin1"); const marker = text.match(/BODY\\[\\] \\{(\\d+)\\}/i); if (!marker || marker.index === undefined) continue;
      const start = marker.index + marker[0].length + 2; messages.push(result.subarray(start, start + Number(marker[1])));
    }
    await this.command("LOGOUT"); this.socket.end(); return messages;
  }
}

function mailboxFor(area: Mailbox["area"]): Mailbox | null {
  const key = area.toUpperCase(); const user = process.env[`NOMINALIA_IMAP_${key}_USER`] || process.env[`NOMINALIA_${key}_EMAIL`]; const password = process.env[`NOMINALIA_IMAP_${key}_PASSWORD`]; return user && password ? { area, user, password } : null;
}

export async function syncNominaliaMailboxes(): Promise<ImapResult[]> {
  const existing = await stagingRest("inbox_messages?select=meta&source=eq.nominalia_imap&limit=3000") as Array<{ meta?: Record<string, unknown> | null }>;
  const known = new Set(existing.map(row => String(row.meta?.message_id || "")).filter(Boolean));
  const results: ImapResult[] = [];
  for (const area of ["geral", "comercial", "carreiras"] as const) {
    const mailbox = mailboxFor(area); if (!mailbox) { results.push({ mailbox: area, scanned: 0, imported: 0, skipped: 0, error: "credenciais não configuradas" }); continue; }
    try {
      const sources = await new ImapConnection(mailbox.user, mailbox.password).fetchLatest(); let imported = 0; let skipped = 0;
      for (const source of sources) { const mail = parseMail(source); if (known.has(mail.messageId)) { skipped += 1; continue; } await stagingRest("inbox_messages", { method: "POST", body: JSON.stringify({ area, source: "nominalia_imap", subject: mail.subject, from_name: mail.fromName, from_email: mail.fromEmail, body: mail.body, meta: { mailbox: mailbox.user, message_id: mail.messageId, received_at: mail.date || new Date().toISOString(), unread: true } }) }); known.add(mail.messageId); imported += 1; }
      results.push({ mailbox: mailbox.user, scanned: sources.length, imported, skipped });
    } catch (error) {
      console.error("NOMINALIA_IMAP_MAILBOX_FAILED", { mailbox: mailbox.user, area, error: error instanceof Error ? error.message : "unknown" });
      results.push({ mailbox: mailbox.user, scanned: 0, imported: 0, skipped: 0, error: "ligação IMAP falhou" });
    }
  }
  return results;
}
