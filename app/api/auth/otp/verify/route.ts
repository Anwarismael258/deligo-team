import { NextRequest, NextResponse } from "next/server";
import { supabaseUrl } from "@/lib/hq-server";
export async function POST(request:NextRequest){
  const anonKey=process.env.SUPABASE_ANON_KEY;if(!anonKey)return NextResponse.json({error:"Autenticação não configurada."},{status:503});
  const {phone,token}=await request.json() as {phone?:string;token?:string}; const digits=String(phone||"").replace(/\D/g,""); const normalized=digits.startsWith("258")?`+${digits}`:`+258${digits.replace(/^0/,"")}`;
  const cleanToken=String(token||"").replace(/\D/g,"").slice(0,6);
  if(!/^\+258\d{9}$/.test(normalized)||!/^\d{6}$/.test(cleanToken))return NextResponse.json({error:"Telefone ou OTP inválido."},{status:400});
  let auth: Response, payload: {access_token?:string;refresh_token?:string;expires_in?:number;user?:{id?:string;user_metadata?:Record<string,unknown>};msg?:string;message?:string;error_description?:string};
  try {
    const authUrl=`${supabaseUrl()}/auth/v1/verify`, headers={apikey:anonKey,"Content-Type":"application/json"};
    const grantType="grant_type=otp";
    auth=await fetch(authUrl,{method:"POST",headers,body:JSON.stringify({grant_type:"otp",phone:normalized,token:cleanToken,type:"sms"}),cache:"no-store",signal:AbortSignal.timeout(20000)});
    payload=await auth.json();
    if(!auth.ok){
      auth=await fetch(authUrl,{method:"POST",headers,body:JSON.stringify({grant_type:"otp",phone:normalized.replace(/^\+/,""),token:cleanToken,type:"sms"}),cache:"no-store",signal:AbortSignal.timeout(4000)});
      payload=await auth.json();
    }
  } catch {
    return NextResponse.json({error:"Não foi possível contactar o serviço OTP. Tente novamente."},{status:504});
  }
  if(!auth.ok||!payload.access_token||!payload.refresh_token)return NextResponse.json({error:payload.error_description||payload.msg||payload.message||"OTP inválido ou expirado."},{status:401});
  let actor=null;
  if(payload.user?.id){
    try {
      const serviceKey=process.env.SUPABASE_SERVICE_ROLE_KEY;
      if(!serviceKey) throw new Error("HQ_SERVICE_ROLE_NOT_CONFIGURED");
      // Supabase's newer sb_secret_* keys authenticate through apikey. They
      // are not JWTs and must not be sent as Authorization: Bearer tokens.
      const employeeHeaders:Record<string,string>={apikey:serviceKey,"Accept-Profile":"hq","Content-Profile":"hq"};
      if(!serviceKey.startsWith("sb_secret_")) employeeHeaders.Authorization=`Bearer ${serviceKey}`;
      const rpcResponse=await fetch(`${supabaseUrl()}/rest/v1/rpc/hq_actor_context_for_login_v1`,{method:"POST",headers:{...employeeHeaders,"Content-Type":"application/json"},body:JSON.stringify({p_auth_user_id:payload.user.id,p_phone_e164:normalized}),cache:"no-store",signal:AbortSignal.timeout(2500)});
      if(rpcResponse.ok){
        const rpcPayload=await rpcResponse.json();
        actor=(Array.isArray(rpcPayload)?rpcPayload[0]:rpcPayload) as Record<string,unknown>;
      }
      if(actor) {
        // The security-definer RPC is the canonical HQ lookup. It also handles
        // an existing Auth identity without relying on REST schema exposure.
        // Completing OTP is the first-access activation point.
        if(String(actor.status||"").toLowerCase()==="invited"){
          const activationResponse=await fetch(`${supabaseUrl()}/rest/v1/employees?id=eq.${encodeURIComponent(String(actor.employee_id))}&status=eq.invited`,{method:"PATCH",headers:{...employeeHeaders,"Content-Type":"application/json",Prefer:"return=representation"},body:JSON.stringify({status:"active",last_login_at:new Date().toISOString()}),cache:"no-store",signal:AbortSignal.timeout(5000)});
          if(activationResponse.ok){ const activated=await activationResponse.json() as Array<Record<string,unknown>>; actor=activated[0]||{...actor,status:"active"}; }
        }
      } else {
      // The phone used for OTP is the canonical identity. Query it first so a
      // stale or missing Auth link cannot block an otherwise valid HQ worker.
      let contextResponse=await fetch(`${supabaseUrl()}/rest/v1/employees?auth_user_id=eq.${encodeURIComponent(payload.user.id)}&status=in.(active,invited)&select=id,employee_code,display_name,status,role,requested_role,auth_user_id,phone_e164&limit=1`,{method:"GET",headers:employeeHeaders,cache:"no-store",signal:AbortSignal.timeout(2500)});
      let rows=contextResponse.ok?await contextResponse.json() as Array<Record<string,unknown>>:[];
      if(!rows.length){
        contextResponse=await fetch(`${supabaseUrl()}/rest/v1/employees?phone_e164=eq.${encodeURIComponent(normalized)}&status=in.(active,invited)&select=id,employee_code,display_name,status,role,requested_role,auth_user_id,phone_e164&limit=1`,{method:"GET",headers:employeeHeaders,cache:"no-store",signal:AbortSignal.timeout(2500)});
        if(contextResponse.ok) rows=await contextResponse.json() as Array<Record<string,unknown>>;
      }
      if(contextResponse.ok){
        const candidate=rows[0];
        if(String(candidate?.status||"").toLowerCase() === "invited"){
          const activationResponse=await fetch(`${supabaseUrl()}/rest/v1/employees?id=eq.${encodeURIComponent(String(candidate.id))}&status=eq.invited`,{method:"PATCH",headers:{apikey:serviceKey,"Accept-Profile":"hq","Content-Profile":"hq","Content-Type":"application/json",Prefer:"return=representation"},body:JSON.stringify({status:"active",last_login_at:new Date().toISOString()}),cache:"no-store",signal:AbortSignal.timeout(5000)});
          if(activationResponse.ok){ const activated=await activationResponse.json() as Array<Record<string,unknown>>; actor=activated[0]||null; }
        } else actor=candidate||null;
      }
      }
    }
    catch { actor=null; }
  }
  if(!actor)return NextResponse.json({error:"Este telefone não está associado a um trabalhador da Central."},{status:403});
  const response=NextResponse.json({ok:true,mustSetPassword:Boolean(payload.user?.user_metadata?.must_set_password),active:actor.status==="active",role:String(actor.role||actor.requested_role||"")});const secure=request.nextUrl.protocol==="https:";
  response.cookies.set("hq_access_token",payload.access_token,{httpOnly:true,secure,sameSite:"strict",path:"/",maxAge:payload.expires_in||3600});response.cookies.set("hq_refresh_token",payload.refresh_token,{httpOnly:true,secure,sameSite:"strict",path:"/",maxAge:604800});return response;
}
