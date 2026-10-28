import {NextRequest,NextResponse} from "next/server";
import {hqRest,hqServiceKey,supabaseUrl} from "@/lib/hq-server";
import {inboxActor,requireConversation,inboxBucket,isUuid,InboxError} from "@/lib/internal-inbox";
export async function GET(req:NextRequest){try{const actor=await inboxActor(),id=req.nextUrl.searchParams.get("id");if(!isUuid(id))throw new InboxError("Anexo inválido.");
 const row=(await hqRest(`chat_attachments?id=eq.${id}&message_id=not.is.null&select=*&limit=1`))[0];if(!row)throw new InboxError("Anexo não encontrado.",404);
 await requireConversation(actor.employee_id,row.conversation_id);
 const key=hqServiceKey(),r=await fetch(`${supabaseUrl()}/storage/v1/object/sign/${inboxBucket}/${row.storage_path}`,{method:"POST",headers:{apikey:key,...(key.startsWith("sb_secret_")?{}:{Authorization:`Bearer ${key}`}),"Content-Type":"application/json"},body:JSON.stringify({expiresIn:60}),cache:"no-store"});
 const result=await r.json();if(!r.ok||!result.signedURL)throw new InboxError("Não foi possível abrir o anexo.",502);
 const url=new URL(result.signedURL.startsWith("/storage/v1/")?result.signedURL:`/storage/v1${result.signedURL}`,supabaseUrl());url.searchParams.set("download",row.file_name);
 return NextResponse.redirect(url,{status:302,headers:{"Cache-Control":"private, no-store","Referrer-Policy":"no-referrer"}});
 }catch(e){return NextResponse.json({error:e instanceof InboxError?e.message:"Não foi possível abrir o anexo."},{status:e instanceof InboxError?e.status:503})}}
