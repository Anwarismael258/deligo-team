const apiUrl = () => process.env.PAYSUITE_API_URL || "https://paysuite.tech/api/v1";

export function paysuiteEnabled() {
  return process.env.PAYSUITE_ENABLED === "true" && Boolean(process.env.PAYSUITE_API_TOKEN);
}

export async function paysuiteRequest<T>(path: string, init: RequestInit = {}) {
  if (!paysuiteEnabled()) throw new Error("PaySuite está desactivada ou sem credenciais.");
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${process.env.PAYSUITE_API_TOKEN}`);
  headers.set("Content-Type", "application/json");
  headers.set("Accept", "application/json");
  const response = await fetch(`${apiUrl()}${path}`, { ...init, headers, signal: AbortSignal.timeout(10_000) });
  const body = await response.json().catch(() => null) as T;
  if (!response.ok) throw new Error(`PaySuite HTTP ${response.status}`);
  return body;
}
