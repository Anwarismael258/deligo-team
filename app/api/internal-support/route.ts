import { NextRequest,NextResponse } from "next/server";
import { corporateActor,supabaseUrl } from "@/lib/hq-server";

const entity="10000000-0000-0000-0000-000000000001";
const headers=(key:string)=>({apikey:key,Authorization:`Bearer ${key}`,"Accept-Profile":"hq","Content-Profile":"hq","Content-Type":"application/json",Prefer:"return=representation"});
async function rest(key:string,path:string,init:RequestInit={}){const r=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...headers(key),...(init.headers||{})},cache:"no-store"});if(!r.ok)throw new Error(await r.text());return r.status===204?null:r.json()}
async function context(){const actor=await corporateActor(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(!actor||!key)return null;const employee=(await rest(key,`employees?id=eq.${actor.employee_id}&select=id,department_id,status`))?.[0];return employee?{actor,key,employee}:null}
async function history(key:string,requestId:string,actorId:string,action:string,before:unknown,after:unknown,comment?:string){await rest(key,"internal_request_history",{method:"POST",body:JSON.stringify({request_id:requestId,actor_employee_id:actorId,action,previous_state:before||null,final_state:after||null,comment:comment||null})});await rest(key,"audit_logs",{method:"POST",body:JSON.stringify({actor_employee_id:actorId,action:`internal_request_${action}`,legal_entity_id:entity,module:"internal_support",target_type:"internal_request",target_id:requestId,result:"success",metadata:{before:before||null,after:after||null}})})}

export async function GET(req:NextRequest){
  const c=await context();if(!c)return NextResponse.json({error:"Sessão inválida ou sem vínculo ativo."},{status:401});
  const admin=["SUPER_ADMIN","FINANCE"].includes(c.actor.role);
  const status=req.nextUrl.searchParams.get("status"),search=req.nextUrl.searchParams.get("search"),page=Math.max(1,Number(req.nextUrl.searchParams.get("page")||1)),pageSize=20,offset=(page-1)*pageSize;
  let query=`internal_requests?select=*&order=updated_at.desc&limit=${pageSize}&offset=${offset}`;
  const filters:string[]=[];
  if(!admin)filters.push(`or(requester_id.eq.${c.actor.employee_id},target_department_id.eq.${c.employee.department_id})`);
  if(status&&status!=="all")filters.push(`status.eq.${encodeURIComponent(status)}`);
  if(search){const term=encodeURIComponent(search.replace(/[,*()]/g," ").trim());filters.push(`or(subject.ilike.*${term}*,category.ilike.*${term}*,description.ilike.*${term}*)`)}
  if(filters.length)query+=`&and=(${filters.join(",")})`;
  const [requests,departments,employeesRaw]=await Promise.all([rest(c.key,query),rest(c.key,"departments?select=id,name,code&order=name"),rest(c.key,"employees?select=id,display_name,employee_code,status,department_id&status=eq.active&order=display_name&limit=500")]);
  const employees=(employeesRaw||[]).map((employee:Record<string,unknown>)=>({...employee,name:employee.display_name||"Trabalhador"}));
  const ids=(requests||[]).map((x:Record<string,unknown>)=>x.id);
  const [messages,events]=ids.length?await Promise.all([rest(c.key,`internal_request_messages?request_id=in.(${ids.join(",")})&select=*&order=created_at.asc`),rest(c.key,`internal_request_history?request_id=in.(${ids.join(",")})&select=*&order=created_at.desc`)]):[[],[]];
  return NextResponse.json({data:{requests,messages,history:events,departments,employees},pagination:{page,pageSize,hasMore:(requests||[]).length===pageSize},permissions:{canManageDepartment:true,canViewInternalNotes:admin||Boolean(c.employee.department_id)}},{headers:{"Cache-Control":"private, no-store"}});
}

export async function POST(req:NextRequest){
  const c=await context();if(!c)return NextResponse.json({error:"Sessão inválida."},{status:401});
  const admin=["SUPER_ADMIN","FINANCE"].includes(c.actor.role);
  const body=await req.json() as {resource?:"request"|"message";record?:Record<string,unknown>};if(!body.resource||!body.record)return NextResponse.json({error:"Registo inválido."},{status:400});
  try{
    if(body.resource==="request"){
      const record={...body.record,legal_entity_id:entity,requester_id:c.actor.employee_id,status:"open"};const created=(await rest(c.key,"internal_requests",{method:"POST",body:JSON.stringify(record)}))?.[0];await history(c.key,created.id,c.actor.employee_id,"created",null,created);return NextResponse.json({record:created},{status:201});
    }
    const requestId=String(body.record.request_id||""),ticket=(await rest(c.key,`internal_requests?id=eq.${encodeURIComponent(requestId)}&select=*`))?.[0];if(!ticket)return NextResponse.json({error:"Pedido não encontrado."},{status:404});
    const allowed=admin||ticket.requester_id===c.actor.employee_id||ticket.target_department_id===c.employee.department_id;if(!allowed)return NextResponse.json({error:"Sem acesso a este pedido."},{status:403});
    const internal=Boolean(body.record.is_internal);if(internal&&ticket.target_department_id!==c.employee.department_id&&!admin)return NextResponse.json({error:"Notas internas são reservadas ao departamento responsável."},{status:403});
    const created=(await rest(c.key,"internal_request_messages",{method:"POST",body:JSON.stringify({...body.record,author_employee_id:c.actor.employee_id})}))?.[0];await history(c.key,requestId,c.actor.employee_id,"message_added",null,{message_id:created.id,is_internal:internal});return NextResponse.json({record:created},{status:201});
  }catch{return NextResponse.json({error:"Não foi possível guardar o pedido."},{status:409})}
}

export async function PATCH(req:NextRequest){
  const c=await context();if(!c)return NextResponse.json({error:"Sessão inválida."},{status:401});
  const admin=["SUPER_ADMIN","FINANCE"].includes(c.actor.role);
  const body=await req.json() as {requestId?:string;action?:string;employeeId?:string;comment?:string;resolution?:string};if(!body.requestId||!body.action)return NextResponse.json({error:"Ação inválida."},{status:400});
  try{
    const current=(await rest(c.key,`internal_requests?id=eq.${encodeURIComponent(body.requestId)}&select=*`))?.[0];if(!current)return NextResponse.json({error:"Pedido não encontrado."},{status:404});
    const handles=admin||current.target_department_id===c.employee.department_id,isRequester=current.requester_id===c.actor.employee_id;if(!handles&&!isRequester)return NextResponse.json({error:"Sem acesso a este pedido."},{status:403});
    let patch:Record<string,unknown>={};
    if(body.action==="assign"){if(!handles||!body.employeeId)return NextResponse.json({error:"Atribuição reservada ao departamento responsável."},{status:403});const target=(await rest(c.key,`employees?id=eq.${encodeURIComponent(body.employeeId)}&department_id=eq.${current.target_department_id}&status=eq.active&select=id`))?.[0];if(!target)return NextResponse.json({error:"O colaborador não pertence ao departamento responsável."},{status:409});patch={assigned_to:body.employeeId,status:"assigned"}}
    else if(body.action==="start"){if(!handles)return NextResponse.json({error:"Sem permissão para iniciar."},{status:403});patch={status:"in_progress"}}
    else if(body.action==="wait"){if(!handles)return NextResponse.json({error:"Sem permissão."},{status:403});patch={status:"waiting_requester"}}
    else if(body.action==="resolve"){if(!handles||!body.resolution?.trim())return NextResponse.json({error:"Indique a resolução."},{status:400});patch={status:"resolved",resolution:body.resolution.trim()}}
    else if(body.action==="close"){if(!isRequester&&!admin)return NextResponse.json({error:"O solicitante deve confirmar o encerramento."},{status:403});patch={status:"closed"}}
    else if(body.action==="archive"){if(!admin)return NextResponse.json({error:"Arquivo reservado ao Super Admin."},{status:403});patch={status:"archived"}}
    else return NextResponse.json({error:"Ação não autorizada neste estado."},{status:400});
    const updated=(await rest(c.key,`internal_requests?id=eq.${encodeURIComponent(body.requestId)}`,{method:"PATCH",body:JSON.stringify(patch)}))?.[0];await history(c.key,body.requestId,c.actor.employee_id,body.action,current,updated,body.comment);return NextResponse.json({record:updated});
  }catch{return NextResponse.json({error:"A transição foi bloqueada pelo estado atual."},{status:409})}
}
