import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRpc, stagingRest, supabaseUrl } from "@/lib/hq-server";

const entity = "10000000-0000-0000-0000-000000000001";
const supportDepartment = "30000000-0000-0000-0000-000000000010";
const platforms: Record<string, string> = { deligo:"20000000-0000-0000-0000-000000000001", comunhao:"20000000-0000-0000-0000-000000000002", taomoz:"20000000-0000-0000-0000-000000000003", sarca:"20000000-0000-0000-0000-000000000004", mestre24:"20000000-0000-0000-0000-000000000005" };
// Central support access is role-based and shared across all connected apps.
const viewerRoles = new Set(["SUPER_ADMIN","SUPERVISOR","CUSTOMER_SUPPORT","FINANCE","ACCOUNTING","MARKETING"]);
const replyRoles = new Set(["SUPER_ADMIN","SUPERVISOR","CUSTOMER_SUPPORT","OPERATIONS","FINANCE","ACCOUNTING"]);
const escalationRoles = new Set(["SUPER_ADMIN","SUPERVISOR","FINANCE","ACCOUNTING"]);
const financeReplyActions = new Set(["analysis","waiting_customer","resolve","assign","escalate","reopen","mark_read"]);
const departmentRoles = new Set(["FINANCE","FINANCE_DIRECTOR","ACCOUNTING","TECHNOLOGY","HUMAN_RESOURCES","LEGAL","COMPLIANCE"]);
const financialTerms = /finance|finan[cç]|pagamento|pagar|dep[oó]sito|levantamento|saldo|cobran[cç]a|reembolso|estorno|fatura|transa[cç][aã]o|transfer[eê]ncia|payment|refund|withdrawal|deposit|billing/i;
function isFinanceRole(role:string){return role==="FINANCE"||role==="ACCOUNTING";}
const headers = (key:string) => ({ apikey:key, Authorization:`Bearer ${key}`, "Accept-Profile":"hq", "Content-Profile":"hq", "Content-Type":"application/json", Prefer:"return=representation" });

async function rest(key:string,path:string,init:RequestInit={}) { const response=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...headers(key),...(init.headers||{})},cache:"no-store"});if(!response.ok)throw new Error(await response.text());return response.status===204?null:response.json() }
const coreHeaders=(key:string)=>({apikey:key,Authorization:`Bearer ${key}`,"Accept-Profile":"core","Content-Profile":"core","Content-Type":"application/json",Prefer:"return=representation"});
async function coreRest(key:string,path:string,init:RequestInit={}){const response=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...coreHeaders(key),...(init.headers||{})},cache:"no-store"});if(!response.ok)throw new Error(await response.text());return response.status===204?null:response.json()}
async function safe<T>(operation:Promise<T>,fallback:T):Promise<T>{try{return await operation}catch(error){console.error("SUPPORT_OPTIONAL_SOURCE_FAILED",String(error));return fallback}}
async function context(_permission="support.viewTickets",platform?:string){
  const authorization=await corporateAuthorization(),key=process.env.SUPABASE_SERVICE_ROLE_KEY,actor=authorization?.actor;
  const role=String(actor?.role||"").toUpperCase();
  if(!actor||!authorization||!key||!viewerRoles.has(role))return null;
  const hasPermission=authorization.isSuperAdmin||authorization.permissions.includes(_permission)||(isFinanceRole(role)&&_permission==="support.close")||(_permission==="support.viewTickets"&&viewerRoles.has(role))||(_permission==="support.reply"&&replyRoles.has(role));
  if(!hasPermission)return null;
  if(platform&&!Object.prototype.hasOwnProperty.call(platforms,platform))return null;
  return{actor:{...actor,role},authorization,key,departmentId:""};
}
function isFinancialTicket(ticket:Record<string,unknown>){
  return financialTerms.test([ticket.category,ticket.ticket_type,ticket.subject,ticket.description,ticket.resolution].map(v=>String(v||"")).join(" "));
}
function canReplyToTicket(current:{actor:{role:string}},ticket:Record<string,unknown>){
  return replyRoles.has(current.actor.role)||(isFinanceRole(current.actor.role)&&isFinancialTicket(ticket));
}
async function sendWhatsAppReply(channel:unknown, contact:unknown, message:string):Promise<string|null>{
  if(String(channel||"").toLowerCase()!=="whatsapp")return null;
  const token=process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId=process.env.WHATSAPP_PHONE_NUMBER||process.env.WHATSAPP_PHONE_NUMBER_ID;
  const to=String(contact||"").replace(/[^0-9]/g,"");
  if(!token||!phoneNumberId||!to)throw new Error("WHATSAPP_OUTBOUND_NOT_CONFIGURED");
  const response=await fetch(`https://graph.facebook.com/v22.0/${phoneNumberId}/messages`,{
    method:"POST",
    headers:{Authorization:`Bearer ${token}`,"Content-Type":"application/json"},
    body:JSON.stringify({messaging_product:"whatsapp",recipient_type:"individual",to,type:"text",text:{preview_url:false,body:message}}),
    cache:"no-store",
  });
  const result=await response.json() as {messages?:Array<{id?:string}>;error?:{message?:string}};
  if(!response.ok)throw new Error(`WHATSAPP_SEND_FAILED: ${result.error?.message||response.status}`);
  return result.messages?.[0]?.id||null;
}
async function history(key:string,ticketId:string,eventType:string,description:string,actorId:string,metadata:Record<string,unknown>={}){await rest(key,"support_history",{method:"POST",body:JSON.stringify({ticket_id:ticketId,event_type:eventType,description,actor_employee_id:actorId,metadata})})}
async function audit(key:string,actorId:string,action:string,ticketId:string,metadata:Record<string,unknown>={}){await rest(key,"audit_logs",{method:"POST",body:JSON.stringify({actor_employee_id:actorId,action,legal_entity_id:entity,module:"support",target_type:"support_ticket",target_id:ticketId,result:"success",metadata})})}
function departmentFor(category:unknown,type:unknown){const value=`${String(category||"")} ${String(type||"")}`.toLowerCase();if(/t[eé]cnic|aplica[cç][aã]o|erro|sistema|api/.test(value))return"TECHNOLOGY";if(/pagamento|dep[oó]sito|levantamento|saldo|cobran[cç]a|reembolso/.test(value))return"FINANCE";if(/trabalhador|motorista|estafeta|agente|comportamento/.test(value))return"HR";if(/contrato|legal|jur[ií]dic|amea[cç]a/.test(value))return"LEGAL";if(/risco|fraude|seguran[cç]a|grave/.test(value))return"COMPLIANCE";return"SUPPORT"}


