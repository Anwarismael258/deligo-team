import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { handleCentralEmployeePayout } from "./central-employee-payout.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const base = (Deno.env.get("PAYSUITE_BASE_URL") || "https://paysuite.tech").replace(/\/$/, "");
const token = Deno.env.get("PAYSUITE_API_TOKEN") || "";
const db = createClient(url, service);

const out = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

serve(async (req) => {
  if (req.method !== "POST") return out({ error: "Method not allowed" }, 405);
  try {
    const raw = req.headers.get("authorization") || "";
    const tokenJwt = raw.startsWith("Bearer ") ? raw.slice(7) : "";
    if (!tokenJwt) return out({ error: "Unauthorized" }, 401);
    const {data: authenticated,error: authError} = await db.auth.getUser(tokenJwt);
    const userId = authError ? undefined : authenticated.user?.id;
    if (!userId) return out({ error: "Invalid token" }, 401);
    const body = await req.json();
    if (["central_employee_payout","central_employee_reconcile"].includes(body.action)) return handleCentralEmployeePayout(body,authenticated.user!,db,{baseUrl:base,token});
    const amount = Number(body.amount);
    const method = String(body.method || "").toLowerCase() === "m-pesa" ? "mpesa" : String(body.method || "").toLowerCase();
    const phone = String(body.phone_number || "").trim();
    const idempotency = String(body.idempotency_key || `admin-corp-${userId}-${Date.now()}`);
    if (!token) return out({ error: "PaySuite não configurada" }, 503);
    const reserve = await db.rpc("admin_reserve_corporate_withdrawal_v1", {
      p_amount: amount, p_method: method, p_phone_number: phone, p_idempotency_key: idempotency,
    });
    if (reserve.error) return out({ error: reserve.error.message }, 400);
    const reserved = reserve.data as Record<string, unknown>;
    const withdrawalId = String(reserved.withdrawal_id || "");
    if (reserved.status === "paid" || reserved.status === "processing") return out(reserved);
    const reference = `DLG-CORP-${withdrawalId.slice(0, 8).toUpperCase()}`;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000);
    let response: Response;
    try {
      response = await fetch(`${base}/api/v1/payouts`, {
      method: "POST", headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ amount, currency: "MZN", reference, description: "Levantamento de receita empresarial DeliGo", beneficiary: { phone }, method, webhook_url: `${url}/functions/v1/paysuite-webhook` }),
        signal: controller.signal,
      });
    } catch (error) {
      await db.from("admin_corporate_withdrawals").update({ status: "failed", updated_at: new Date().toISOString() }).eq("id", withdrawalId);
      return out({ error: error instanceof Error && error.name === "AbortError" ? "PaySuite não respondeu dentro do prazo" : "Falha de comunicação com a PaySuite", withdrawal_id: withdrawalId }, 504);
    } finally {
      clearTimeout(timeout);
    }
    const provider = await response.json().catch(() => ({}));
    const providerRef = provider?.data?.id || provider?.data?.transaction_id || provider?.id || null;
    if (!response.ok) {
      await db.from("admin_corporate_withdrawals").update({ status: "failed", updated_at: new Date().toISOString() }).eq("id", withdrawalId);
      return out({ error: provider?.message || provider?.error || "Falha ao criar payout PaySuite", withdrawal_id: withdrawalId }, 400);
    }
    await db.from("admin_corporate_withdrawals").update({ status: "processing", provider_reference: providerRef || reference, updated_at: new Date().toISOString() }).eq("id", withdrawalId);
    return out({ success: true, withdrawal_id: withdrawalId, status: "processing", amount, fee_amount: reserved.fee_amount, net_amount: reserved.net_amount, provider_reference: providerRef || reference });
  } catch (error) { return out({ error: error instanceof Error ? error.message : "Falha no levantamento empresarial" }, 500); }
});
