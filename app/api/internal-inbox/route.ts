import {NextRequest,NextResponse} from "next/server";
import {hqRest,hqRpc} from "@/lib/hq-server";
import {inboxActor,requireConversation,isUuid,InboxError,meetingUrl} from "@/lib/internal-inbox";
const respond=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{"Cache-Control":"private, no-store"}});
function failed(e:unknown){if(e instanceof InboxError)return respond({error:e.message},e.status);console.error("Internal inbox failed",e);return respond({error:"A Inbox interna ainda não está disponível. Contacte a administração para activar o serviço."},503)}
export async function GET(req:NextRequest){try{const actor=await inboxActor(),id=req.nextUrl.searchParams.get("conversation");if(!id){const [conversations,employees]=await Promise.all([hqRpc("chat_list_v1",{p_actor:actor.employee_id}),hqRest("employees?status=eq.active&select=id,display_name,employee_code&order=display_name&limit=500")]);return respond({actorId:actor.employee_id,conversations,employees})}
 await requireConversation(actor.employee_id,id);
 const beforeId=req.nextUrl.searchParams.get("beforeId");if(beforeId&&!isUuid(beforeId))throw new InboxError("Cursor inválido.");
 const before=req.nextUrl.searchParams.get("before");if(before&&(!Number.isFinite(Date.parse(before))))throw new InboxError("Data inválida.");
 const messages=await hqRest(`chat_messages?conversation_id=eq.${id}&select=*&order=created_at.desc,id.desc&limit=60${before?(beforeId?`&or=(created_at.lt.${encodeURIComponent(before)},and(created_at.eq.${encodeURIComponent(before)},id.lt.${beforeId}))`:`&created_at=lt.${encodeURIComponent(before)}`):""}`);
 const ids=messages.map((m:{id:string})=>m.id),replyIds=messages.map((m:{reply_to?:string})=>m.reply_to).filter(Boolean);
 const [attachments,replies]=await Promise.all([ids.length?hqRest(`chat_attachments?conversation_id=eq.${id}&message_id=in.(${ids.join(",")})&select=id,message_id,file_name,mime_type,size_bytes`):[],replyIds.length?hqRest(`chat_messages?conversation_id=eq.${id}&id=in.(${replyIds.join(",")})&select=id,body,sender_id`):[]]);
 return respond({messages:messages.reverse(),attachments,replies,hasMore:messages.length===60});
 }catch(e){return failed(e)}}
export async function POST(req:NextRequest){try{const actor=await inboxActor(),b=await req.json();if(b.action==="create"){
 const recipients=Array.isArray(b.recipients)?b.recipients:[];if(recipients.length>499||!recipients.every(isUuid)||typeof b.title!=="string"||b.title.length>120)throw new InboxError("Destinatários ou nome de grupo inválidos.");
 const id=await hqRpc("chat_create_v1",{p_actor:actor.employee_id,p_recipients:recipients,p_title:b.title,p_all:b.all===true});return respond({id},201)}
 const id=await requireConversation(actor.employee_id,b.conversationId);
 if(b.action!=="send"&&b.action!=="meeting")throw new InboxError("Acção inválida.");
 if(!isUuid(b.clientId)||(b.replyTo&&!isUuid(b.replyTo)))throw new InboxError("Identificador de mensagem inválido.");
 const files=b.files||[];if(!Array.isArray(files)||files.length>5||!files.every(isUuid))throw new InboxError("Anexos inválidos.");
 if(typeof b.body!=="string"||b.body.length>10000||(!b.body.trim()&&!files.length&&b.action!=="meeting"))throw new InboxError("Escreva uma mensagem ou anexe um ficheiro.");
 const message=await hqRpc("chat_send_v1",{p_actor:actor.employee_id,p_conversation:id,p_body:b.body,p_client:b.clientId,p_reply:b.replyTo||null,p_files:files,p_meeting:b.action==="meeting"?meetingUrl():null});return respond({message},201);
 }catch(e){return failed(e)}}
export async function PATCH(req:NextRequest){try{const actor=await inboxActor(),b=await req.json(),id=await requireConversation(actor.employee_id,b.conversationId);if(!isUuid(b.messageId))throw new InboxError("Mensagem inválida.");await hqRpc("chat_read_v1",{p_actor:actor.employee_id,p_conversation:id,p_message:b.messageId});return respond({ok:true})}catch(e){return failed(e)}}