export async function GET(request:NextRequest){
  const requestedPlatform=request.nextUrl.searchParams.get("platform")||undefined,requestedTicket=request.nextUrl.searchParams.get("ticket")||"",current=await context("support.viewTickets",requestedPlatform);if(!current)return NextResponse.json({error:"Acesso reservado ao atendimento e plataformas atribuídas."},{status:403});
  // Authorized support roles can see the shared queue across every connected platform.
  const requestedPlatformId=requestedPlatform?platforms[requestedPlatform]:null;
  const scope=requestedPlatformId?`&platform_id=eq.${requestedPlatformId}`:"";
  // Keep this projection limited to columns created by the HQ support
  // migrations. A missing convenience column must not hide the whole queue.
  let ticketsHealthy=true;
  let publicTicketsHealthy=true;
  let publicMessagesHealthy=true;
  let tickets: Array<Record<string,unknown>>=[];
  try {
    tickets=await rest(current.key,`support_tickets?select=id,ticket_number,platform_id,external_reference,customer_reference,subject,description,status,priority,ticket_type,category,customer_name,customer_contact,assigned_to,created_at:opened_at,updated_at,source_channel,workflow_case_id&limit=300${scope}&order=updated_at.desc`) as Array<Record<string,unknown>>;
  } catch(error) {
    ticketsHealthy=false;
    console.error("SUPPORT_HQ_TICKETS_SOURCE_FAILED",String(error));
  }
  // The optional cross-platform `core` schema is not exposed by the current
  // PostgREST configuration. The public support bridge is the canonical
  // source for app-originated conversations in this environment; do not
  // retry an unavailable schema on every poll and delay/erase the queue.
  // Future exposed-core deployments can restore support_cases?select=*,app:apps.
  let publicTickets: Array<Record<string,unknown>>=[];
  try {
    publicTickets=await stagingRest("support_tickets?select=*&order=updated_at.desc&limit=300") as Array<Record<string,unknown>>;
  } catch(error) {
    publicTicketsHealthy=false;
    console.error("SUPPORT_PUBLIC_TICKETS_SOURCE_FAILED",String(error));
  }
  const publicIds=publicTickets.map(row=>String(row.id||"")).filter(Boolean);
  let publicMessages: Array<Record<string,unknown>>=[];
  if(publicIds.length){
    try {
      publicMessages=await stagingRest(`support_messages?ticket_id=in.(${publicIds.join(",")})&select=*&order=created_at.asc&limit=1000`) as Array<Record<string,unknown>>;
    } catch(error) {
      publicMessagesHealthy=false;
      console.error("SUPPORT_PUBLIC_MESSAGES_SOURCE_FAILED",String(error));
    }
  }
  const coreTickets: Array<{id:string}> = [];
  const publicTicketRows=publicTickets;
  const publicTicketIds=new Set(publicTicketRows.map(row=>String(row.id||"")));
  const publicTicketMapped=publicTicketRows.map(row=>{const meta=(row.metadata&&typeof row.metadata==="object"?row.metadata:{}) as Record<string,unknown>;const source=String(row.external_source||meta.platform||"app");return {id:`public:${String(row.id)}`,source:"public_app",ticket_number:`${source.toUpperCase()}-${String(row.external_id||row.id).slice(0,8)}`,platform_id:null,platform_slug:String(meta.platform_slug||source),platform_name:String(meta.platform_name||source),subject:String(row.reason||"Pedido de suporte"),description:String(row.reason||""),status:String(row.status||"open"),priority:String(meta.priority||"normal"),ticket_type:"app_message",category:String(row.dispute_type||"support"),customer_name:String(row.customer_name||"Utilizador"),customer_contact:String(row.customer_phone||row.customer_email||""),customer_reference:String(row.opened_by||""),assigned_to:row.assigned_to||null,created_at:String(row.created_at||""),updated_at:String(row.updated_at||row.created_at||""),external_reference:String(row.external_id||""),source_channel:source};});
  const publicMessagesMapped=publicMessages.filter(row=>publicTicketIds.has(String(row.ticket_id||""))).map(row=>{const senderRole=String(row.sender_role||"").toLowerCase();return {id:`public-msg:${String(row.id)}`,ticket_id:`public:${String(row.ticket_id)}`,sender_type:["client","customer","user","cliente"].includes(senderRole)?"customer":"agent",sender_employee_id:null,message:String(row.text||""),is_internal:false,created_at:String(row.created_at||""),is_read:Boolean(row.read_at)}});
  const publicAttachments=publicMessages.filter(row=>publicTicketIds.has(String(row.ticket_id||""))&&row.attachment_url).map(row=>({id:`public-attachment:${String(row.id)}`,ticket_id:`public:${String(row.ticket_id)}`,file_name:"Anexo do utilizador",mime_type:row.attachment_type||"ficheiro",storage_reference:row.attachment_url}));
  const publicExternalReferences=new Set(publicTicketMapped.map(ticket=>String(ticket.external_reference||"")).filter(Boolean));
  // The bridge mirrors public app tickets into HQ. Prefer the public record
  // for those mirrored tickets so the queue does not show duplicates or two
  // competing message histories.
  const hqTickets=tickets.filter(ticket=>!publicExternalReferences.has(String(ticket.external_reference||"")));
  let allTickets: Array<Record<string,unknown>>=[...hqTickets,...coreTickets,...publicTicketMapped];
  const ids=tickets.map(row=>String(row.id||"")),ticketFilter=ids.length?`ticket_id=in.(${ids.join(",")})`:"ticket_id=eq.00000000-0000-0000-0000-000000000000";
  const caseIds=tickets.map(row=>String(row.workflow_case_id||"")).filter(Boolean);
  const coreIds=coreTickets.map((row:{id:string})=>row.id.slice(5));
  const coreFilter=coreIds.length?`case_id=in.(${coreIds.join(",")})`:"case_id=eq.00000000-0000-0000-0000-000000000000";
  const legacyDetail=Boolean(requestedTicket)&&!requestedTicket.startsWith("core:")&&!requestedTicket.startsWith("public:")?requestedTicket:"";
  const legacyWorkflowCaseId=legacyDetail?String((tickets as Array<{id?:string;workflow_case_id?:string}>).find(row=>String(row.id)===legacyDetail)?.workflow_case_id||""):"";
  const coreDetail=requestedTicket.startsWith("core:")?requestedTicket.slice(5):"";
  const [conversations,attachments,escalations,assignments,events,cases,steps,employees,platformRows,departments,coreConversations,coreEvents]=await Promise.all([
    safe(rest(current.key,`support_conversations?select=id,ticket_id,sender_type,sender_employee_id,message,is_internal,created_at,external_message_id&${ticketFilter}&order=created_at.desc&limit=600`),[]),safe(legacyDetail?rest(current.key,`support_attachments?select=*&ticket_id=eq.${encodeURIComponent(legacyDetail)}&limit=100`):Promise.resolve([]),[]),
    safe(legacyDetail?rest(current.key,`support_escalations?select=*&ticket_id=eq.${encodeURIComponent(legacyDetail)}&limit=100`):Promise.resolve([]),[]),safe(legacyDetail?rest(current.key,`support_department_assignments?select=*&ticket_id=eq.${encodeURIComponent(legacyDetail)}&order=created_at.desc&limit=100`):Promise.resolve([]),[]),
    safe(legacyDetail?rest(current.key,`support_history?select=*&ticket_id=eq.${encodeURIComponent(legacyDetail)}&order=created_at.desc&limit=200`):Promise.resolve([]),[]),
    legacyWorkflowCaseId?safe(rest(current.key,`workflow_cases?id=eq.${encodeURIComponent(legacyWorkflowCaseId)}&select=*&limit=1`),[]):[],
    legacyWorkflowCaseId?safe(rest(current.key,`workflow_steps?case_id=eq.${encodeURIComponent(legacyWorkflowCaseId)}&select=*&order=step_order&limit=100`),[]):[],
    safe(rest(current.key,"employees?select=id,employee_code,name:display_name,job_title,status,department_id&limit=300"),[]),safe(rest(current.key,"platforms?select=id,slug,name&limit=20"),[]),safe(rest(current.key,"departments?select=id,code,name&active=eq.true&limit=100"),[]),
    safe(coreDetail?coreRest(current.key,`support_case_messages?select=*&case_id=eq.${encodeURIComponent(coreDetail)}&order=created_at.asc&limit=300`):Promise.resolve([]),[]),safe(coreDetail?coreRest(current.key,`support_case_events?select=*&case_id=eq.${encodeURIComponent(coreDetail)}&order=created_at.desc&limit=300`):Promise.resolve([]),[])
  ]);
  const readAtByCase=new Map<string,string>();
  for(const event of (Array.isArray(coreEvents)?coreEvents:[]) as Array<{case_id:string;actor_user_id?:string|null;event_type?:string;created_at:string}>){
    if(event.event_type!=="hq_case_opened" || event.actor_user_id!==current.actor.authUserId)continue;
    const previous=readAtByCase.get(event.case_id);
    if(!previous || new Date(event.created_at).getTime()>new Date(previous).getTime())readAtByCase.set(event.case_id,event.created_at);
  }
  const readAtByTicket=new Map<string,string>();
  for(const event of (Array.isArray(events)?events:[]) as Array<{ticket_id:string;actor_employee_id?:string|null;event_type?:string;created_at:string}>){
    if(event.event_type!=="hq_case_opened")continue;
    const previous=readAtByTicket.get(event.ticket_id);
    if(!previous || new Date(event.created_at).getTime()>new Date(previous).getTime())readAtByTicket.set(event.ticket_id,event.created_at);
  }
  const legacyMessages=(Array.isArray(conversations)?conversations:[]).map((item:Record<string,unknown>)=>({...item,is_read:item.sender_type!=="customer"||Boolean(readAtByTicket.get(String(item.ticket_id))&&new Date(String(item.created_at)).getTime()<=new Date(readAtByTicket.get(String(item.ticket_id)) as string).getTime())}));
  const coreMessages=(Array.isArray(coreConversations)?coreConversations:[]).map((item:{id:string;case_id:string;author_type:string;body:string;is_internal:boolean;created_at:string})=>({id:`core-msg:${item.id}`,ticket_id:`core:${item.case_id}`,sender_type:item.author_type==="staff"?"agent":"customer",message:item.body,is_internal:item.is_internal,created_at:item.created_at,is_read:item.author_type!=="customer"||Boolean(readAtByCase.get(item.case_id)&&new Date(item.created_at).getTime()<=new Date(readAtByCase.get(item.case_id) as string).getTime())}));
  allTickets=allTickets.map(ticket=>{const ticketId=String(ticket.id||"");return ticketId.startsWith("core:")?{...ticket,last_read_at:readAtByCase.get(ticketId.slice(5))||null}:ticket;});
  const coreHistory=(Array.isArray(coreEvents)?coreEvents:[]).filter((item:{event_type?:string})=>item.event_type!=="hq_case_opened").map((item:{id:number;case_id:string;event_type:string;old_value?:unknown;new_value?:unknown;created_at:string})=>({id:`core-event:${item.id}`,ticket_id:`core:${item.case_id}`,event_type:item.event_type,description:`${item.event_type.replaceAll("_"," ")}`,metadata:{old_value:item.old_value,new_value:item.new_value},created_at:item.created_at}));
  const legacyHistory=(Array.isArray(events)?events:[]).filter((item:{event_type?:string})=>item.event_type!=="hq_case_opened");
  const orderedConversations=[...legacyMessages,...coreMessages,...publicMessagesMapped].sort((left,right)=>new Date(String((left as Record<string,unknown>).created_at||0)).getTime()-new Date(String((right as Record<string,unknown>).created_at||0)).getTime());
  return NextResponse.json({data:{support_tickets:allTickets,support_conversations:orderedConversations,support_attachments:[...(Array.isArray(attachments)?attachments:[]),...publicAttachments],support_escalations:escalations,support_department_assignments:assignments,support_history:[...legacyHistory,...coreHistory],workflow_cases:cases,workflow_steps:steps,employees,platforms:platformRows,departments},meta:{degraded:!ticketsHealthy&&!publicTicketsHealthy||!publicMessagesHealthy,ticketsHealthy,publicTicketsHealthy,publicMessagesHealthy}},{headers:{"Cache-Control":"private, no-store"}});
}

