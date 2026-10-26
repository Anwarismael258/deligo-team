// Pure helpers shared by the form, server and tests. No provider credentials here.
const basic = new Set(Array.from("@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"));
const extended = new Set(Array.from("\f^{}\\[~]|€"));
export function smsSegments(message: string) {
  let units = 0;
  for (const char of message) {
    if (basic.has(char)) units++;
    else if (extended.has(char)) units += 2;
    else return { encoding: "Unicode", units: message.length, segments: message.length <= 70 ? 1 : Math.ceil(message.length / 67) };
  }
  return { encoding: "GSM-7", units, segments: units === 0 ? 0 : units <= 160 ? 1 : Math.ceil(units / 153) };
}
export function mozPhone(value: string) {
  const digits = value.replace(/\D/g, "");
  const phone = digits.length === 9 ? `258${digits}` : digits;
  return /^2588[2-7]\d{7}$/.test(phone) ? phone : null;
}
export function campaignMessage(value: unknown) {
  if (typeof value !== "string" || !value.trim() || value.length > 1000) throw new Error("Mensagem obrigatória, até 1000 caracteres.");
  return value.trim();
}
export type ProviderOutcome = { status: "accepted" | "failed" | "unknown"; reference?: string; cost?: number };
// Uncertain responses never trigger an automatic resend: the provider may have accepted it.
export async function sendMozeSms(config: { key: string; secret: string; sender: string }, phone: string, message: string, transport: typeof fetch = fetch): Promise<ProviderOutcome> {
  try {
    const response = await transport("https://api.mozesms.com/sms/send", {
      method: "POST", headers: { "Content-Type": "application/json", "X-API-Key": config.key, "X-API-Secret": config.secret },
      body: JSON.stringify({ phone, message, sender_id: config.sender }), signal: AbortSignal.timeout(15000),
    });
    if (response.status >= 400 && response.status < 500) return { status: "failed" };
    if (!response.ok) return { status: "unknown" };
    const result = await response.json();
    if (result.success === false) return { status: "failed" };
    if (result.success !== true || !result.data?.id) return { status: "unknown" };
    return { status: "accepted", reference: String(result.data.id), ...(typeof result.data.cost === "number" && Number.isFinite(result.data.cost) ? { cost: result.data.cost } : {}) };
  } catch { return { status: "unknown" }; }
}
export async function mozeBalance(config: { key: string; secret: string }, transport: typeof fetch = fetch) {
  const response = await transport("https://api.mozesms.com/account/balance", { headers: { "X-API-Key": config.key, "X-API-Secret": config.secret }, cache: "no-store", signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new Error("SMS_BALANCE_UNAVAILABLE");
  const result = await response.json();
  const balance = result.data?.balance, price = result.data?.unit_price_mzn;
  if (result.success !== true || result.data?.currency !== "MZN" || typeof balance !== "number" || !Number.isFinite(balance) || balance < 0 || typeof price !== "number" || !Number.isFinite(price) || price <= 0) throw new Error("SMS_BALANCE_INVALID");
  return { balance, unitPrice: price };
}
export function smsBudgetAllows(balance: number, unitPrice: number, segments: number, reserve: number) {
  return [balance, unitPrice, segments, reserve].every(Number.isFinite) && unitPrice > 0 && segments > 0 && reserve > 0 && balance - unitPrice * segments >= reserve;
}
