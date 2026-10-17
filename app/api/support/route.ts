import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRpc, supabaseUrl } from "@/lib/hq-server";

const entity = "10000000-0000-0000-0000-000000000001";
const supportDepartment = "30000000-0000-0000-0000-000000000010";
const platforms: Record<string, string> = { deligo:"20000000-0000-0000-0000-000000000001", comunhao:"20000000-0000-0000-0000-000000000002", taomoz:"20000000-0000-0000-0000-000000000003", sarca:"20000000-0000-0000-0000-000000000004", mestre24:"20000000-0000-0000-0000-000000000005" };
// Central support access is role-based and shared across all connected apps.
const viewerRoles = new Set(["SUPER_ADMIN","ADMIN","ADMINISTRATOR","SUPERVISOR","OPERATIONS_SUPERVISOR","CUSTOMER_SUPPORT","SUPPORT_AGENT","FINANCE","FINANCE_DIRECTOR"]);
const replyRoles = new Set(["SUPER_ADMIN","ADMIN","ADMINISTRATOR","SUPERVISOR","OPERATIONS_SUPERVISOR","CUSTOMER_SUPPORT","SUPPORT_AGENT","OPERATIONS"]);
const financeReplyActions = new Set(["analysis","waiting_customer","resolve"]);
const departmentRoles = new Set(["FINANCE","FINANCE_DIRECTOR","ACCOUNTING","TECHNOLOGY","HUMAN_RESOURCES","LEGAL","COMPLIANCE"]);
const financialTerms = /finance|finan[cç]|pagamento|pagar|dep[oó]sito|levantamento|saldo|cobran[cç]a|reembolso|estorno|fatura|transa[cç][aã]o|transfer[eê]ncia|payment|refund|withdrawal|deposit|billing/i;
function isFinanceRole(role:string){return role==="FINANCE"||role==="FINANCE_DIRECTOR";}
const headers = (key:string) => ({ apikey:key, Authorization:`Bearer ${key}`, "Accept-Profile":"hq", "Content-Profile":"hq", "Content-Type":"application/json", Prefer:"return=representation" });

