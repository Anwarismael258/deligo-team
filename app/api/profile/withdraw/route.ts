import { personalWalletAmounts } from "@/lib/finance-custody";
import { NextRequest, NextResponse } from "next/server";
import {cookies} from "next/headers";
import {detectMozambiqueWalletOperator} from "@/lib/mozambique-wallet";
import { corporateActor, hqRest, hqRpc, hqServiceKey, supabaseUrl } from "@/lib/hq-server";
import { paysuiteRequest, payoutResult, definitelyRejected, PaySuiteHttpError } from "@/lib/paysuite";

import {walletOwner,eligiblePersonalWallet} from "@/lib/personal-wallet";
import {isUuid} from "@/lib/internal-inbox";

const PAYOUT_BRIDGE_READY = process.env.HQ_EMPLOYEE_PAYOUT_READY === "true";
const PAYOUT_BRIDGE_ENDPOINT = process.env.HQ_EMPLOYEE_PAYOUT_ENDPOINT === "admin-corporate-withdrawal" ? "admin-corporate-withdrawal" : "central-employee-payout";
const APP_ID = "7628e590-652b-4e93-9ff0-d258e351303c";
const moneyMinor = (value: number) => Math.round(value * 100);
const normalizePhone = (value: string) => {
  const digits = value.replace(/\D/g, "");
  const local = digits.startsWith("258") ? digits.slice(3) : digits;
  if (!/^(82|83|84|85|86|87)\d{7}$/.test(local)) throw new Error("Número PaySuite inválido.");
  return local;
};

async function paymentsRest(path: string, init: RequestInit = {}) {
  const key = hqServiceKey();
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_NOT_CONFIGURED");
  const privileged: Record<string, string> = key.startsWith("sb_secret_") ? { apikey: key } : { apikey: key, Authorization: `Bearer ${key}` };
  const initHeaders = new Headers(init.headers);
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init,
    headers: {
      ...privileged,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      "Content-Profile": "payments",
      "Accept-Profile": "payments",
      ...Object.fromEntries(initHeaders.entries()),
    },
    cache: "no-store",
  });
  if (!response.ok) throw new Error((await response.text()) || "PAYMENTS_REST_FAILED");
  return response.status === 204 ? null : response.json();
}

type Wallet = Record<string, unknown> & { id: string; available_balance_minor: number; metadata: Record<string, unknown> };
const PAYSUITE_FEE_RATE = 0.03;
const paysuiteWebhookUrl = () => process.env.PAYSUITE_WEBHOOK_URL || process.env.APP_URL && `${process.env.APP_URL.replace(/\/$/, "")}/api/payments/paysuite/webhook` || process.env.NEXT_PUBLIC_APP_URL && `${process.env.NEXT_PUBLIC_APP_URL.replace(/\/$/, "")}/api/payments/paysuite/webhook` || "https://www.deligoteam.online/api/payments/paysuite/webhook";

type Allocation={kind:"hq"|"canonical";wallet:Wallet;amountMinor:number};
type Reserved={kind:"hq"|"canonical";id:string;reference:string;amountMinor:number;netMinor:number};
async function release(item:Reserved,reason:string){await hqRpc(item.kind==="hq"?"hq_fail_employee_paysuite_payout_v1":"fail_paysuite_payout_v1",{p_payout_request_id:item.id,p_reason:reason})}

async function sendPreparedPayout(p:Reserved,requestBody:Record<string,unknown>){
 if(process.env.PAYSUITE_ENABLED==="true"&&process.env.PAYSUITE_API_TOKEN)return paysuiteRequest<Record<string,unknown>>("/payouts",{method:"POST",body:JSON.stringify(requestBody)});
 const token=(await cookies()).get("hq_access_token")?.value,anon=process.env.SUPABASE_ANON_KEY;
 if(!token||!anon)throw new Error("SHARED_PAYOUT_SESSION_REQUIRED");
 const response=await fetch(`${supabaseUrl()}/functions/v1/${PAYOUT_BRIDGE_ENDPOINT}`,{method:"POST",headers:{apikey:anon,Authorization:`Bearer ${token}`,"Content-Type":"application/json"},body:JSON.stringify({action:"central_employee_payout",payout_id:p.id,kind:p.kind}),cache:"no-store",signal:AbortSignal.timeout(20000)});
 const result=await response.json().catch(()=>null);
 if(!response.ok||!result)throw new Error("SHARED_PAYOUT_CONFIRMATION_PENDING");
 const status=Number(result.provider_http_status||0);
 if(status<200||status>=300)throw new PaySuiteHttpError(status||503);
 return (result.provider_response||{data:{status:"pending",reference:p.reference}}) as Record<string,unknown>;
}

