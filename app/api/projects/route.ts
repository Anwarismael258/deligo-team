import { NextRequest, NextResponse } from "next/server";
import { corporateActor, supabaseUrl } from "@/lib/hq-server";

const entity = "10000000-0000-0000-0000-000000000001";
const platforms: Record<string,string> = {
  deligo:"20000000-0000-0000-0000-000000000001",
  comunhao:"20000000-0000-0000-0000-000000000002",
  corporate:"20000000-0000-0000-0000-000000000006",
  sarca:"20000000-0000-0000-0000-000000000004",
  mestre24:"20000000-0000-0000-0000-000000000005",
};
const readers = new Set(["SUPER_ADMIN","FINANCE","SUPERVISOR","OPERATIONS","TECHNOLOGY","MARKETING","FIELD","CUSTOMER_SUPPORT","HUMAN_RESOURCES","ACQUISITION","OPERATIONS_SUPERVISOR"]);
const writers = new Set(readers);
const headers = (key:string) => ({apikey:key,Authorization:`Bearer ${key}`,"Accept-Profile":"hq","Content-Profile":"hq","Content-Type":"application/json",Prefer:"return=representation"});

async function context(){
  const actor=await corporateActor(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  return actor&&key&&readers.has(actor.role)?{actor,key}:null;
}
async function rest(key:string,path:string,init:RequestInit={}){
  const response=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...headers(key),...(init.headers||{})},cache:"no-store"});
  if(!response.ok)throw new Error(await response.text());
  return response.status===204?null:response.json();
}
async function audit(key:string,actorId:string,action:string,targetType:string,targetId:string,before?:unknown,after?:unknown){
  await rest(key,"audit_logs",{method:"POST",body:JSON.stringify({actor_employee_id:actorId,action,legal_entity_id:entity,module:"projects",target_type:targetType,target_id:targetId,result:"success",metadata:{before:before||null,after:after||null}})});
}

export async function GET(){
  const c=await context();
  if(!c)return NextResponse.json({error:"Sem acesso a Projectos e Tarefas."},{status:403});
  const sources:[string,string][]=[
    ["projects","projects?select=*&order=updated_at.desc&limit=300"],
    ["tasks","tasks?select=*&order=due_at.asc.nullslast&limit=800"],
    ["members","project_members?select=*&limit=600"],
    ["milestones","project_milestones?select=*&order=due_date.asc.nullslast&limit=500"],
    ["dependencies","task_dependencies?select=*&limit=800"],
    ["updates","project_updates?select=*&order=created_at.desc&limit=500"],
    ["employees","employees?select=id,name,employee_code,status,department_id&limit=500"],
    ["platforms","platforms?select=id,name,slug&limit=20"],
    ["departments","departments?select=id,name,code&limit=100"],
  ];
  const pairs=await Promise.all(sources.map(async([name,path])=>{try{return [name,await rest(c.key,path)]}catch{return [name,[]]}}));
  return NextResponse.json({data:Object.fromEntries(pairs)},{headers:{"Cache-Control":"private, no-store"}});
}

export async function POST(req:NextRequest){
  const c=await context();
  if(!c||!writers.has(c.actor.role))return NextResponse.json({error:"Sem permissão para gerir projectos."},{status:403});
  const body=await req.json() as {resource?:string;record?:Record<string,unknown>};
  if(!body.resource||!body.record)return NextResponse.json({error:"Registo inválido."},{status:400});
  try{
    let table="",record={...body.record} as Record<string,unknown>;
    if(body.resource==="project"){
      table="projects";record={...record,legal_entity_id:entity,platform_id:platforms[String(record.platform_slug)]||null,created_by:c.actor.employee_id};delete record.platform_slug;
    }else if(body.resource==="task"){
      if(record.assigned_to){const recipient=(await rest(c.key,`employees?id=eq.${encodeURIComponent(String(record.assigned_to))}&status=eq.active&select=id`))?.[0];if(!recipient)return NextResponse.json({error:"O destinatário não está activo ou não existe."},{status:400})}
      table="tasks";record={...record,legal_entity_id:entity,platform_id:platforms[String(record.platform_slug)]||null,assigned_by:c.actor.employee_id,created_by:c.actor.employee_id};delete record.platform_slug;
    }else if(body.resource==="member")table="project_members";
    else if(body.resource==="milestone")table="project_milestones",record={...record,created_by:c.actor.employee_id};
    else if(body.resource==="dependency")table="task_dependencies",record={...record,created_by:c.actor.employee_id};
    else if(body.resource==="update")table="project_updates",record={...record,created_by:c.actor.employee_id};
    else return NextResponse.json({error:"Tipo de registo inválido."},{status:400});
    const created=(await rest(c.key,table,{method:"POST",body:JSON.stringify(record)}))?.[0];
    if(body.resource==="task"&&record.assigned_to)await rest(c.key,"notifications",{method:"POST",body:JSON.stringify([{employee_id:record.assigned_to,type:"task_assigned",title:"Nova tarefa atribuída",body:String(record.title||"Tarefa"),target_url:"/minhas-tarefas",priority:String(record.priority||"normal"),source_type:"task",source_id:created.id}])});
    await audit(c.key,c.actor.employee_id,`${body.resource}_created`,body.resource,created.id,null,created);
    return NextResponse.json({record:created},{status:201});
  }catch(error){
    return NextResponse.json({error:"Não foi possível guardar. Verifique prazos, duplicações e dependências."},{status:409});
  }
}

