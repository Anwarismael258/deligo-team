import {NextRequest,NextResponse} from "next/server";
import {cookies} from "next/headers";
import {corporateActor,hqRest,stagingRest,supabaseUrl} from "@/lib/hq-server";

export const dynamic="force-dynamic";
export async function POST(request:NextRequest){
 const actor=await corporateActor();
 if(!actor||!["SUPER_ADMIN","FINANCE"].includes(actor.role))return NextResponse.json({error:"Depósitos disponíveis para Admin e Finanças."},{status:403});
 const body=await request.json().catch(()=>null),amount=Number(body?.amount),minor=Math.round(amount*100);
 if(!Number.isFinite(amount)||minor<100||minor>1000000000||Math.abs(amount*100-minor)>0.000001)return NextResponse.json({error:"Indique um montante válido, com até duas casas decimais."},{status:400});
 const token=(await cookies()).get("hq_access_token")?.value,key=process.env.SUPABASE_ANON_KEY;
 if(!token||!key)return NextResponse.json({error:"Sessão de pagamentos indisponível. Inicie sessão novamente."},{status:401});
 try{
  // The shared service authenticates this token, derives the verified account
  // phone/operator, and checks wallet ownership. Never accept those from the UI.
  const wallets=await stagingRest(`wallets?user_id=eq.${encodeURIComponent(actor.authUserId)}&currency=eq.MZN&is_active=eq.true&select=id&order=is_default.desc,created_at.asc&limit=1`);
  if(!wallets?.[0]?.id)return NextResponse.json({error:"A conta ainda não tem uma carteira pessoal activa para depósitos."},{status:409});
  const response=await fetch(`${supabaseUrl()}/functions/v1/wallet-deposit-v2`,{method:"POST",headers:{apikey:key,Authorization:`Bearer ${token}`,"Content-Type":"application/json"},body:JSON.stringify({wallet_id:wallets[0].id,amount:minor/100}),cache:"no-store",signal:AbortSignal.timeout(45000)});
  const data=await response.json().catch(()=>null);
  if(!response.ok||!data?.success)return NextResponse.json({error:data?.error||"Não foi possível iniciar o checkout PaySuite."},{status:response.ok?502:response.status});
  const checkout=new URL(String(data.checkout_url||""));
  if(checkout.protocol!=="https:"||!(checkout.hostname==="paysuite.tech"||checkout.hostname.endsWith(".paysuite.tech")||checkout.hostname==="paysuite.co.mz"||checkout.hostname.endsWith(".paysuite.co.mz")))throw new Error("A PaySuite não devolveu um checkout seguro.");
  await hqRest("personal_deposit_checkouts?on_conflict=deposit_id",{method:"POST",headers:{Prefer:"resolution=ignore-duplicates,return=representation"},body:JSON.stringify({deposit_id:data.deposit_id,employee_id:actor.employee_id})});
  return NextResponse.json({checkoutUrl:checkout.toString(),depositId:data.deposit_id,grossAmount:data.gross_amount,fee:data.gateway_fee,netAmount:data.net_amount},{status:201,headers:{"Cache-Control":"private, no-store"}});
 }catch(error){console.error("HQ_PERSONAL_DEPOSIT_FAILED",error instanceof Error?error.message:"unknown");return NextResponse.json({error:"Não foi possível abrir o checkout. Verifique o histórico antes de tentar novamente."},{status:502});}
}