export async function POST(request:NextRequest){
  const body=await request.json() as {resource?:string;record?:Record<string,unknown>};if(!body.resource||!body.record)return NextResponse.json({error:"Dados insuficientes."},{status:400});
  const platform=body.resource==="ticket"?String(body.record.platform_slug||""):undefined,current=await context("support.reply",platform);if(!current)return NextResponse.json({error:"Sem permissão para gerir este atendimento ou plataforma."},{status:403});
  if(body.resource==="ticket"&&!replyRoles.has(current.actor.role))return NextResponse.json({error:"Este perfil pode consultar e responder apenas a atendimentos financeiros já existentes."},{status:403});
  try{
    if(body.resource==="ticket"){
      if(departmentRoles.has(current.actor.role))return NextResponse.json({error:"A abertura de tickets pertence ao Apoio ao Cliente."},{status:403});
      const record={...body.record,platform_id:platforms[String(body.record.platform_slug)]||null,legal_entity_id:entity,department_id:supportDepartment,current_department_id:supportDepartment,created_by:current.actor.employee_id,status:"open"} as Record<string,unknown>;delete record.platform_slug;
      const created=(await rest(current.key,"support_tickets",{method:"POST",body:JSON.stringify(record)}))?.[0];await history(current.key,created.id,"opened","Ticket aberto",current.actor.employee_id,{type:record.ticket_type,category:record.category});
      const department=departmentFor(record.category,record.ticket_type),workflow=await hqRpc("hq_route_support_ticket_v1",{p_ticket_id:created.id,p_department_code:department,p_actor_employee_id:current.actor.employee_id,p_reason:`Encaminhamento automático pela categoria ${String(record.category)}`});
      return NextResponse.json({record:{...created,ticket_number:workflow.ticket_number},workflow},{status:201});
    }
    const table={message:"support_conversations",attachment:"support_attachments"}[body.resource];if(!table)return NextResponse.json({error:"Operação de atendimento inválida."},{status:400});
    if(String(body.record.ticket_id||"").startsWith("public:")){
      const publicId=String(body.record.ticket_id).slice(7),publicTicket=(await stagingRest(`support_tickets?id=eq.${encodeURIComponent(publicId)}&select=*`) as Array<Record<string,unknown>>)?.[0];
      if(!publicTicket)return NextResponse.json({error:"Atendimento do aplicativo não encontrado."},{status:404});
      if(!canReplyToTicket(current,{...publicTicket,category:publicTicket.dispute_type,subject:publicTicket.reason,description:publicTicket.reason}))return NextResponse.json({error:"Sem permissão para responder a este atendimento."},{status:403});
      if(body.resource==="message"||body.resource==="attachment"){
        const record=body.resource==="message"?{ticket_id:publicId,sender_id:current.actor.authUserId,sender_name:current.actor.name,sender_role:"support_agent",text:`${String(body.record.message||"").trim()}\n\n— ${current.actor.name}`}:{ticket_id:publicId,sender_id:current.actor.authUserId,sender_name:current.actor.name,sender_role:"support_agent",text:`Anexo enviado por ${current.actor.name}`,attachment_url:body.record.storage_reference||null,attachment_type:body.record.mime_type||null};
        const created=(await stagingRest("support_messages",{method:"POST",body:JSON.stringify({...record,delivered_at:new Date().toISOString()})}) as Array<Record<string,unknown>>)?.[0];
        // The message is already available to the platform after INSERT. Do
        // not make the sender wait for the secondary ticket-state update.
        void stagingRest(`support_tickets?id=eq.${encodeURIComponent(publicId)}`,{method:"PATCH",body:JSON.stringify({status:"in_progress",updated_at:new Date().toISOString()})}).catch(error=>console.error("SUPPORT_PUBLIC_TICKET_STATUS_UPDATE_FAILED",String(error)));
        return NextResponse.json({record:{...created,id:`public-msg:${String(created?.id||"")}`,ticket_id:`public:${publicId}`,sender_type:"agent",message:created?.text||record.text,delivered_at:created?.delivered_at||new Date().toISOString()}},{status:201});
      }
    }
    if(String(body.record.ticket_id||"").startsWith("core:")){
      const caseId=String(body.record.ticket_id).slice(5);
      if(body.resource!=="message")return NextResponse.json({error:"Anexos de casos dos apps devem usar o armazenamento do app."},{status:409});
      const coreCase=(await coreRest(current.key,`support_cases?id=eq.${caseId}&select=*,app:apps(slug,name)`))?.[0];
      if(!coreCase)return NextResponse.json({error:"Atendimento não encontrado."},{status:404});
      const coreCategory={category:coreCase.category,subject:coreCase.subject,description:coreCase.description};
      if(!canReplyToTicket(current,coreCategory))return NextResponse.json({error:"O perfil Finance só pode responder a assuntos financeiros."},{status:403});
      const isInternal=body.record.is_internal==="true"||body.record.is_internal===true;
      const signedBody=`${String(body.record.message||"").trim()}\n\n— ${current.actor.name}`;
      const outboundId=isInternal?null:await sendWhatsAppReply(coreCase.source_channel,coreCase.requester_phone,signedBody);
      const created=(await coreRest(current.key,"support_case_messages",{method:"POST",body:JSON.stringify({case_id:caseId,author_type:"staff",body:signedBody,is_internal:isInternal,metadata:{hq_employee_id:current.actor.employee_id,source_channel:coreCase.source_channel||"app",whatsapp_message_id:outboundId}})}))?.[0];
      await coreRest(current.key,`support_cases?id=eq.${caseId}`,{method:"PATCH",body:JSON.stringify({status:"assigned",updated_at:new Date().toISOString()})});
      await coreRest(current.key,"support_case_events",{method:"POST",body:JSON.stringify({case_id:caseId,event_type:"hq_reply_sent",metadata:{hq_employee_id:current.actor.employee_id,channel:coreCase.source_channel||"app"}})});
      return NextResponse.json({record:{...created,id:`core-msg:${created.id}`,ticket_id:`core:${caseId}`,sender_type:"agent",message:created.body}},{status:201});
    }
    const ticket=(await rest(current.key,`support_tickets?id=eq.${encodeURIComponent(String(body.record.ticket_id||""))}&select=*`))?.[0];if(!ticket||!canReplyToTicket(current,ticket))return NextResponse.json({error:"Sem permissão para responder a este atendimento. O perfil Finance só pode responder a assuntos financeiros."},{status:403});
    const record={...body.record} as Record<string,unknown>;
    if(table==="support_conversations"){
      record.sender_type="agent";record.sender_employee_id=current.actor.employee_id;
      record.message=`${String(record.message||"").trim()}\n\n— ${current.actor.name}`;
      const isInternal=record.is_internal==="true"||record.is_internal===true;
      const outboundId=isInternal?null:await sendWhatsAppReply(ticket.source_channel,ticket.customer_contact,String(record.message));
      record.source_channel=String(ticket.source_channel||"central");
      if(outboundId)record.external_message_id=outboundId;
    }
    if(table==="support_attachments")record.uploaded_by=current.actor.employee_id;
    const created=(await rest(current.key,table,{method:"POST",body:JSON.stringify(record)}))?.[0];await history(current.key,ticket.id,body.resource==="message"?"response_sent":"attachment_added",body.resource==="message"?"Resposta adicionada à conversa":"Anexo associado ao ticket",current.actor.employee_id,{department_id:current.departmentId,source_channel:ticket.source_channel||"central"});await audit(current.key,current.actor.employee_id,`support_${body.resource}_created`,ticket.id,{record_id:created.id,department_id:current.departmentId});return NextResponse.json({record:created},{status:201});
  }catch(error){const message=error instanceof Error?error.message:"";if(message.includes("WHATSAPP_OUTBOUND_NOT_CONFIGURED"))return NextResponse.json({error:"WhatsApp ainda não está configurado no deployment: faltam WHATSAPP_ACCESS_TOKEN ou WHATSAPP_PHONE_NUMBER_ID."},{status:503});if(message.includes("WHATSAPP_SEND_FAILED"))return NextResponse.json({error:"O WhatsApp recusou o envio. Confirme o número, o token Meta e a janela de atendimento."},{status:502});return NextResponse.json({error:"Não foi possível guardar o atendimento. Confirme cliente, plataforma e dados obrigatórios."},{status:409})}
}