async function rest(key:string,path:string,init:RequestInit={}) { const response=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...headers(key),...(init.headers||{})},cache:"no-store"});if(!response.ok)throw new Error(await response.text());return response.status===204?null:response.json() }
const coreHeaders=(key:string)=>({apikey:key,Authorization:`Bearer ${key}`,"Accept-Profile":"core","Content-Profile":"core","Content-Type":"application/json",Prefer:"return=representation"});
async function coreRest(key:string,path:string,init:RequestInit={}){const response=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...coreHeaders(key),...(init.headers||{})},cache:"no-store"});if(!response.ok)throw new Error(await response.text());return response.status===204?null:response.json()}
async function safe<T>(operation:Promise<T>,fallback:T):Promise<T>{try{return await operation}catch(error){console.error("SUPPORT_OPTIONAL_SOURCE_FAILED",String(error));return fallback}}
async function context(_permission="support.viewTickets",platform?:string){
  const authorization=await corporateAuthorization(),key=process.env.SUPABASE_SERVICE_ROLE_KEY,actor=authorization?.actor;
  const role=String(actor?.role||"").toUpperCase();
  if(!actor||!authorization||!key||!viewerRoles.has(role))return null;
  const hasPermission=authorization.isSuperAdmin||authorization.permissions.includes(_permission)||(isFinanceRole(role)&&_permission==="support.close");
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
  const phoneNumberId=process.env.WHATSAPP_PHONE_NUMBER_ID;
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
  const requestedPlatform=request.nextUrl.searchParams.get("platform")||undefined,current=await context("support.viewTickets",requestedPlatform);if(!current)return NextResponse.json({error:"Acesso reservado ao atendimento e plataformas atribuídas."},{status:403});
  // Authorized support roles can see the shared queue across every connected platform.
  const requestedPlatformId=requestedPlatform?platforms[requestedPlatform]:null;
  const scope=requestedPlatformId?`&platform_id=eq.${requestedPlatformId}`:"";
  const tickets=await safe(rest(current.key,`support_tickets?select=*&limit=600${scope}&order=updated_at.desc`),[]);
  const appCases=await safe(coreRest(current.key,"support_cases?select=*,app:apps(slug,name)&order=updated_at.desc&limit=600"),[]);
  const platformIdBySlug=platforms;
  const coreTickets=(Array.isArray(appCases)?appCases:[]).filter((item:{app?:{slug?:string}})=>{const slug=String(item.app?.slug||"");return (!requestedPlatform||slug===requestedPlatform)}).map((item:{id:string;case_number:number;app?:{slug?:string;name?:string};subject:string;description:string;status:string;priority:string;requester_name?:string;requester_phone?:string;requester_email?:string;requester_user_id?:string;category:string;assigned_user_id?:string;created_at:string;updated_at:string;source_channel?:string})=>({id:`core:${item.id}`,source:"app",ticket_number:`${String(item.app?.slug||"app").toUpperCase()}-${String(item.case_number).padStart(6,"0")}`,platform_id:platformIdBySlug[String(item.app?.slug||"")],platform_slug:item.app?.slug,platform_name:item.app?.name,subject:item.subject,description:item.description,status:item.status==="waiting_internal"?"escalated":item.status,priority:item.priority,ticket_type:"app_message",category:item.category,customer_name:item.requester_name,customer_contact:item.requester_phone||item.requester_email,customer_reference:item.requester_user_id,assigned_to:item.assigned_user_id,created_at:item.created_at,updated_at:item.updated_at,external_reference:item.source_channel}));
  const allTickets=[...(Array.isArray(tickets)?tickets:[]),...coreTickets];
  const ids=(tickets||[]).map((row:{id:string})=>row.id),ticketFilter=ids.length?`ticket_id=in.(${ids.join(",")})`:"ticket_id=eq.00000000-0000-0000-0000-000000000000";
  const caseIds=(tickets||[]).map((row:{workflow_case_id?:string})=>row.workflow_case_id).filter(Boolean);
  const coreIds=coreTickets.map((row:{id:string})=>row.id.slice(5));
  const coreFilter=coreIds.length?`case_id=in.(${coreIds.join(",")})`:"case_id=eq.00000000-0000-0000-0000-000000000000";
  const [conversations,attachments,escalations,assignments,events,cases,steps,employees,platformRows,departments,coreConversations,coreEvents]=await Promise.all([
    safe(rest(current.key,`support_conversations?select=*&${ticketFilter}&order=created_at.desc&limit=600`),[]),safe(rest(current.key,`support_attachments?select=*&${ticketFilter}&limit=600`),[]),
    safe(rest(current.key,`support_escalations?select=*&${ticketFilter}&limit=600`),[]),safe(rest(current.key,`support_department_assignments?select=*&${ticketFilter}&order=created_at.desc&limit=600`),[]),
    safe(rest(current.key,`support_history?select=*&${ticketFilter}&order=created_at.desc&limit=600`),[]),
    caseIds.length?safe(rest(current.key,`workflow_cases?id=in.(${caseIds.join(",")})&select=*&limit=600`),[]):[],
    caseIds.length?safe(rest(current.key,`workflow_steps?case_id=in.(${caseIds.join(",")})&select=*&order=step_order&limit=600`),[]):[],
    safe(rest(current.key,"employees?select=id,employee_code,name:display_name,job_title,status,department_id&limit=600"),[]),safe(rest(current.key,"platforms?select=id,slug,name&limit=20"),[]),safe(rest(current.key,"departments?select=id,code,name&active=eq.true&limit=100"),[]),
    safe(coreRest(current.key,`support_case_messages?select=*&${coreFilter}&order=created_at.asc&limit=1000`),[]),safe(coreRest(current.key,`support_case_events?select=*&${coreFilter}&order=created_at.desc&limit=1000`),[])
  ]);
  const coreMessages=(Array.isArray(coreConversations)?coreConversations:[]).map((item:{id:string;case_id:string;author_type:string;body:string;is_internal:boolean;created_at:string})=>({id:`core-msg:${item.id}`,ticket_id:`core:${item.case_id}`,sender_type:item.author_type==="staff"?"agent":"customer",message:item.body,is_internal:item.is_internal,created_at:item.created_at}));
  const coreHistory=(Array.isArray(coreEvents)?coreEvents:[]).map((item:{id:number;case_id:string;event_type:string;old_value?:unknown;new_value?:unknown;created_at:string})=>({id:`core-event:${item.id}`,ticket_id:`core:${item.case_id}`,event_type:item.event_type,description:`${item.event_type.replaceAll("_"," ")}`,metadata:{old_value:item.old_value,new_value:item.new_value},created_at:item.created_at}));
  return NextResponse.json({data:{support_tickets:allTickets,support_conversations:[...(Array.isArray(conversations)?conversations:[]),...coreMessages],support_attachments:attachments,support_escalations:escalations,support_department_assignments:assignments,support_history:[...(Array.isArray(events)?events:[]),...coreHistory],workflow_cases:cases,workflow_steps:steps,employees,platforms:platformRows,departments}},{headers:{"Cache-Control":"private, no-store"}});
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
  }catch{return NextResponse.json({error:"Não foi possível guardar o atendimento. Confirme cliente, plataforma e dados obrigatórios."},{status:409})}
}