export async function PATCH(req:NextRequest){
  const c=await context();
  if(!c||!writers.has(c.actor.role))return NextResponse.json({error:"Sem permissão."},{status:403});
  const body=await req.json() as {resource?:"project"|"task"|"milestone";id?:string;action?:string;progress?:number;message?:string};
  if(!body.resource||!body.id||!body.action)return NextResponse.json({error:"Ação inválida."},{status:400});
  const tables={project:"projects",task:"tasks",milestone:"project_milestones"},table=tables[body.resource];
  try{
    const current=(await rest(c.key,`${table}?id=eq.${encodeURIComponent(body.id)}&select=*`))?.[0];
    if(!current)return NextResponse.json({error:"Registo não encontrado."},{status:404});
    let patch:Record<string,unknown>={};
    if(body.resource==="project"){
      const statuses:Record<string,string>={start:"active",hold:"on_hold",resume:"active",complete:"completed",cancel:"cancelled"};
      if(!statuses[body.action])return NextResponse.json({error:"Transição inválida."},{status:400});
      if(["completed","cancelled"].includes(String(current.status)))return NextResponse.json({error:"O projecto já está encerrado."},{status:409});
      if(body.action==="complete"){
        const open=await rest(c.key,`tasks?project_id=eq.${body.id}&status=not.in.(completed,cancelled)&select=id&limit=1`);
        if(open?.length)return NextResponse.json({error:"Conclua ou cancele todas as tarefas antes de encerrar o projecto."},{status:409});
      }
      patch={status:statuses[body.action]};
    }else if(body.resource==="task"){
      const statuses:Record<string,string>={start:"in_progress",block:"blocked",resume:"in_progress",complete:"completed",cancel:"cancelled"};
      if(body.action==="progress")patch={progress:Math.max(0,Math.min(100,Number(body.progress||0)))};
      else{
        if(!statuses[body.action])return NextResponse.json({error:"Transição inválida."},{status:400});
        if(body.action==="start"||body.action==="complete"){
          const dependencies=await rest(c.key,`task_dependencies?task_id=eq.${body.id}&select=depends_on_task_id`);
          if(dependencies?.length){const ids=dependencies.map((d:Record<string,unknown>)=>d.depends_on_task_id).join(",");const pending=await rest(c.key,`tasks?id=in.(${ids})&status=not.eq.completed&select=id&limit=1`);if(pending?.length)return NextResponse.json({error:"Existem dependências ainda não concluídas."},{status:409});}
        }
        patch={status:statuses[body.action]};
      }
    }else{
      const statuses:Record<string,string>={start:"in_progress",complete:"completed",miss:"missed",cancel:"cancelled"};
      if(!statuses[body.action])return NextResponse.json({error:"Transição inválida."},{status:400});
      patch={status:statuses[body.action],...(body.action==="complete"?{completed_at:new Date().toISOString()}: {})};
    }
    const updated=(await rest(c.key,`${table}?id=eq.${encodeURIComponent(body.id)}`,{method:"PATCH",body:JSON.stringify(patch)}))?.[0];
    if(body.message&&body.resource!=="milestone")await rest(c.key,"project_updates",{method:"POST",body:JSON.stringify({project_id:body.resource==="project"?body.id:current.project_id,task_id:body.resource==="task"?body.id:null,update_type:body.action==="block"?"blocker":"progress",message:body.message,progress:body.progress??null,created_by:c.actor.employee_id})});
    await audit(c.key,c.actor.employee_id,`${body.resource}_${body.action}`,body.resource,body.id,current,updated);
    return NextResponse.json({record:updated});
  }catch{
    return NextResponse.json({error:"A operação foi bloqueada pelo estado atual."},{status:409});
  }
}