export async function PATCH(request:NextRequest){
  const body=await request.json() as {ticketId?:string;action?:string;employeeId?:string;reason?:string;resolution?:string};if(!body.ticketId||!body.action)return NextResponse.json({error:"Ação inválida."},{status:400});
  const permission=["resolve","close"].includes(body.action)?"support.close":"support.reply",current=await context(permission);if(!current)return NextResponse.json({error:"Sem permissão para atualizar atendimento."},{status:403});
  if(isFinanceRole(current.actor.role)&&!financeReplyActions.has(body.action))return NextResponse.json({error:"Finance só pode atualizar o estado de atendimentos financeiros através das ações permitidas."},{status:403});
  try{
    if(String(body.ticketId).startsWith("public:")){
      const publicId=String(body.ticketId).slice(7),publicTicket=(await stagingRest(`support_tickets?id=eq.${encodeURIComponent(publicId)}&select=*`) as Array<Record<string,unknown>>)?.[0];
      if(!publicTicket)return NextResponse.json({error:"Atendimento do aplicativo não encontrado."},{status:404});
      if(body.action==="mark_read"){
        await stagingRest(`support_messages?ticket_id=eq.${encodeURIComponent(publicId)}&sender_role=in.(client,customer,user,cliente)&read_at=is.null`,{method:"PATCH",body:JSON.stringify({read_at:new Date().toISOString()})});
        return NextResponse.json({ok:true,readAt:new Date().toISOString()});
      }
      if(!canReplyToTicket(current,{...publicTicket,category:publicTicket.dispute_type,subject:publicTicket.reason,description:publicTicket.reason}))return NextResponse.json({error:"Sem permissão para atualizar este atendimento."},{status:403});
      const statusMap:Record<string,string>={analysis:"in_progress",waiting_customer:"waiting",resolve:"resolved",close:"closed",reopen:"open"};
      const next=statusMap[body.action||""];if(!next)return NextResponse.json({error:"Ação inválida."},{status:400});
      const updated=(await stagingRest(`support_tickets?id=eq.${encodeURIComponent(publicId)}`,{method:"PATCH",body:JSON.stringify({status:next,updated_at:new Date().toISOString(),resolution:body.resolution||null})}) as Array<Record<string,unknown>>)?.[0];
      return NextResponse.json({ok:true,record:updated});
    }
    if(String(body.ticketId).startsWith("core:")){
      const caseId=String(body.ticketId).slice(5),coreCase=(await coreRest(current.key,`support_cases?id=eq.${caseId}&select=*`))?.[0];if(!coreCase)return NextResponse.json({error:"Caso do app não encontrado."},{status:404});
      if(body.action==="mark_read"){
        await coreRest(current.key,"support_case_events",{method:"POST",body:JSON.stringify({case_id:caseId,actor_user_id:current.actor.authUserId,event_type:"hq_case_opened",metadata:{employee_id:current.actor.employee_id}})});
        return NextResponse.json({ok:true,readAt:new Date().toISOString()});
      }
      if(!canReplyToTicket(current,{category:coreCase.category,subject:coreCase.subject,description:coreCase.description}))return NextResponse.json({error:"O perfil Finance só pode atualizar atendimentos financeiros."},{status:403});
      const statusMap:Record<string,string>={assign:"assigned",analysis:"assigned",waiting_customer:"waiting_customer",resolve:"resolved",close:"closed",reopen:"open"};
      if(body.action==="escalate")return NextResponse.json({error:"Escalonamento de casos dos apps requer encaminhamento pelo departamento."},{status:409});
      const next=statusMap[body.action||""];if(!next)return NextResponse.json({error:"Ação inválida."},{status:400});
      if(body.action==="resolve"&&String(body.resolution||"").trim().length<3)return NextResponse.json({error:"Indique a resolução aplicada."},{status:400});
      const updated=(await coreRest(current.key,`support_cases?id=eq.${caseId}`,{method:"PATCH",body:JSON.stringify({status:next,updated_at:new Date().toISOString(),metadata:{...(coreCase.metadata||{}),last_hq_employee_id:current.actor.employee_id,resolution:body.resolution||null}})}))?.[0];
      await coreRest(current.key,"support_case_events",{method:"POST",body:JSON.stringify({case_id:caseId,event_type:`hq_${body.action}`,old_value:{status:coreCase.status},new_value:{status:next},metadata:{hq_employee_id:current.actor.employee_id,reason:body.reason||null}})});
      return NextResponse.json({ok:true,record:updated});
    }
    if(body.action==="mark_read"){
      await history(current.key,String(body.ticketId),"hq_case_opened","Atendimento aberto pela Central",current.actor.employee_id,{employee_id:current.actor.employee_id});
      return NextResponse.json({ok:true});
    }
    const ticket=(await rest(current.key,`support_tickets?id=eq.${encodeURIComponent(body.ticketId)}&select=*`))?.[0];if(!ticket)return NextResponse.json({error:"Ticket não encontrado."},{status:404});if(!canReplyToTicket(current,ticket))return NextResponse.json({error:"Sem permissão para atualizar este atendimento."},{status:403});
    const changes:Record<string,unknown>={};
    if(body.action==="assign"){if(!escalationRoles.has(current.actor.role))return NextResponse.json({error:"Só Admin, Finance e Supervisor podem atribuir atendimentos."},{status:403});if(!body.employeeId)return NextResponse.json({error:"Selecione o agente responsável."},{status:400});const employee=(await rest(current.key,`employees?id=eq.${encodeURIComponent(body.employeeId)}&select=id,department_id,status`))?.[0],department=(await rest(current.key,`departments?id=eq.${encodeURIComponent(String(employee?.department_id||""))}&select=code`))?.[0];if(employee?.status!=="active"||!["SUPPORT","CUSTOMER_SUPPORT"].includes(String(department?.code||"").toUpperCase()))return NextResponse.json({error:"Escolha um agente ativo do Apoio ao Cliente."},{status:400});changes.assigned_to=body.employeeId;changes.assigned_by=current.actor.employee_id;changes.status=ticket.status==="open"?"in_analysis":ticket.status}
    else if(body.action==="analysis")changes.status="in_analysis";
    else if(body.action==="waiting_customer")changes.status="waiting_customer";
    else if(body.action==="escalate"){if(!escalationRoles.has(current.actor.role))return NextResponse.json({error:"Só Admin, Finance e Supervisor podem escalar atendimentos."},{status:403});if(!body.employeeId||String(body.reason||"").trim().length<6)return NextResponse.json({error:"Escolha um agente e indique um motivo com pelo menos 6 caracteres."},{status:400});const employee=(await rest(current.key,`employees?id=eq.${encodeURIComponent(body.employeeId)}&select=id,department_id,status`))?.[0],department=(await rest(current.key,`departments?id=eq.${encodeURIComponent(String(employee?.department_id||""))}&select=code`))?.[0];if(employee?.status!=="active"||!["SUPPORT","CUSTOMER_SUPPORT"].includes(String(department?.code||"").toUpperCase()))return NextResponse.json({error:"Escolha um agente ativo do Apoio ao Cliente."},{status:400});const workflow=await hqRpc("hq_route_support_ticket_v1",{p_ticket_id:ticket.id,p_department_code:department.code,p_actor_employee_id:current.actor.employee_id,p_reason:body.reason});const updated=(await rest(current.key,`support_tickets?id=eq.${ticket.id}`,{method:"PATCH",body:JSON.stringify({assigned_to:body.employeeId,assigned_by:current.actor.employee_id,escalated_to:body.employeeId,escalated_at:new Date().toISOString(),escalation_reason:body.reason,status:"escalated",updated_at:new Date().toISOString()})}))?.[0];await history(current.key,ticket.id,"escalated",`Atendimento escalado para agente ${body.employeeId}`,current.actor.employee_id,{to_employee_id:body.employeeId,reason:body.reason,department_code:department.code});await audit(current.key,current.actor.employee_id,"support_escalated",ticket.id,{to_employee_id:body.employeeId,reason:body.reason,department_code:department.code});return NextResponse.json({ok:true,record:updated,workflow})}
    else if(body.action==="resolve"){if(String(body.resolution||"").trim().length<3)return NextResponse.json({error:"Indique a resolução aplicada."},{status:400});changes.status="resolved";changes.resolution=body.resolution}
    else if(body.action==="close"){if(departmentRoles.has(current.actor.role))return NextResponse.json({error:"O encerramento final pertence ao Apoio ao Cliente."},{status:403});changes.status="closed"}
    else if(body.action==="reopen")changes.status="in_analysis";else return NextResponse.json({error:"Ação inválida."},{status:400});
    const updated=(await rest(current.key,`support_tickets?id=eq.${ticket.id}`,{method:"PATCH",body:JSON.stringify(changes)}))?.[0];await history(current.key,ticket.id,body.action,`Ticket atualizado: ${body.action}`,current.actor.employee_id,{department_id:current.departmentId,reason:body.reason||null});await audit(current.key,current.actor.employee_id,`support_${body.action}`,ticket.id,{before:{status:ticket.status},after:{status:updated?.status},department_id:current.departmentId});return NextResponse.json({ok:true,record:updated});
  }catch{return NextResponse.json({error:"A transição foi bloqueada. Confirme o estado, agente, escalonamento ou resolução."},{status:409})}
}
