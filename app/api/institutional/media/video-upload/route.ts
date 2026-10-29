import {NextRequest,NextResponse} from "next/server";
import {requireEditorialPermission} from "@/lib/editorial-authorization";
import {hqServiceKey,supabaseUrl} from "@/lib/hq-server";
import {maxNewsVideoBytes,newsVideoTypes} from "@/lib/news-media";
export async function POST(request:NextRequest){
 const auth=await requireEditorialPermission("news.manage_media"),key=hqServiceKey();
 if(!auth||!key)return NextResponse.json({error:"Sem permissão para carregar vídeos."},{status:403});
 const body=await request.json().catch(()=>null),size=Number(body?.size),mime=String(body?.type||"");
 if(!Number.isInteger(size)||size<=0||size>maxNewsVideoBytes||!newsVideoTypes[mime])return NextResponse.json({error:"Escolha um vídeo MP4 ou WebM até 50 MB."},{status:400});
 const path=`news/${auth.actor.employee_id}/${crypto.randomUUID()}.${newsVideoTypes[mime]}`,base=supabaseUrl();
 try{
  const response=await fetch(`${base}/storage/v1/object/upload/sign/institutional-news/${path}`,{method:"POST",headers:{apikey:key,...(key.startsWith("sb_secret_")?{}:{Authorization:`Bearer ${key}`}),"Content-Type":"application/json"},body:"{}",cache:"no-store",signal:AbortSignal.timeout(12000)});
  if(!response.ok)throw Error("Storage rejected upload authorization");
  const data=await response.json();const signedUrl=new URL(`${base}/storage/v1${data.url}`);
  if(signedUrl.origin!==new URL(base).origin||!signedUrl.searchParams.get("token"))throw Error("Invalid upload authorization");
  return NextResponse.json({signedUrl:signedUrl.toString(),publicUrl:`${base}/storage/v1/object/public/institutional-news/${path}`,path,publicKey:process.env.SUPABASE_ANON_KEY||null},{headers:{"Cache-Control":"private, no-store"}});
 }catch{return NextResponse.json({error:"Não foi possível preparar o envio do vídeo."},{status:502})}
}
