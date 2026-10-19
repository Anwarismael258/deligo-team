import {NextRequest, NextResponse} from "next/server";
import {corporateActor,supabaseUrl} from "@/lib/hq-server";
const h=(k:string)=>({apikey:k,Authorization:`Bearer ${k}`,"Accept-Profile":"hq","Content-Profile":"hq","Content-Type":"application/json"});
async function rest(k:string,p:string,init:RequestInit={}){const r=await fetch(`${supabaseUrl()}/rest/v1/${p}`,{...init,headers:{...h(k),...(init.headers||{})},cache:"no-store"});if(!r.ok)throw new Error(await r.text());return r.status===204?null:r.json()}
type Row=Record<string,unknown>;
const item=(kind:string,row:Row,title:unknown,description:unknown,status:unknown,priority:unknown,dueAt:unknown,url:string)=>({id:`${kind}:${row.id}`,sourceType:kind,sourceId:row.id,title:String(title||"Sem título"),description:String(description||""),status:String(status||"pending"),priority:String(priority||"normal"),dueAt:dueAt||null,platformId:row.platform_id||null,departmentId:row.department_id||row.current_department_id||row.target_department_id||null,responsibleId:row.assigned_to||row.owner_employee_id||null,taskOrigin:row.task_origin||null,taskType:row.task_type||null,url,updatedAt:row.updated_at||row.created_at});
export async function GET(){const actor=await corporateActor(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(!actor||!key)return NextResponse.json({error:"Sessão inválida."},{status:401});const employee=(await rest(key,`employees?id=eq.${actor.employee_id}&select=id,department_id`))?.[0],department=String(employee?.department_id||""),admin=actor.role==="SUPER_ADMIN";const [tasks,approvals,internal,tickets,steps,projects,contracts,departments,platforms]=await Promise.all([
 rest(key,`tasks?assigned_to=eq.${actor.employee_id}&status=not.in.(completed,cancelled)&select=*&order=due_at.asc.nullslast&limit=300`),
 rest(key,`approval_requests?status=in.(submitted,under_review)${admin?"":`&department_id=eq.${department}`}&select=*&order=submitted_at.asc.nullslast&limit=300`),
 rest(key,`internal_requests?or=(assigned_to.eq.${actor.employee_id},target_department_id.eq.${department})&status=not.in.(resolved,closed,archived)&select=*&order=due_at.asc.nullslast&limit=300`),
 rest(key,`support_tickets?or=(assigned_to.eq.${actor.employee_id},current_department_id.eq.${department})&status=not.in.(resolved,closed)&select=*&order=updated_at.desc&limit=300`),
 rest(key,`workflow_steps?or=(assigned_to.eq.${actor.employee_id},department_id.eq.${department})&status=in.(pending,in_progress,waiting_approval)&select=*&order=created_at.asc&limit=500`),
 rest(key,`projects?owner_employee_id=eq.${actor.employee_id}&status=not.in.(completed,cancelled)&select=*&order=due_date.asc.nullslast&limit=200`),
 rest(key,`contracts?owner_employee_id=eq.${actor.employee_id}&status=in.(draft,under_review,legal_review,approved,signed,active)&select=*&order=expires_on.asc.nullslast&limit=200`),
 rest(key,"departments?select=id,name,code&limit=100"),rest(key,"platforms?select=id,name,slug&limit=20")]);
 const items=[...tasks.map((r:Row)=>item("task",r,r.title,r.description,r.status,r.priority,r.due_at,"/projectos-tarefas")),...approvals.map((r:Row)=>item("approval",r,r.title,`Aprovação ${r.request_type}`,r.status,r.priority,r.submitted_at,"/aprovacoes")),...internal.map((r:Row)=>item("internal_request",r,r.subject,r.description,r.status,r.priority,r.due_at,"/apoio-interno")),...tickets.map((r:Row)=>item("support_ticket",r,`${r.ticket_number||"Ticket"} · ${r.subject}`,r.category,r.status,r.priority,r.updated_at,"/apoio-cliente")),...steps.map((r:Row)=>item("workflow_step",r,r.step_type,r.result,r.status,"high",r.updated_at,"/minhas-tarefas")),...projects.map((r:Row)=>item("project",r,r.name,r.objective,r.status,r.priority,r.due_date,"/projectos-tarefas")),...contracts.map((r:Row)=>item("contract",r,r.title,r.counterparty,r.status,"high",r.expires_on,"/juridico"))].sort((a,b)=>String(a.dueAt||"9999").localeCompare(String(b.dueAt||"9999")));
 const now=Date.now();return NextResponse.json({items,meta:{departments,platforms},summary:{total:items.length,overdue:items.filter(x=>x.dueAt&&new Date(String(x.dueAt)).getTime()<now).length,approvals:approvals.length,inProgress:items.filter(x=>x.status==="in_progress").length,waiting:items.filter(x=>["waiting","under_review","submitted","waiting_approval"].includes(x.status)).length}},{headers:{"Cache-Control":"private, no-store"}})}

export async function POST(req:NextRequest){
 const actor=await corporateActor(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!actor||!key)return NextResponse.json({error:"Sessão inválida."},{status:401});
 try{
  const body=await req.json() as {title?:string;description?:string;priority?:string;due_at?:string|null};
  const title=String(body.title||"").trim();
  if(!title)return NextResponse.json({error:"Indique um título para a tarefa."},{status:400});
  const entity="10000000-0000-0000-0000-000000000001";
  const created=(await rest(key,"tasks",{method:"POST",body:JSON.stringify({legal_entity_id:entity,title,description:String(body.description||"").trim()||null,priority:["low","normal","high","urgent"].includes(String(body.priority))?body.priority:"normal",status:"planned",assigned_to:actor.employee_id,assigned_by:actor.employee_id,created_by:actor.employee_id,due_at:body.due_at||null,task_origin:"manual",task_type:"general"})}))?.[0];
  return NextResponse.json({record:created},{status:201});
 }catch(error){return NextResponse.json({error:"Não foi possível criar a tarefa pessoal."},{status:409});}
}

export async function PATCH(req:NextRequest){
 const actor=await corporateActor(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!actor||!key)return NextResponse.json({error:"Sessão inválida."},{status:401});
 try{
  const body=await req.json() as {id?:string;action?:string};
  if(!body.id||!["start","block","resume","complete","cancel"].includes(String(body.action)))return NextResponse.json({error:"Ação inválida."},{status:400});
  const current=(await rest(key,`tasks?id=eq.${encodeURIComponent(body.id)}&assigned_to=eq.${actor.employee_id}&select=*`))?.[0];
  if(!current)return NextResponse.json({error:"Tarefa não encontrada ou não pertence a este utilizador."},{status:404});
  const statuses:Record<string,string>={start:"in_progress",block:"blocked",resume:"in_progress",complete:"completed",cancel:"cancelled"};
  const patch={status:statuses[String(body.action)],...(body.action==="complete"?{completed_at:new Date().toISOString()}: {})};
  const updated=(await rest(key,`tasks?id=eq.${encodeURIComponent(body.id)}&assigned_to=eq.${actor.employee_id}`,{method:"PATCH",body:JSON.stringify(patch)}))?.[0];
  return NextResponse.json({record:updated});
 }catch(error){return NextResponse.json({error:"Não foi possível atualizar a tarefa."},{status:409});}
}
