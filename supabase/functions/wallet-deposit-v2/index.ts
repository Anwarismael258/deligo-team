import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GATEWAY_DEPOSIT_FEE_PERCENT = 0.03;
const paysuiteBaseUrl = (Deno.env.get("PAYSUITE_BASE_URL") || "https://paysuite.tech").replace(/\/$/, "");
const paysuiteToken = Deno.env.get("PAYSUITE_API_TOKEN") || "";
// PaySuite requires an absolute HTTP(S) return URL. The mobile deep link is
// not accepted by the provider, so route the hosted checkout through our
// HTTPS bridge, which then opens the installed DeliGo app. Keep the value
// configurable for production, but never fall back to PaySuite's dashboard.
const paysuiteReturnUrl = Deno.env.get("PAYSUITE_RETURN_URL") ||
  `${supabaseUrl.replace(/\/$/, "")}/functions/v1/paysuite-webhook`;

const supabase = createClient(supabaseUrl, supabaseKey);

async function isPhoneVerified(userId: string) {
  const { data: profile } = await supabase
    .from("profiles")
    .select("settings, role, phone, payment_contact")
    .eq("id", userId)
    .maybeSingle();
  const settings = profile?.settings && typeof profile.settings === "object"
    ? profile.settings as Record<string, unknown>
    : {};
  const verifiedAt = String(settings.phone_verified_at || "").trim();
  const authUser = await supabase.auth.admin.getUserById(userId);
  return {
    // Supabase Auth phone confirmation is authoritative for older accounts
    // that were verified before profiles.settings.phone_verified_at existed.
    verified: verifiedAt.length > 0 || Boolean(authUser.data.user?.phone_confirmed_at),
    role: profile?.role ? String(profile.role).toLowerCase() : "",
    phone: String(
      authUser.data.user?.phone || profile?.payment_contact || profile?.phone || "",
    ).trim(),
  };
}

function normalizeMsisdn(phone: string): string {
  const digits = phone.replace(/[^\d]/g, "");
  if (digits.startsWith("258") && digits.length >= 12) {
    return digits.slice(3);
  }
  return digits;
}

