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
  if (!response.ok) throw new PaySuiteHttpError(response.status);
  return body;
}

/** The API envelope's status=success means HTTP success, not a paid payout. */
export function payoutResult(value:Record<string,unknown>){
 const nested=value.data&&typeof value.data==="object"&&!Array.isArray(value.data)?value.data as Record<string,unknown>:null;
 const row=nested||value,status=String(row.status||row.state||"pending").toLowerCase();
 return {id:String(row.id||row.reference||""),status:nested?status:(status==="success"?"pending":status),paid:["completed","paid","successful","complete"].includes(status),failed:["failed","cancelled","rejected"].includes(status)};
}
export class PaySuiteHttpError extends Error{constructor(public status:number){super(`PaySuite HTTP ${status}`)}}
export function definitelyRejected(error:unknown){return error instanceof PaySuiteHttpError&&[400,401,402,403,404,422].includes(error.status)}
