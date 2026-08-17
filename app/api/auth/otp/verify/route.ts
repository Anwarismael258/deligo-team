import { NextRequest, NextResponse } from "next/server";
import { hqRpc } from "@/lib/hq-server";
const STAGING_URL="https://tpmsgvkdjzoidvyiwwfk.supabase.co";
export async function POST(request:NextRequest){
  const anonKey=process.env.SUPABASE_ANON_KEY;if(!anonKey)return NextResponse.json({error:"Autenticação não configurada."},{status:503});
  const {phone,token}=await request.json() as {phone?:string;token?:string}; const digits=String(phone||"").replace(/\D/g,""); const normalized=digits.startsWith("258")?`+${digits}`:`+258${digits.replace(/^0/,"")}`;
  if(!/^\+258\d{9}$/.test(normalized)||!/^\d{6}$/.test(String(token||"")))return NextResponse.json({error:"Telefone ou OTP inválido."},{status:400});
  const auth=await fetch(`${process.env.SUPABASE_URL||STAGING_URL}/auth/v1/token?grant_type=otp`,{method:"POST",headers:{apikey:anonKey,"Content-Type":"application/json"},body:JSON.stringify({phone:normalized,token,type:"sms"}),cache:"no-store"});
  const payload=await auth.json() as {access_token?:string;refresh_token?:string;expires_in?:number;user?:{id?:string;user_metadata?:Record<string,unknown>}};
  if(!auth.ok||!payload.access_token||!payload.refresh_token)return NextResponse.json({error:"OTP inválido ou expirado."},{status:401});
  const actor=payload.user?.id?await hqRpc("hq_actor_context_v1",{p_auth_user_id:payload.user.id}):null;
  if(!actor)return NextResponse.json({error:"Este telefone não está associado a um trabalhador da Central."},{status:403});
  const response=NextResponse.json({ok:true,mustSetPassword:Boolean(payload.user?.user_metadata?.must_set_password),active:actor.status==="active"});const secure=process.env.NODE_ENV==="production";
  response.cookies.set("hq_access_token",payload.access_token,{httpOnly:true,secure,sameSite:"strict",path:"/",maxAge:payload.expires_in||3600});response.cookies.set("hq_refresh_token",payload.refresh_token,{httpOnly:true,secure,sameSite:"strict",path:"/",maxAge:604800});return response;
}
