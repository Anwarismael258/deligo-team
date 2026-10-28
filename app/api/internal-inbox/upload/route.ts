import {NextRequest,NextResponse} from "next/server";
import {hqRest,hqServiceKey,supabaseUrl} from "@/lib/hq-server";
import {inboxActor,requireConversation,inboxBucket,attachmentTypes,maxAttachmentBytes,InboxError} from "@/lib/internal-inbox";
export async function POST(req:NextRequest){let storedPath:string|null=null;try{
 const actor=await inboxActor();if(Number(req.headers.get("content-length")||0)>maxAttachmentBytes+65536)throw new InboxError("O ficheiro deve ter até 3 MB.",413);
 const form=await req.formData(),id=await requireConversation(actor.employee_id,form.get("conversationId")),file=form.get("file");
 if(!(file instanceof File)||file.size<1||file.size>maxAttachmentBytes||!attachmentTypes.has(file.type))throw new InboxError("Use um documento, imagem, áudio ou vídeo permitido, até 3 MB.");
 const name=file.name.replace(/[\x00-\x1f/\\]/g,"_").slice(0,180)||"anexo";
 const path=`${id}/${actor.employee_id}/${crypto.randomUUID()}`;const key=hqServiceKey();
 const r=await fetch(`${supabaseUrl()}/storage/v1/object/${inboxBucket}/${path}`,{method:"POST",headers:{apikey:key,...(key.startsWith("sb_secret_")?{}:{Authorization:`Bearer ${key}`}),"Content-Type":file.type,"x-upsert":"false"},body:await file.arrayBuffer(),cache:"no-store"});
 if(!r.ok)throw new InboxError("Não foi possível guardar o anexo. Verifique o bucket privado hq-internal-inbox.",502);storedPath=path;
 const rows=await hqRest("chat_attachments",{method:"POST",body:JSON.stringify({conversation_id:id,uploaded_by:actor.employee_id,storage_path:path,file_name:name,mime_type:file.type,size_bytes:file.size})});return NextResponse.json({attachment:{id:rows[0].id,file_name:name,size_bytes:file.size}},{status:201});
 }catch(e){if(storedPath){const key=hqServiceKey();await fetch(`${supabaseUrl()}/storage/v1/object/${inboxBucket}`,{method:"DELETE",headers:{apikey:key,...(key.startsWith("sb_secret_")?{}:{Authorization:`Bearer ${key}`}),"Content-Type":"application/json"},body:JSON.stringify({prefixes:[storedPath]})}).catch(()=>null)}return NextResponse.json({error:e instanceof InboxError?e.message:"Não foi possível anexar o ficheiro."},{status:e instanceof InboxError?e.status:503})}}
