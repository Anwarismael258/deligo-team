import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, hqRpc, supabaseUrl } from "@/lib/hq-server";

const entity = "10000000-0000-0000-0000-000000000001";
const supportDepartment = "30000000-0000-0000-0000-000000000010";
const platforms: Record<string, string> = { deligo:"20000000-0000-0000-0000-000000000001", comunhao:"20000000-0000-0000-0000-000000000002", taomoz:"20000000-0000-0000-0000-000000000003", sarca:"20000000-0000-0000-0000-000000000004" };
const directRoles = new Set(["SUPER_ADMIN","CUSTOMER_SUPPORT","OPERATIONS","SUPERVISOR"]);
const departmentRoles = new Set(["FINANCE","TECHNOLOGY","HUMAN_RESOURCES","LEGAL","COMPLIANCE"]);
const headers = (key:string) => ({ apikey:key, Authorization:`Bearer ${key}`, "Accept-Profile":"hq", "Content-Profile":"hq", "Content-Type":"application/json", Prefer:"return=representation" });

async function rest(key:string,path:string,init:RequestInit={}) { const response=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...headers(key),...(init.headers||{})},cache:"no-store"});if(!response.ok)throw new Error(await response.text());return response.status===204?null:response.json() }
async function context(permission="support.viewTickets",platform?:string){const authorization=await requireCorporatePermission(permission,platform),key=process.env.SUPABASE_SERVICE_ROLE_KEY,actor=authorization?.actor;if(!actor||!key||(!directRoles.has(actor.role)&&!departmentRoles.has(actor.role)))return null;const employee=(await rest(key,`employees?id=eq.${actor.employee_id}&select=department_id`))?.[0];return{actor,authorization,key,departmentId:String(employee?.department_id||"")}}
async function history(key:string,ticketId:string,eventType:string,description:string,actorId:string,metadata:Record<string,unknown>={}){await rest(key,"support_history",{method:"POST",body:JSON.stringify({ticket_id:ticketId,event_type:eventType,description,actor_employee_id:actorId,metadata})})}
async function audit(key:string,actorId:string,action:string,ticketId:string,metadata:Record<string,unknown>={}){await rest(key,"audit_logs",{method:"POST",body:JSON.stringify({actor_employee_id:actorId,action,legal_entity_id:entity,module:"support",target_type:"support_ticket",target_id:ticketId,result:"success",metadata})})}
function departmentFor(category:unknown,type:unknown){const value=`${String(category||"")} ${String(type||"")}`.toLowerCase();if(/t[eé]cnic|aplica[cç][aã]o|erro|sistema|api/.test(value))return"TECHNOLOGY";if(/pagamento|dep[oó]sito|levantamento|saldo|cobran[cç]a|reembolso/.test(value))return"FINANCE";if(/trabalhador|motorista|estafeta|agente|comportamento/.test(value))return"HR";if(/contrato|legal|jur[ií]dic|amea[cç]a/.test(value))return"LEGAL";if(/risco|fraude|seguran[cç]a|grave/.test(value))return"COMPLIANCE";return"SUPPORT"}
function ticketAllowed(current:{actor:{role:string};departmentId:string},ticket:Record<string,unknown>){return directRoles.has(current.actor.role)||String(ticket.current_department_id||ticket.department_id||"")===current.departmentId}

export async function GET(request:NextRequest){
  const requestedPlatform=request.nextUrl.searchParams.get("platform")||undefined,current=await context("support.viewTickets",requestedPlatform);if(!current)return NextResponse.json({error:"Acesso reservado ao atendimento e plataformas atribuídas."},{status:403});
  const departmentScope=departmentRoles.has(current.actor.role)?`&current_department_id=eq.${encodeURIComponent(current.departmentId)}`:"";
  const requestedPlatformId=requestedPlatform?platforms[requestedPlatform]:null,platformScope=requestedPlatformId?`&platform_id=eq.${requestedPlatformId}`:current.authorization.isSuperAdmin?"":current.authorization.platformIds.length?`&platform_id=in.(${current.authorization.platformIds.join(",")})`:`&platform_id=eq.00000000-0000-0000-0000-000000000000`,scope=`${departmentScope}${platformScope}`;
  const tickets=await rest(current.key,`support_tickets?select=*&limit=600${scope}&order=updated_at.desc`);
  const ids=(tickets||[]).map((row:{id:string})=>row.id),ticketFilter=ids.length?`ticket_id=in.(${ids.join(",")})`:"ticket_id=eq.00000000-0000-0000-0000-000000000000";
  const caseIds=(tickets||[]).map((row:{workflow_case_id?:string})=>row.workflow_case_id).filter(Boolean);
  const [conversations,attachments,escalations,assignments,events,cases,steps,employees,platformRows,departments]=await Promise.all([
    rest(current.key,`support_conversations?select=*&${ticketFilter}&order=created_at.desc&limit=600`),rest(current.key,`support_attachments?select=*&${ticketFilter}&limit=600`),
    rest(current.key,`support_escalations?select=*&${ticketFilter}&limit=600`),rest(current.key,`support_department_assignments?select=*&${ticketFilter}&order=created_at.desc&limit=600`),
    rest(current.key,`support_history?select=*&${ticketFilter}&order=created_at.desc&limit=600`),
    caseIds.length?rest(current.key,`workflow_cases?id=in.(${caseIds.join(",")})&select=*&limit=600`):[],
    caseIds.length?rest(current.key,`workflow_steps?case_id=in.(${caseIds.join(",")})&select=*&order=step_order&limit=600`):[],
    rest(current.key,"employees?select=id,employee_code,name,job_title,status,department_id&limit=600"),rest(current.key,"platforms?select=id,slug,name&limit=20"),rest(current.key,"departments?select=id,code,name&active=eq.true&limit=100")
  ]);
  return NextResponse.json({data:{support_tickets:tickets,support_conversations:conversations,support_attachments:attachments,support_escalations:escalations,support_department_assignments:assignments,support_history:events,workflow_cases:cases,workflow_steps:steps,employees,platforms:platformRows,departments}},{headers:{"Cache-Control":"private, no-store"}});
}