function inferMethodFromPhone(msisdn: string): "mpesa" | "emola" | "mkesh" | null {
  if (msisdn.startsWith("82") || msisdn.startsWith("83")) return "mkesh";
  if (msisdn.startsWith("84") || msisdn.startsWith("85")) return "mpesa";
  if (msisdn.startsWith("86") || msisdn.startsWith("87")) return "emola";
  return null;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("authorization") || req.headers.get("Authorization") || "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const {data: identity,error: identityError}=await supabase.auth.getUser(token);
    if(identityError||!identity.user)return new Response(JSON.stringify({error:"Unauthorized"}),{status:401,headers:{"Content-Type":"application/json"}});
    const userId = identity.user.id;
    if (!userId) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const reconciling=body.action==="reconcile";
    const verification = await isPhoneVerified(userId);
    const role = verification.role;
    if (!reconciling && !["client", "customer", "restaurant", "courier", "admin"].includes(role)) {
      return new Response(
        JSON.stringify({
          error:
            "Depositos disponiveis apenas para clientes, restaurantes, estafetas e administradores.",
        }),
        { status: 403, headers: { "Content-Type": "application/json" } },
      );
    }
    if (!reconciling && role !== "admin" && !verification.verified) {
      return new Response(
        JSON.stringify({
          error:
            "Conta ainda nao confirmada. Depositos so ficam disponiveis apos verificacao do telefone.",
        }),
        { status: 403, headers: { "Content-Type": "application/json" } },
      );
    }

    if(body.action==="reconcile"){
      let {data:context,error:contextError}=await supabase.rpc("hq_actor_context_v1",{p_auth_user_id:userId});
      if(!context&&identity.user.phone){
        const fallback=await supabase.rpc("hq_actor_context_for_login_v1",{p_auth_user_id:userId,p_phone_e164:"+"+identity.user.phone.replace(/[^0-9]/g,"")});
        context=fallback.data;contextError=fallback.error;
      }
      if(typeof context==="string"){try{context=JSON.parse(context)}catch{context=null}}
      if(Array.isArray(context))context=context[0];
      const employee=context?.status==="active"?{id:context.employee_id}:null;
      if(!employee)console.error("HQ_DEPOSIT_ACTOR_RESOLUTION_FAILED",contextError?.message||"no_active_context");
      if(!employee)return new Response(JSON.stringify({error:"Sem acesso à Central."}),{status:403,headers:{"Content-Type":"application/json"}});
      const {data:receipts}=await supabase.schema("hq").from("personal_deposit_checkouts").select("deposit_id").eq("employee_id",employee.id).is("synced_at",null).limit(5);
      let reconciled=0;
      if(receipts?.length){
        const {data:deposits}=await supabase.from("wallet_deposits").select("id,reference,amount,transaction_id,user_id,status").eq("user_id",userId).in("id",receipts.map((r:any)=>r.deposit_id));
        const base=paysuiteBaseUrl.endsWith("/api/v1")?paysuiteBaseUrl.slice(0,-7):paysuiteBaseUrl,headers={Authorization:`Bearer ${paysuiteToken}`,Accept:"application/json"};
        for(const deposit of deposits||[]){
          if(deposit.status==="completed")continue;
          let payment:any=null;
          if(deposit.transaction_id){const r=await fetch(`${base}/api/v1/payments/${encodeURIComponent(deposit.transaction_id)}`,{headers});if(r.ok)payment=(await r.json()).data;}
          else {for(let page=1;page<=3&&!payment;page++){const r=await fetch(`${base}/api/v1/payments?page=${page}&limit=100`,{headers});if(!r.ok)throw new Error("PaySuite verification unavailable");const rows=(await r.json()).data;if(!Array.isArray(rows))throw new Error("Invalid payment list");payment=rows.find((p:any)=>p.reference===deposit.reference);if(rows.length<100)break;}}
          if(payment&&payment.reference===deposit.reference&&Math.round(Number(payment.amount)*100)===Math.round(Number(deposit.amount)*100)&&["completed","paid","success","successful","settled"].includes(String(payment.status).toLowerCase())){
            const result=await supabase.rpc("settle_confirmed_paysuite_deposit_v1",{p_reference:deposit.reference,p_amount:Number(payment.amount),p_provider_id:String(payment.id||""),p_payload:{source:"authenticated_provider_query",payment}});
            if(result.error)throw result.error;reconciled++;
          }
        }
      }
      return new Response(JSON.stringify({success:true,reconciled}),{headers:{"Content-Type":"application/json"}});
    }
    const requestReturnUrl=body.return_url==="https://www.deligoteam.online/meu-perfil" ? body.return_url : paysuiteReturnUrl;
    const walletId = body.wallet_id as string | undefined;
    const amount = Number(body.amount);
    // The provider is selected from the registered phone prefix on the server.
    // Client input is intentionally ignored so users cannot choose a mismatch.
    const requestedPhone = String(body.phone_number || "").trim();
    const phoneNumber = verification.phone;

    if (!walletId || !amount || amount <= 0 || !phoneNumber) {
      return new Response(JSON.stringify({ error: "Dados invalidos" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }
    if (requestedPhone && normalizeMsisdn(requestedPhone) !== normalizeMsisdn(phoneNumber)) {
      return new Response(JSON.stringify({ error: "O deposito so pode usar o telefone verificado da conta." }), {
        status: 409, headers: { "Content-Type": "application/json" },
      });
    }

    if (!paysuiteToken) return new Response(JSON.stringify({ error: "PaySuite nao configurada." }), { status: 503, headers: { "Content-Type": "application/json" } });

    const { data: wallet, error: walletError } = await supabase
      .from("wallets")
      .select("id,user_id")
      .eq("id", walletId)
      .single();

    if (walletError || !wallet || wallet.user_id !== userId) {
      return new Response(JSON.stringify({ error: "Carteira invalida" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    // PaySuite accepts only letters and numbers in the reference field.
    const reference = `DEP${userId.slice(0, 8)}${Date.now()}`;
    const gatewayFee = Number((amount * GATEWAY_DEPOSIT_FEE_PERCENT).toFixed(2));
    const netAmount = Number((amount - gatewayFee).toFixed(2));
    const msisdn = normalizeMsisdn(phoneNumber);

    if (!/^8\d{8}$/.test(msisdn)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Numero invalido. Use um contacto M-Pesa ou e-Mola valido.",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const inferredMethod = inferMethodFromPhone(msisdn);
    if (!inferredMethod) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Metodo invalido para este numero.",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }
    const paymentMethod = inferredMethod;
    const paymentMethodForDb = paymentMethod === "mpesa"
      ? "m-pesa"
      : paymentMethod === "mkesh" ? "mkesh" : "e-mola";

    const baseDepositPayload = {
      wallet_id: walletId,
      user_id: userId,
      amount,
      payment_method: paymentMethodForDb,
      phone_number: phoneNumber,
      status: "pending",
      reference,
    };
    let depositResult = await supabase
      .from("wallet_deposits")
      .insert({
        ...baseDepositPayload,
        gateway_fee: gatewayFee,
        net_amount: netAmount,
      })
      .select()
      .single();

    if (depositResult.error || !depositResult.data) {
      console.error("wallet-deposit-v2 insert fallback", depositResult.error);
      depositResult = await supabase
        .from("wallet_deposits")
        .insert(baseDepositPayload)
        .select()
        .single();
    }

    const { data: deposit, error: depositError } = depositResult;

    if (depositError || !deposit) {
      console.error("wallet-deposit-v2 create deposit error", depositError);
      return new Response(
        JSON.stringify({
          error: "Falha ao criar deposito",
          details: depositError?.message || null,
          code: depositError?.code || null,
          debug_tag: "wallet-deposit-v2-insert-compat",
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    if (!paysuiteToken) {
      return new Response(
        JSON.stringify({
          success: true,
          deposit_id: deposit.id,
          reference,
          status: "pending",
          gross_amount: amount,
          gateway_fee: gatewayFee,
          net_amount: netAmount,
          message:
            "Deposito criado. Aguarde a confirmacao do pagamento no provedor.",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    const url = `${paysuiteBaseUrl}/api/v1/payments`;
    const callbackUrl = `${supabaseUrl.replace(/\/$/, "")}/functions/v1/paysuite-webhook`;
    const paysuiteHeaders = {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: `Bearer ${paysuiteToken}`,
    };
    let contactId: string | null = null;
    const contactPhone = `+258${msisdn}`;
    try {
      const contactsUrl = `${paysuiteBaseUrl}/api/v1/contacts?phone=${encodeURIComponent(contactPhone)}`;
      const contactsResponse = await fetch(contactsUrl, {
        method: "GET",
        headers: paysuiteHeaders,
      });
      const contactsEnvelope = await contactsResponse.json().catch(() => ({}));
      const contacts = Array.isArray(contactsEnvelope?.data)
        ? contactsEnvelope.data
        : [];
      contactId = contacts[0]?.id?.toString() || null;
      if (!contactId) {
        const contactResponse = await fetch(`${paysuiteBaseUrl}/api/v1/contacts`, {
          method: "POST",
          headers: paysuiteHeaders,
          body: JSON.stringify({
            name: `Cliente DeliGo ${msisdn.slice(-4)}`,
            phone: contactPhone,
          }),
        });
        const contactEnvelope = await contactResponse.json().catch(() => ({}));
        contactId = contactEnvelope?.data?.id?.toString() || null;
      }
    } catch (error) {
      console.warn("wallet-deposit-v2 contact lookup skipped:", error);
    }
    let debitoRes: Response;
    try {
      debitoRes = await fetch(url, {
        method: "POST",
        headers: paysuiteHeaders,
        body: JSON.stringify({
          amount: amount.toFixed(2),
          method: paymentMethod,
          reference,
          description: `Deposito DeliGo ${reference}`,
          return_url: `${requestReturnUrl}?section=deposit&deposit_id=${encodeURIComponent(deposit.id)}`,
          // PaySuite's canonical field. callback_url is deprecated and may
          // still be used by older provider deployments. Keep both fields so
          // confirmed deposits are delivered to DeliGo without manual polling.
          webhook_url: callbackUrl,
          callback_url: callbackUrl,
          ...(contactId ? { contact_id: contactId } : {}),
        }),
      });
    } catch (error) {
      await supabase
        .from("wallet_deposits")
        .update({
          status: "failed",
          provider_status: "network_error",
          provider_payload: {
            source: "wallet-deposit-v2",
            error: error instanceof Error ? error.message : "network_error",
          },
          processed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", deposit.id);

      return new Response(
        JSON.stringify({
          success: false,
          error: "O gateway de pagamento esta temporariamente indisponivel.",
          deposit_id: deposit.id,
          reference,
          provider_status: "network_error",
        }),
        { status: 503, headers: { "Content-Type": "application/json" } },
      );
    }

    const debitoRaw = await debitoRes.text().catch(() => "");
    let debitoData: Record<string, unknown> = {};
    if (debitoRaw) {
      try {
        debitoData = JSON.parse(debitoRaw);
      } catch {
        debitoData = {};
      }
    }
    const providerData = debitoData.data && typeof debitoData.data === "object"
      ? debitoData.data as Record<string, unknown>
      : {};
    if (!debitoRes.ok) {
      await supabase
        .from("wallet_deposits")
        .update({
          status: "failed",
          provider_status: String(
            debitoData?.status ||
              debitoData?.transaction_status ||
              debitoData?.state ||
              "",
          ).trim() || null,
          provider_payload: {
            http_status: debitoRes.status,
            raw: debitoRaw || null,
            parsed: debitoData,
          },
          updated_at: new Date().toISOString(),
        })
        .eq("id", deposit.id);

      return new Response(
        JSON.stringify({
          success: false,
          error: debitoData?.message || "Falha ao iniciar pagamento",
          deposit_id: deposit.id,
          reference,
          provider_status: debitoData?.status ||
            debitoData?.transaction_status ||
            debitoData?.state ||
            null,
          provider_error: debitoData?.error ||
            debitoData?.message ||
            debitoData?.detail ||
            null,
          provider_http_status: debitoRes.status,
          gross_amount: amount,
          gateway_fee: gatewayFee,
          net_amount: netAmount,
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const debitoReference =
      providerData.debito_reference || providerData.id ||
      debitoData.debito_reference || debitoData.transaction_id || debitoData.provider_reference ||
      null;
    const checkoutUrl =
      providerData.checkout_url ||
      debitoData.checkout_url ||
      debitoData.payment_url ||
      debitoData.payment_link ||
      debitoData.url ||
      null;

    await supabase
      .from("wallet_deposits")
      .update({
        transaction_id: debitoReference,
        provider_status: String(providerData.status || debitoData.status || "pending"),
        provider_payload: {
          parsed: debitoData,
          checkout_url: checkoutUrl,
        },
        updated_at: new Date().toISOString(),
      })
      .eq("id", deposit.id);

    return new Response(
      JSON.stringify({
        success: true,
        deposit_id: deposit.id,
        reference,
        debito_reference: debitoReference,
        checkout_url: checkoutUrl,
        status: debitoData.status || "PENDING",
        gross_amount: amount,
        gateway_fee: gatewayFee,
        net_amount: netAmount,
        message: "Pedido enviado. Confirme o PIN no seu telemovel.",
        instructions:
          "Aguardando pagamento. Confirme o PIN no telemovel. O saldo da carteira sera atualizado automaticamente apos a confirmacao do gateway.",
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : "Erro interno",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
