import { NextRequest, NextResponse } from "next/server";
import { corporateActor, supabaseUrl } from "@/lib/hq-server";

const platforms:Record<string,string>={deligo:"20000000-0000-0000-0000-000000000001",comunhao:"20000000-0000-0000-0000-000000000002",taomoz:"20000000-0000-0000-0000-000000000003",sarca:"20000000-0000-0000-0000-000000000004"};
const readRoles=new Set(["SUPER_ADMIN","CUSTOMER_SUPPORT","OPERATIONS","SUPERVISOR"]),writeRoles=new Set(["SUPER_ADMIN","CUSTOMER_SUPPORT","OPERATIONS"]);
const resources=["support_tickets","support_conversations","support_attachments","support_escalations","support_history","employees","platforms"];
const headers=(key:string)=>({apikey:key,Authorization:`Bearer ${key}`,"Accept-Profile":"hq","Content-Profile":"hq","Content-Type":"application/json",Prefer:"return=representation"});
async function ctx(){const actor=await corporateActor(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;return actor&&key&&readRoles.has(actor.role)?{actor,key}:null}
async function rest(key:string,path:string,init:RequestInit={}){const response=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...headers(key),...(init.headers||{})},cache:"no-store"});if(!response.ok)throw new Error(await response.text());return response.status===204?null:response.json()}
async function history(key:string,ticketId:string,eventType:string,description:string,actorId:string,metadata:Record<string,unknown>={}){await rest(key,"support_history",{method:"POST",body:JSON.stringify({ticket_id:ticketId,event_type:eventType,description,actor_employee_id:actorId,metadata})})}

export async function GET(){const c=await ctx();if(!c)return NextResponse.json({error:"Acesso reservado ao Apoio ao Cliente."},{status:403});const rows=await Promise.all(resources.map(async name=>{try{const select=name==="employees"?"id,employee_code,name,job_title,status":name==="platforms"?"id,slug,name":"*";return[name,await rest(c.key,`${name}?select=${select}&limit=600${["support_tickets","support_conversations","support_history"].includes(name)?`&order=${name==="support_tickets"?"updated_at":"created_at"}.desc`:""}`)] as const}catch{return[name,[]] as const}}));return NextResponse.json({data:Object.fromEntries(rows)},{headers:{"Cache-Control":"private, no-store"}})}

export async function POST(request:NextRequest){
  const c=await ctx();if(!c||!writeRoles.has(c.actor.role))return NextResponse.json({error:"Sem permissão para gerir atendimento."},{status:403});
  const body=await request.json() as {resource?:string;record?:Record<string,unknown>};if(!body.resource||!body.record)return NextResponse.json({error:"Dados insuficientes."},{status:400});
  try{
    if(body.resource==="ticket"){
      const record={...body.record,platform_id:platforms[String(body.record.platform_slug)]||null,status:"open"} as Record<string,unknown>;delete record.platform_slug;
      const created=(await rest(c.key,"support_tickets",{method:"POST",body:JSON.stringify(record)}))?.[0];await history(c.key,created.id,"opened","Ticket aberto",c.actor.employee_id,{type:record.ticket_type,category:record.category});return NextResponse.json({record:created},{status:201});
    }
    const mapping:Record<string,string>={message:"support_conversations",attachment:"support_attachments"},table=mapping[body.resource];if(!table)return NextResponse.json({error:"Operação de atendimento inválida."},{status:400});
    const record={...body.record} as Record<string,unknown>;
    if(table==="support_conversations"){record.sender_type="agent";record.sender_employee_id=c.actor.employee_id}
    if(table==="support_attachments")record.uploaded_by=c.actor.employee_id;
    const created=(await rest(c.key,table,{method:"POST",body:JSON.stringify(record)}))?.[0];await history(c.key,String(record.ticket_id),body.resource==="message"?"response_sent":"attachment_added",body.resource==="message"?"Resposta adicionada à conversa":"Anexo associado ao ticket",c.actor.employee_id);return NextResponse.json({record:created},{status:201});
  }catch{return NextResponse.json({error:"Não foi possível guardar o atendimento. Confirme cliente, plataforma e dados obrigatórios."},{status:409})}
}

export async function PATCH(request:NextRequest){
  const c=await ctx();if(!c||!writeRoles.has(c.actor.role))return NextResponse.json({error:"Sem permissão para atualizar atendimento."},{status:403});
  const body=await request.json() as {ticketId?:string;action?:string;employeeId?:string;reason?:string;resolution?:string};if(!body.ticketId||!body.action)return NextResponse.json({error:"Ação inválida."},{status:400});
  try{
    const ticket=(await rest(c.key,`support_tickets?id=eq.${encodeURIComponent(body.ticketId)}&select=*`))?.[0];if(!ticket)return NextResponse.json({error:"Ticket não encontrado."},{status:404});
    const changes:Record<string,unknown>={};
    if(body.action==="assign"){if(!body.employeeId)return NextResponse.json({error:"Selecione o agente responsável."},{status:400});changes.assigned_to=body.employeeId;changes.assigned_by=c.actor.employee_id;changes.status=ticket.status==="open"?"in_analysis":ticket.status}
    else if(body.action==="analysis")changes.status="in_analysis";
    else if(body.action==="waiting_customer")changes.status="waiting_customer";
    else if(body.action==="escalate"){if(!body.employeeId||String(body.reason||"").trim().length<6)return NextResponse.json({error:"Destino e motivo do escalonamento são obrigatórios."},{status:400});changes.status="escalated";changes.escalated_to=body.employeeId;changes.escalation_reason=body.reason;await rest(c.key,"support_escalations",{method:"POST",body:JSON.stringify({ticket_id:ticket.id,from_employee_id:ticket.assigned_to||c.actor.employee_id,to_employee_id:body.employeeId,reason:body.reason,status:"pending"})})}
    else if(body.action==="resolve"){if(String(body.resolution||"").trim().length<3)return NextResponse.json({error:"Indique a resolução aplicada."},{status:400});changes.status="resolved";changes.resolution=body.resolution}
    else if(body.action==="close")changes.status="closed";
    else if(body.action==="reopen")changes.status="in_analysis";
    else return NextResponse.json({error:"Ação inválida."},{status:400});
    await rest(c.key,`support_tickets?id=eq.${ticket.id}`,{method:"PATCH",body:JSON.stringify(changes)});await history(c.key,ticket.id,body.action,`Ticket atualizado: ${body.action}`,c.actor.employee_id,{reason:body.reason||null});return NextResponse.json({ok:true});
  }catch{return NextResponse.json({error:"A transição foi bloqueada. Confirme o estado, agente, escalonamento ou resolução."},{status:409})}
}
