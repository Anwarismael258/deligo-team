export type KycDecisionResult = { result?: { status?: string; message?: string; driver_status?: string; notification_id?: string }; error?: string };

export async function submitKycDecision(url: string, body: Record<string, unknown>, fetcher: typeof fetch = fetch): Promise<KycDecisionResult> {
  const response = await fetcher(url, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), signal: AbortSignal.timeout(15000) });
  const result = await response.json() as KycDecisionResult;
  if (!response.ok) throw new Error(result.error || "A decisão não foi aplicada. Tente novamente.");
  return result;
}
