import {NextRequest,NextResponse}from"next/server";
import{corporateActor,hqRpc,supabaseUrl}from"@/lib/hq-server";

const allowed=new Set(["SUPER_ADMIN","TECHNOLOGY"]),entity="10000000-0000-0000-0000-000000000001";
const resources=new Set(["technology_systems","technology_integrations","technology_incidents","technology_backups","technology_changes","technology_credentials","technology_domains","technology_certificates","technology_releases"]);
const h=(key:string)=>({apikey:key,Authorization:`Bearer ${key}`,"Accept-Profile":"hq","Content-Profile":"hq","Content-Type":"application/json",Prefer:"return=representation"});
async function ctx(){const actor=await corporateActor(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;return actor&&key&&allowed.has(actor.role)?{actor,key}:null}
async function rest(key:string,path:string,init:RequestInit={}){const r=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...h(key),...(init.headers||{})},cache:"no-store"});if(!r.ok)throw new Error(await r.text());return r.status===204?null:r.json()}
function safe(row:Record<string,unknown>){const{secret_reference,storage_reference,...visible}=row;return{...visible,has_secret_reference:Boolean(secret_reference),has_storage_reference:Boolean(storage_reference)}}
async function audit(key:string,actorId:string,action:string,targetType:string,targetId:string,before?:unknown,after?:unknown){await rest(key,"audit_logs",{method:"POST",body:JSON.stringify({actor_employee_id:actorId,action,legal_entity_id:entity,module:"technology",target_type:targetType,target_id:targetId,result:"success",metadata:{before:before||null,after:after||null}})})}

export async function GET(){
 const c=await ctx();if(!c)return NextResponse.json({error:"Acesso reservado a Tecnologia."},{status:403});
 const sources:[string,string][]=[
  ["technology_systems","technology_systems?select=*&order=name&limit=500"],
  ["technology_integrations","technology_integrations?select=id,legal_entity_id,platform_id,name,provider,integration_type,status,health_endpoint,last_success_at,last_failure_at,owner_employee_id,created_at&order=name&limit=500"],
  ["technology_incidents","technology_incidents?select=*&order=started_at.desc&limit=500"],
  ["technology_backups","technology_backups?select=id,legal_entity_id,system_id,backup_type,started_at,completed_at,status,size_bytes,restore_tested_at,retention_until,created_at&order=started_at.desc&limit=500"],
  ["technology_changes","technology_changes?select=*&order=created_at.desc&limit=500"],
  ["technology_credentials","technology_credentials?select=id,legal_entity_id,system_id,integration_id,name,credential_type,provider,status,last_rotated_at,expires_at,owner_employee_id,created_at,updated_at&order=name&limit=500"],
  ["technology_domains","technology_domains?select=*&order=expires_on.asc.nullslast&limit=500"],
  ["technology_certificates","technology_certificates?select=*&order=valid_until.asc&limit=500"],
  ["technology_releases","technology_releases?select=*&order=created_at.desc&limit=500"],
  ["technology_failure_history","technology_failure_history?select=*&order=occurred_at.desc&limit=500"],
  ["technology_incident_reports","technology_incident_reports?select=*&order=created_at.desc&limit=500"],
  ["platforms","platforms?select=id,name,slug&limit=20"],
  ["employees","employees?select=id,name,employee_code,status,department_id&status=eq.active&limit=500"],
 ];
 const pairs=await Promise.all(sources.map(async([name,path])=>{try{return[name,await rest(c.key,path)]}catch{return[name,[]]}}));const data=Object.fromEntries(pairs)as Record<string,unknown[]>;
 try{const technologyDepartment=(await rest(c.key,"departments?code=eq.TECHNOLOGY&select=id"))?.[0];data.internal_requests=technologyDepartment?await rest(c.key,`internal_requests?target_department_id=eq.${technologyDepartment.id}&select=id,request_number,requester_id,assigned_to,category,subject,priority,status,due_at,created_at,updated_at&order=updated_at.desc&limit=100`):[]}catch{data.internal_requests=[]}
 return NextResponse.json({data},{headers:{"Cache-Control":"private, no-store"}});
}

export async function POST(req:NextRequest){
 const c=await ctx();if(!c)return NextResponse.json({error:"Sem permissão de Tecnologia."},{status:403});const b=await req.json()as{resource?:string;record?:Record<string,unknown>};if(!b.resource||!b.record||!resources.has(b.resource))return NextResponse.json({error:"Registo técnico inválido."},{status:400});
 try{const record={...b.record}as Record<string,unknown>;if(!["technology_certificates"].includes(b.resource))record.legal_entity_id=entity;if(["technology_systems","technology_integrations","technology_incidents","technology_credentials","technology_domains","technology_certificates"].includes(b.resource))record.owner_employee_id=c.actor.employee_id;if(b.resource==="technology_changes")record.requested_by=c.actor.employee_id;if(b.resource==="technology_releases")record.deployed_by=c.actor.employee_id;const created=(await rest(c.key,b.resource,{method:"POST",body:JSON.stringify(record)}))?.[0],visible=safe(created);const workflow=b.resource==="technology_incidents"?await hqRpc("hq_start_technical_incident_workflow_v1",{p_incident_id:created.id,p_actor_employee_id:c.actor.employee_id}):null;await audit(c.key,c.actor.employee_id,"created",b.resource,created.id,null,visible);return NextResponse.json({record:visible,workflow},{status:201})}catch{return NextResponse.json({error:"Não foi possível guardar. Credenciais devem usar apenas referências vault://, secret://, env:// ou supabase-vault://."},{status:409})}
}

