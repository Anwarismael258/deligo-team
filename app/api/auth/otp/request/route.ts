import { NextRequest, NextResponse } from "next/server";
import { supabaseUrl } from "@/lib/hq-server";
export async function POST(request:NextRequest){
  const anonKey=process.env.SUPABASE_ANON_KEY;if(!anonKey||!process.env.SUPABASE_URL)return NextResponse.json({error:"Autenticação não configurada."},{status:503});
  const {phone}=await request.json() as {phone?:string}; const digits=String(phone||"").replace(/\D/g,""); const normalized=digits.startsWith("258")?`+${digits}`:`+258${digits.replace(/^0/,"")}`;
  if(!/^\+258\d{9}$/.test(normalized))return NextResponse.json({error:"Introduza um número moçambicano válido."},{status:400});
  // Use the standard OTP flow. Existing employees are matched by their
  // normalized phone; Supabase will not create a duplicate because phone is
  // unique. The explicit create_user:false made GoTrue classify the request
  // as a disabled signup in this project, returning otp_disabled before the
  // configured Send SMS hook could run.
  const response=await fetch(`${supabaseUrl()}/auth/v1/otp`,{method:"POST",headers:{apikey:anonKey,"Content-Type":"application/json"},body:JSON.stringify({phone:normalized}),cache:"no-store"});
  if(!response.ok){const upstream=await response.json().catch(()=>({})) as {msg?:string;message?:string;error_description?:string;error_code?:string};const reason=upstream.error_code||upstream.msg||upstream.message||upstream.error_description;return NextResponse.json({error:reason?`OTP não enviado: ${reason}`:"Não foi possível enviar o OTP. Confirme que o telefone está cadastrado e que o SMS está configurado."},{status:400});}
  return NextResponse.json({ok:true,message:"OTP enviado para o telefone cadastrado."});
}