async function execute(actor:NonNullable<Awaited<ReturnType<typeof corporateActor>>>,amount:number,method:string,intentId:string){
 const owner=await walletOwner(actor),requestedMinor=moneyMinor(amount);
 const profiles=await hqRest(`employee_display_profiles?employee_id=eq.${actor.employee_id}&select=personal_phone`);
 const contacts=await hqRest(`employees?id=eq.${actor.employee_id}&select=phone_e164`);
 const phone=detectMozambiqueWalletOperator(String(profiles?.[0]?.personal_phone||contacts?.[0]?.phone_e164||"")).phone;
 await hqRpc("migrate_legacy_personal_wallet_to_paysuite_v1",{p_auth_user_id:owner}).catch(()=>null);
 const [hqWallets,canonical]=await Promise.all([
  hqRest(`logical_wallets?owner_user_id=eq.${owner}&wallet_type=eq.employee&status=eq.active&currency=eq.MZN&select=*`),
  paymentsRest(`wallet_accounts?owner_user_id=eq.${owner}&status=eq.active&currency_code=eq.MZN&select=*`),
 ]);
 const reconciledCanonical = await personalWalletAmounts(canonical,owner,path=>paymentsRest(path));
 const sources:Allocation[]=[...hqWallets.map((w:Wallet)=>({kind:"hq" as const,wallet:w,amountMinor:moneyMinor(Number(w.available_amount||0))})),...reconciledCanonical.filter(eligiblePersonalWallet).map(row=>({kind:"canonical" as const,wallet:row as Wallet,amountMinor:Number(row.available_balance_minor||0)}))].filter(x=>x.amountMinor>0);
 if(sources.reduce((sum,x)=>sum+x.amountMinor,0)<requestedMinor)throw new Error("Saldo pessoal disponível insuficiente.");
 let remaining=requestedMinor;const allocations=sources.map(x=>{const amountMinor=Math.min(remaining,x.amountMinor);remaining-=amountMinor;return {...x,amountMinor}}).filter(x=>x.amountMinor>0);
 // PaySuite accepts a minimum net payout of 1 MZN for each source wallet.
 if(allocations.some(x=>x.amountMinor-Math.round(x.amountMinor*PAYSUITE_FEE_RATE)<100))throw new Error("O valor líquido de cada carteira deve ser pelo menos 1 MZN.");
 const prepared:Reserved[]=[];
 try{for(let index=0;index<allocations.length;index++){
  const x=allocations[index],netMinor=x.amountMinor-Math.round(x.amountMinor*PAYSUITE_FEE_RATE),key=`employee-${intentId}-${index}`;
  if(x.kind==="hq"){
   const p=await hqRpc("hq_prepare_employee_paysuite_payout_v1",{p_actor_auth_user_id:owner,p_amount:x.amountMinor/100,p_method:method,p_phone_number:phone,p_idempotency_key:key}) as Record<string,unknown>;
   prepared.push({kind:x.kind,id:String(p.payout_request_id),reference:String(p.reference),amountMinor:x.amountMinor,netMinor});
  }else{
   const reference=`DLGWD${crypto.randomUUID().replace(/-/g,"").slice(0,24)}`;
   const [p]=await paymentsRest("payout_requests",{method:"POST",body:JSON.stringify({app_id:x.wallet.app_id||APP_ID,source_wallet_account_id:x.wallet.id,beneficiary_user_id:owner,requested_by:actor.authUserId,amount_minor:x.amountMinor,fee_minor:x.amountMinor-netMinor,status:"pending",destination_phone:phone,method,idempotency_key:key,request_note:"Levantamento pessoal unificado no perfil",metadata:{reference,provider:"paysuite",employee_id:actor.employee_id,gross_amount_minor:x.amountMinor,net_amount_minor:netMinor,unified_withdrawal:true}})});
   try{await hqRpc("reserve_paysuite_payout_v1",{p_payout_request_id:p.id})}catch(e){await paymentsRest(`payout_requests?id=eq.${p.id}`,{method:"PATCH",body:JSON.stringify({status:"failed",rejection_reason:"Não foi possível reservar saldo."})}).catch(()=>null);throw e}
   prepared.push({kind:x.kind,id:String(p.id),reference,amountMinor:x.amountMinor,netMinor});
  }
 }}catch(e){for(const p of prepared)await release(p,"Não foi possível preparar o pedido completo.").catch(()=>null);throw e}
 const results=[];
 for(const p of prepared){
  try{
   const raw=await sendPreparedPayout(p,{amount:(p.netMinor/100).toFixed(2),currency:"MZN",reference:p.reference,description:`Levantamento DeliGo Team - ${actor.name}`.slice(0,255),beneficiary:{phone,holder:actor.name},method,...(process.env.PAYSUITE_WEBHOOK_SECRET?{webhook_url:paysuiteWebhookUrl()}: {})});
   const provider=payoutResult(raw),providerReference=provider.id||p.reference;
   if(provider.failed){await release(p,"PaySuite confirmou a rejeição.");results.push({payoutId:p.id,status:"failed",providerReference});continue}
   if(provider.paid)await hqRpc(p.kind==="hq"?"hq_complete_employee_paysuite_payout_v1":"complete_paysuite_payout_v1",{p_payout_request_id:p.id,p_provider_reference:providerReference});
   results.push({payoutId:p.id,status:provider.paid?"paid":"processing",providerReference});
  }catch(e){
   if(definitelyRejected(e)){try{await release(p,"PaySuite rejeitou o pedido.");results.push({payoutId:p.id,status:"failed"})}catch{results.push({payoutId:p.id,status:"processing",reconciliationRequired:true})}}
   else results.push({payoutId:p.id,status:"processing",reference:p.reference,reconciliationRequired:true});
   // Timeout or local reconciliation failure does not prove provider rejection.
  }
 }
 const allPaid=results.every(x=>x.status==="paid"),allFailed=results.every(x=>x.status==="failed"),hasFailed=results.some(x=>x.status==="failed");
 return {body:{status:allPaid?"paid":allFailed?"failed":hasFailed?"partial":"processing",payoutId:results[0]?.payoutId,payoutIds:results.map(x=>x.payoutId),providerReferences:results.map(x=>x.providerReference).filter(Boolean),results},httpStatus:allFailed?409:allPaid?200:202};
}
export async function POST(request:NextRequest){
 const actor=await corporateActor();if(!actor)return NextResponse.json({error:"Sessão inválida."},{status:401});
 const b=await request.json().catch(()=>null),amount=Number(b?.amount),minor=moneyMinor(amount);
 let operator;try{const [p,c]=await Promise.all([hqRest(`employee_display_profiles?employee_id=eq.${actor.employee_id}&select=personal_phone`),hqRest(`employees?id=eq.${actor.employee_id}&select=phone_e164`)]);operator=detectMozambiqueWalletOperator(String(p?.[0]?.personal_phone||c?.[0]?.phone_e164||""))}catch{return NextResponse.json({error:"Confirme o número protegido do perfil para levantar o saldo."},{status:409})}
 const method=operator.method;
 if(!Number.isFinite(amount)||minor<104||minor>100000000||Math.abs(amount*100-minor)>0.000001)return NextResponse.json({error:"Indique um montante entre 1,04 e 1.000.000 MZN, com até duas casas decimais."},{status:400});
 if(!["mpesa","emola","mkesh"].includes(method))return NextResponse.json({error:"Método de levantamento inválido."},{status:400});
 if(!isUuid(b?.idempotencyKey))return NextResponse.json({error:"Identificador do pedido inválido. Actualize a página e tente novamente."},{status:400});

 if(!(process.env.PAYSUITE_ENABLED==="true"&&process.env.PAYSUITE_API_TOKEN)&&!PAYOUT_BRIDGE_READY)return NextResponse.json({error:"O saldo existe, mas o serviço PaySuite de levantamento da Central aguarda activação. Nenhum valor foi reservado ou debitado."},{status:503});
 let claim:Record<string,unknown>;
 try{claim=await hqRpc("claim_employee_withdrawal_v1",{p_employee:actor.employee_id,p_client:b.idempotencyKey,p_minor:minor,p_method:method},"hq") as Record<string,unknown>}
 catch(e){console.error("withdrawal_claim_failed",e);return NextResponse.json({error:"Não foi possível registar o pedido. Verifique a activação do serviço de levantamento."},{status:503})}
 if(!claim.fresh)return NextResponse.json(claim.response||{status:"processing",intentId:claim.id,message:"Este pedido já foi recebido. Consulte o saldo e aguarde a confirmação."},{status:Number(claim.http_status||202)});
 let result:{body:Record<string,unknown>;httpStatus:number};
 try{
  const owner=await walletOwner(actor);
  const [hqBalances,rawCanonical]=await Promise.all([hqRest(`logical_wallets?owner_user_id=eq.${owner}&wallet_type=eq.employee&status=eq.active&currency=eq.MZN&select=available_amount`),paymentsRest(`wallet_accounts?owner_user_id=eq.${owner}&status=eq.active&currency_code=eq.MZN&select=*`)]);
  const reconciled=await personalWalletAmounts(rawCanonical,owner,path=>paymentsRest(path));
  const spendable=hqBalances.reduce((sum:number,w:Record<string,unknown>)=>sum+moneyMinor(Number(w.available_amount||0)),0)+reconciled.filter(eligiblePersonalWallet).reduce((sum:number,w:Record<string,unknown>)=>sum+Number(w.available_balance_minor||0),0);
  if(minor>spendable)throw new Error("Saldo pessoal disponível insuficiente.");
  result=await execute(actor,amount,method,String(claim.id));result.body={...result.body,operator:operator.label}}
 catch(e){console.error("withdrawal_prepare_failed",e);const message=e instanceof Error&&/^(Saldo pessoal|O valor líquido|Número PaySuite)/.test(e.message)?e.message:"Não foi possível preparar o levantamento. Consulte o saldo antes de iniciar um novo pedido.";result={body:{status:"failed",error:message},httpStatus:409}}
 await hqRest(`employee_withdrawal_intents?id=eq.${claim.id}&employee_id=eq.${actor.employee_id}`,{method:"PATCH",body:JSON.stringify({response:result.body,http_status:result.httpStatus})}).catch(e=>console.error("withdrawal_receipt_failed",e));
 return NextResponse.json(result.body,{status:result.httpStatus,headers:{"Cache-Control":"private, no-store"}});
}