export async function PATCH(request:NextRequest){
  const body=await request.json() as {ticketId?:string;action?:string;employeeId?:string;reason?:string;resolution?:string};if(!body.ticketId||!body.action)return NextResponse.json({error:"Ação inválida."},{status:400});
  const permission=["resolve","close"].includes(body.action)?"support.close":"support.reply",current=await context(permission);if(!current)return NextResponse.json({error:"Sem permissão para atualizar atendimento."},{status:403});
  if(isFinanceRole(current.actor.role)&&!financeReplyActions.has(body.action))return NextResponse.json({error:"Finance só pode atualizar o estado de atendimentos financeiros através das ações permitidas."},{status:403});
  try{
    if(String(body.ticketId).startsWith("core:")){
      const caseId=String(body.ticketId).slice(5),coreCase=(await coreRest(current.key,`support_cases?id=eq.${caseId}&select=*`))?.[0];if(!coreCase)return NextResponse.json({error:"Caso do app não encontrado."},{status:404});
      if(!canReplyToTicket(current,{category:coreCase.category,subject:coreCase.subject,description:coreCase.description}))return NextResponse.json({error:"O perfil Finance só pode atualizar atendimentos financeiros."},{status:403});
      const statusMap:Record<string,string>={assign:"assigned",analysis:"assigned",waiting_customer:"waiting_customer",resolve:"resolved",close:"closed",reopen:"open"};
      if(body.action==="escalate")return NextResponse.json({error:"Escalonamento de casos dos apps requer encaminhamento pelo departamento."},{status:409});
      const next=statusMap[body.action||""];if(!next)return NextResponse.json({error:"Ação inválida."},{status:400});
      if(body.action==="resolve"&&String(body.resolution||"").trim().length<3)return NextResponse.json({error:"Indique a resolução aplicada."},{status:400});
      const updated=(await coreRest(current.key,`support_cases?id=eq.${caseId}`,{method:"PATCH",body:JSON.stringify({status:next,updated_at:new Date().toISOString(),metadata:{...(coreCase.metadata||{}),last_hq_employee_id:current.actor.employee_id,resolution:body.resolution||null}})}))?.[0];
      await coreRest(current.key,"support_case_events",{method:"POST",body:JSON.stringify({case_id:caseId,event_type:`hq_${body.action}`,old_value:{status:coreCase.status},new_value:{status:next},metadata:{hq_employee_id:current.actor.employee_id,reason:body.reason||null}})});
      return NextResponse.json({ok:true,record:updated});
    }
    const ticket=(await rest(current.key,`support_tickets?id=eq.${encodeURIComponent(body.ticketId)}&select=*`))?.[0];if(!ticket)return NextResponse.json({error:"Ticket não encontrado."},{status:404});if(!canReplyToTicket(current,ticket))return NextResponse.json({error:"Sem permissão para atualizar este atendimento."},{status:403});
    const changes:Record<string,unknown>={};
    if(body.action==="assign"){if(departmentRoles.has(current.actor.role))return NextResponse.json({error:"A atribuição pertence ao Apoio ao Cliente."},{status:403});if(!body.employeeId)return NextResponse.json({error:"Selecione o agente responsável."},{status:400});changes.assigned_to=body.employeeId;changes.assigned_by=current.actor.employee_id;changes.status=ticket.status==="open"?"in_analysis":ticket.status}
    else if(body.action==="analysis")changes.status="in_analysis";
    else if(body.action==="waiting_customer")changes.status="waiting_customer";
    else if(body.action==="escalate"){if(!body.employeeId||String(body.reason||"").trim().length<6)return NextResponse.json({error:"Destino e motivo do escalonamento são obrigatórios."},{status:400});const employee=(await rest(current.key,`employees?id=eq.${encodeURIComponent(body.employeeId)}&select=id,department_id`))?.[0],department=(await rest(current.key,`departments?id=eq.${encodeURIComponent(String(employee?.department_id||""))}&select=code`))?.[0];if(!department?.code)return NextResponse.json({error:"O destino não possui departamento ativo."},{status:409});const workflow=await hqRpc("hq_route_support_ticket_v1",{p_ticket_id:ticket.id,p_department_code:department.code,p_actor_employee_id:current.actor.employee_id,p_reason:body.reason});return NextResponse.json({ok:true,workflow})}
    else if(body.action==="resolve"){if(String(body.resolution||"").trim().length<3)return NextResponse.json({error:"Indique a resolução aplicada."},{status:400});changes.status="resolved";changes.resolution=body.resolution}
    else if(body.action==="close"){if(departmentRoles.has(current.actor.role))return NextResponse.json({error:"O encerramento final pertence ao Apoio ao Cliente."},{status:403});changes.status="closed"}
    else if(body.action==="reopen")changes.status="in_analysis";else return NextResponse.json({error:"Ação inválida."},{status:400});
    const updated=(await rest(current.key,`support_tickets?id=eq.${ticket.id}`,{method:"PATCH",body:JSON.stringify(changes)}))?.[0];await history(current.key,ticket.id,body.action,`Ticket atualizado: ${body.action}`,current.actor.employee_id,{department_id:current.departmentId,reason:body.reason||null});await audit(current.key,current.actor.employee_id,`support_${body.action}`,ticket.id,{before:{status:ticket.status},after:{status:updated?.status},department_id:current.departmentId});return NextResponse.json({ok:true,record:updated});
  }catch{return NextResponse.json({error:"A transição foi bloqueada. Confirme o estado, agente, escalonamento ou resolução."},{status:409})}
}