export async function POST(request:NextRequest){
  const body=await request.json() as {resource?:string;record?:Record<string,unknown>};if(!body.resource||!body.record)return NextResponse.json({error:"Dados insuficientes."},{status:400});
  const platform=body.resource==="ticket"?String(body.record.platform_slug||""):undefined,current=await context("support.reply",platform);if(!current)return NextResponse.json({error:"Sem permissão para gerir este atendimento ou plataforma."},{status:403});
  try{
    if(body.resource==="ticket"){
      if(departmentRoles.has(current.actor.role))return NextResponse.json({error:"A abertura de tickets pertence ao Apoio ao Cliente."},{status:403});
      const record={...body.record,platform_id:platforms[String(body.record.platform_slug)]||null,legal_entity_id:entity,department_id:supportDepartment,current_department_id:supportDepartment,created_by:current.actor.employee_id,status:"open"} as Record<string,unknown>;delete record.platform_slug;
      const created=(await rest(current.key,"support_tickets",{method:"POST",body:JSON.stringify(record)}))?.[0];await history(current.key,created.id,"opened","Ticket aberto",current.actor.employee_id,{type:record.ticket_type,category:record.category});
      const department=departmentFor(record.category,record.ticket_type),workflow=await hqRpc("hq_route_support_ticket_v1",{p_ticket_id:created.id,p_department_code:department,p_actor_employee_id:current.actor.employee_id,p_reason:`Encaminhamento automático pela categoria ${String(record.category)}`});
      return NextResponse.json({record:{...created,ticket_number:workflow.ticket_number},workflow},{status:201});
    }
    const table={message:"support_conversations",attachment:"support_attachments"}[body.resource];if(!table)return NextResponse.json({error:"Operação de atendimento inválida."},{status:400});
    const ticket=(await rest(current.key,`support_tickets?id=eq.${encodeURIComponent(String(body.record.ticket_id||""))}&select=*`))?.[0];if(!ticket||!ticketAllowed(current,ticket))return NextResponse.json({error:"O ticket não pertence ao seu departamento."},{status:403});
    const record={...body.record} as Record<string,unknown>;if(table==="support_conversations"){record.sender_type="agent";record.sender_employee_id=current.actor.employee_id}if(table==="support_attachments")record.uploaded_by=current.actor.employee_id;
    const created=(await rest(current.key,table,{method:"POST",body:JSON.stringify(record)}))?.[0];await history(current.key,ticket.id,body.resource==="message"?"response_sent":"attachment_added",body.resource==="message"?"Resposta adicionada à conversa":"Anexo associado ao ticket",current.actor.employee_id,{department_id:current.departmentId});await audit(current.key,current.actor.employee_id,`support_${body.resource}_created`,ticket.id,{record_id:created.id,department_id:current.departmentId});return NextResponse.json({record:created},{status:201});
  }catch{return NextResponse.json({error:"Não foi possível guardar o atendimento. Confirme cliente, plataforma e dados obrigatórios."},{status:409})}
}

export async function PATCH(request:NextRequest){
  const body=await request.json() as {ticketId?:string;action?:string;employeeId?:string;reason?:string;resolution?:string};if(!body.ticketId||!body.action)return NextResponse.json({error:"Ação inválida."},{status:400});
  const permission=["resolve","close"].includes(body.action)?"support.close":"support.reply",current=await context(permission);if(!current)return NextResponse.json({error:"Sem permissão para atualizar atendimento."},{status:403});
  try{
    const ticket=(await rest(current.key,`support_tickets?id=eq.${encodeURIComponent(body.ticketId)}&select=*`))?.[0];if(!ticket)return NextResponse.json({error:"Ticket não encontrado."},{status:404});if(!ticketAllowed(current,ticket))return NextResponse.json({error:"O ticket não pertence ao seu departamento."},{status:403});
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