export async function PATCH(req:NextRequest){
 const c=await ctx();if(!c)return NextResponse.json({error:"Sem permissão de Tecnologia."},{status:403});const b=await req.json()as{resource?:string;id?:string;action?:string;resolution?:string;secretReference?:string};if(!b.resource||!b.id||!b.action||!resources.has(b.resource))return NextResponse.json({error:"Ação técnica inválida."},{status:400});
 try{const current=(await rest(c.key,`${b.resource}?id=eq.${encodeURIComponent(b.id)}&select=*`))?.[0];if(!current)return NextResponse.json({error:"Registo não encontrado."},{status:404});let patch:Record<string,unknown>={};
  if(b.resource==="technology_systems"){const s:Record<string,string>={operational:"operational",degrade:"degraded",maintenance:"maintenance",outage:"outage",retire:"retired"};if(!s[b.action])throw new Error();patch={status:s[b.action],last_checked_at:new Date().toISOString()}}
  else if(b.resource==="technology_integrations"){const s:Record<string,string>={activate:"active",degrade:"degraded",disable:"disabled"};if(!s[b.action])throw new Error();patch={status:s[b.action],...(b.action==="activate"?{last_success_at:new Date().toISOString()}:{last_failure_at:new Date().toISOString()})}}
  else if(b.resource==="technology_incidents"){const s:Record<string,string>={investigate:"investigating",mitigate:"mitigated",resolve:"resolved",close:"closed"};if(!s[b.action])throw new Error();if(b.action==="resolve"&&!b.resolution?.trim())return NextResponse.json({error:"Indique a resolução técnica."},{status:400});patch={status:s[b.action],...(b.resolution?{resolution:b.resolution}:{}) ,...(["resolve","close"].includes(b.action)?{resolved_at:new Date().toISOString()}:{})}}
  else if(b.resource==="technology_backups"){if(b.action==="success")patch={status:"succeeded",completed_at:new Date().toISOString()};else if(b.action==="fail")patch={status:"failed",completed_at:new Date().toISOString()};else if(b.action==="restore_test")patch={restore_tested_at:new Date().toISOString()};else throw new Error()}
  else if(b.resource==="technology_changes"){const s:Record<string,string>={approve:"approved",start:"in_progress",complete:"completed",rollback:"rolled_back",cancel:"cancelled"};if(!s[b.action])throw new Error();if(b.action==="approve"&&current.requested_by===c.actor.employee_id&&c.actor.role!=="SUPER_ADMIN")return NextResponse.json({error:"Quem solicita não pode aprovar a própria alteração."},{status:409});patch={status:s[b.action],...(b.action==="approve"?{approved_by:c.actor.employee_id}:{}),...(["complete","rollback"].includes(b.action)?{completed_at:new Date().toISOString()}:{})}}
  else if(b.resource==="technology_releases"){const s:Record<string,string>={start:"deploying",success:"succeeded",fail:"failed",rollback:"rolled_back"};if(!s[b.action])throw new Error();patch={status:s[b.action],...(b.action==="start"?{started_at:new Date().toISOString()}:{completed_at:new Date().toISOString()})}}
  else if(b.resource==="technology_credentials"){if(b.action==="revoke")patch={status:"revoked"};else if(b.action==="rotate"&&b.secretReference)patch={status:"active",secret_reference:b.secretReference,last_rotated_at:new Date().toISOString()};else throw new Error()}
  else if(b.resource==="technology_domains"){if(b.action==="suspend")patch={status:"suspended"};else if(b.action==="activate")patch={status:"active"};else throw new Error()}
  else if(b.resource==="technology_certificates"){if(b.action!=="revoke")throw new Error();patch={status:"revoked"}}
  const updated=(await rest(c.key,`${b.resource}?id=eq.${encodeURIComponent(b.id)}`,{method:"PATCH",body:JSON.stringify(patch)}))?.[0];if(b.resource==="technology_incidents")await rest(c.key,"technology_failure_history",{method:"POST",body:JSON.stringify({incident_id:b.id,system_id:current.system_id||null,event_type:b.action==="resolve"?"resolution":b.action==="mitigate"?"mitigation":"status_change",summary:b.resolution||`Estado alterado para ${String(updated.status)}`,previous_status:current.status,final_status:updated.status,created_by:c.actor.employee_id})});const before=safe(current),after=safe(updated);await audit(c.key,c.actor.employee_id,b.action,b.resource,b.id,before,after);return NextResponse.json({record:after})
 }catch{return NextResponse.json({error:"A operação foi bloqueada pelo estado ou pelos requisitos de segurança."},{status:409})}
}
