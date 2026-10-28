type Row = Record<string, any>;
const json = (body: Row, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "private, no-store" } });
const msisdn = (value: unknown) => String(value || "").replace(/\D/g, "").replace(/^258/, "");
const uuid = (value: unknown) => /^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(String(value || ""));

export async function handleCentralEmployeePayout(body: Row, user: Row, db: any, config: { baseUrl: string; token: string }, fetcher: typeof fetch = fetch) {
  const readContext = await db.rpc("hq_actor_context_v1", { p_auth_user_id: user.id });
  let actor = readContext.data;
  if (!actor && user.phone && user.phone_confirmed_at) {
    const fallback = await db.rpc("hq_actor_context_for_login_v1", { p_auth_user_id: user.id, p_phone_e164: "+258" + msisdn(user.phone) });
    actor = fallback.data;
  }
  if (!actor?.employee_id || actor.status !== "active") return json({ error: "Trabalhador não autorizado.", not_submitted: true }, 403);
  const employeeResult = await db.schema("hq").from("employees").select("id,auth_user_id,phone_e164,display_name").eq("id", actor.employee_id).eq("status", "active").single();
  const employee = employeeResult.data;
  if (!employee?.auth_user_id) return json({ error: "Identidade da carteira indisponível.", not_submitted: true }, 403);
  const owner = employee.auth_user_id;
  const root = config.baseUrl.replace(/\/$/, "").replace(/\/api\/v1$/i, "") + "/api/v1";
  const headers = { Authorization: `Bearer ${config.token}`, Accept: "application/json", "Content-Type": "application/json" };

  const storeProvider = async (kind: string, request: Row, snapshot: Row, httpStatus: number) => {
    const row = snapshot.data && typeof snapshot.data === "object" && !Array.isArray(snapshot.data) ? snapshot.data : snapshot;
    const metadata = { ...(request.metadata || {}), central_provider_snapshot: snapshot, central_provider_http_status: httpStatus, ...(row.id ? { central_provider_id: String(row.id) } : {}) };
    const update: Row = { metadata, updated_at: new Date().toISOString() };
    if (row.id) update.provider_reference = String(row.id);
    const result = await db.schema(kind === "hq" ? "hq" : "payments").from("payout_requests").update(update).eq("id", request.id);
    if (result.error) throw new Error("PAYOUT_RECEIPT_NOT_SAVED");
  };
  const reconcile = async (kind: string, request: Row) => {
    const metadata = request.metadata || {};
    const reference = metadata.reference;
    const expectedMinor = kind === "hq" ? Math.round(Number(request.amount) * 100) - Math.round(Number(request.amount) * 3) : Number(request.amount_minor) - Number(request.fee_minor);
    let found: Row | null = null;
    if (metadata.central_provider_id) {
      const response = await fetcher(`${root}/payouts/${encodeURIComponent(metadata.central_provider_id)}`, { headers, signal: AbortSignal.timeout(10000) });
      if (!response.ok) return null;
      const value = await response.json(); found = value.data || value;
    } else {
      for (let page = 1; page <= 3 && !found; page++) {
        const response = await fetcher(`${root}/payouts?page=${page}&limit=100`, { headers, signal: AbortSignal.timeout(10000) });
        if (!response.ok) return null;
        const value = await response.json();
        const rows = Array.isArray(value.data) ? value.data : [];
        found = rows.find((row: Row) => row.reference === reference) || null;
        if (rows.length < 100) break;
      }
    }
    if (!found || found.reference !== reference || Math.round(Number(found.amount) * 100) !== expectedMinor) return null;
    const phone = kind === "hq" ? request.destination_number : request.destination_phone;
    if (msisdn(found.beneficiary?.phone) !== msisdn(phone)) return null;
    const state = String(found.status || "").toLowerCase();
    const paid = ["completed", "paid", "successful"].includes(state);
    const failed = ["failed", "cancelled", "rejected"].includes(state);
    await storeProvider(kind, request, { data: found }, 200);
    if (paid || failed) {
      const name = kind === "hq" ? (paid ? "hq_complete_employee_paysuite_payout_v1" : "hq_fail_employee_paysuite_payout_v1") : (paid ? "complete_paysuite_payout_v1" : "fail_paysuite_payout_v1");
      const args = paid ? { p_payout_request_id: request.id, p_provider_reference: String(found.id) } : { p_payout_request_id: request.id, p_reason: "PaySuite confirmou a rejeição do levantamento." };
      const result = await db.rpc(name, args);if (result.error) throw new Error("PAYOUT_RECONCILIATION_PENDING");
    }
    return found;
  };

  if (body.action === "central_employee_reconcile") {
    if (!config.token) return json({ reconciled: 0, provider_available: false });
    let count = 0;
    for (const kind of ["canonical", "hq"]) {
      const result = await db.schema(kind === "hq" ? "hq" : "payments").from("payout_requests").select("*").eq("beneficiary_user_id", owner).eq("status", "processing").limit(20);
      if (result.error) continue;
      for (const request of result.data || []) {
        if (!request.metadata?.central_dispatch_started_at) continue;
        try { if (await reconcile(kind, request)) count++; } catch { /* Keep the reservation until provider status is confirmed. */ }
      }
    }
    return json({ reconciled: count, provider_available: true });
  }
  if (!config.token) return json({ error: "PaySuite indisponível no serviço partilhado.", not_submitted: true }, 503);
  if (!user.phone_confirmed_at) return json({ error: "Confirme o telefone da conta antes de levantar.", not_submitted: true }, 403);
  if (!uuid(body.payout_id) || !["canonical", "hq"].includes(body.kind)) return json({ error: "Pedido de levantamento inválido.", not_submitted: true }, 400);
  const contact = await db.schema("hq").from("employee_display_profiles").select("personal_phone").eq("employee_id", employee.id).maybeSingle();
  const protectedPhone = msisdn(contact.data?.personal_phone || employee.phone_e164 || user.phone);
  if (protectedPhone !== msisdn(user.phone)) return json({ error: "O telefone protegido deve coincidir com a conta verificada.", not_submitted: true }, 409);
  const claim = await db.schema("hq").rpc("claim_employee_paysuite_dispatch_v1", { p_kind: body.kind, p_payout_id: body.payout_id, p_owner: owner });
  if (claim.error || !claim.data) return json({ error: "Pedido não reservado ou não pertence ao trabalhador.", not_submitted: true }, 409);
  const payout = claim.data;
  if (payout.phone !== protectedPhone) return json({ error: "Destino do levantamento inválido.", not_submitted: true }, 409);
  if (!claim.data.fresh) return json({ provider_http_status: 202, provider_response: { data: { reference: payout.reference, status: "pending" } }, reconciliationRequired: true });
  const request = { id: payout.id, metadata: payout.metadata };
  try {
    const response = await fetcher(`${root}/payouts`, { method: "POST", headers, signal: AbortSignal.timeout(15000), body: JSON.stringify({ amount: (Number(payout.net_minor) / 100).toFixed(2), currency: "MZN", reference: payout.reference, description: "Levantamento pessoal DeliGo Central", beneficiary: { phone: payout.phone, holder: payout.holder }, method: payout.method }) });
    const snapshot = await response.json().catch(() => ({}));
    await storeProvider(body.kind, request, snapshot, response.status);
    return json({ provider_http_status: response.status, provider_response: snapshot });
  } catch {
    // A timeout does not establish whether PaySuite accepted the request.
    return json({ provider_http_status: 202, provider_response: { data: { reference: payout.reference, status: "pending" } }, reconciliationRequired: true });
  }
}
