import { hqRest, hqRpc } from "./hq-server";
import { sendMozeSms, mozeBalance, smsBudgetAllows } from "./sms-campaigns";
export type SmsCampaign = { id: string; app_slug: string; title: string; message: string; sender_id: string; status: string; segments: number; max_recipients: number; created_by: string; target_user_id: string | null };
export function smsLiveEnabled() { return process.env.MOZESMS_MARKETING_ENABLED === "true"; }
export async function smsProviderConfig() {
  const value = await hqRpc("hq_sms_provider_config_v1") as Record<string, string> | null;
  if (!value?.mozesms_api_key || !value.mozesms_api_secret || !value.mozesms_sender_id) throw new Error("SMS_PROVIDER_NOT_CONFIGURED");
  return { key: value.mozesms_api_key, secret: value.mozesms_api_secret, sender: value.mozesms_sender_id };
}
export async function dispatchSms(campaign: SmsCampaign, actor: string) {
  if (!smsLiveEnabled()) throw new Error("SMS_LIVE_DISABLED");
  const config = await smsProviderConfig();
  if (config.sender !== campaign.sender_id) throw new Error("SMS_SENDER_CHANGED");
  const reserve = Number(process.env.MOZESMS_MARKETING_MIN_BALANCE_MZN);
  const balance = await mozeBalance(config);
  if (!smsBudgetAllows(balance.balance, balance.unitPrice, campaign.segments, reserve)) throw new Error("SMS_OTP_RESERVE_OR_BUDGET_REQUIRED");
  const claim = await hqRpc("hq_sms_claim_v1", { p_id: campaign.id, p_actor: actor }) as { id: string; phone: string; message: string; sender: string } | null;
  if (!claim) return { processed: 0 };
  const outcome = await sendMozeSms({ ...config, sender: claim.sender }, claim.phone, claim.message);
  // If persistence fails, leave sending intact. It expires to unknown, never an automatic resend.
  await hqRest(`sms_campaign_recipients?id=eq.${claim.id}&status=eq.sending`, { method: "PATCH", body: JSON.stringify({ status: outcome.status, provider_reference: outcome.reference || null, cost_mzn: outcome.cost ?? null, finished_at: new Date().toISOString() }) });
  return { processed: 1, status: outcome.status };
}
