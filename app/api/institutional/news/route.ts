import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, supabaseUrl } from "@/lib/hq-server";

type News = Record<string, unknown> & { id: string; author_id?: string | null; status: string; title: string };
const baseHeaders = (key: string) => ({ apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", Prefer: "return=representation" });
const slugify = (value: string) => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 140);
async function rest(key: string, path: string, init: RequestInit = {}) { const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, { ...init, headers: { ...baseHeaders(key), ...(init.headers || {}) }, cache: "no-store" }); if (!response.ok) throw new Error(await response.text()); return response.status === 204 ? null : response.json(); }
async function audit(key:string, actor:string, action:string, id:string, before:unknown, after:unknown) { await fetch(`${supabaseUrl()}/rest/v1/audit_logs`, { method:"POST", headers:{...baseHeaders(key),"Accept-Profile":"hq","Content-Profile":"hq"}, body:JSON.stringify({actor_employee_id:actor,action,module:"institutional_cms",target_type:"news",target_id:id,result:"success",before_state:before,after_state:after}) }); }
async function notify(key:string, employeeId:string, type:string, title:string, body:string, id:string) { await fetch(`${supabaseUrl()}/rest/v1/notifications`, { method:"POST", headers:{...baseHeaders(key),"Accept-Profile":"hq","Content-Profile":"hq"}, body:JSON.stringify({employee_id:employeeId,type,title,body,target_url:"/marketing/conteudos",priority:"normal",source_type:"news",source_id:id,dedupe_key:`${type}:${id}:${employeeId}`}) }); }
async function admins(key:string) { const people=await rest(key,"employees?select=id,employee_roles(roles(code))&status=eq.active&limit=500",{headers:{"Accept-Profile":"hq"}}) as Array<{id:string;employee_roles?:Array<{roles?:{code?:string}}>} >; return people.filter(p=>p.employee_roles?.some(x=>["SUPER_ADMIN","FINANCE"].includes(String(x.roles?.code)))).map(p=>p.id); }

export async function GET(request:NextRequest) {
 const auth=await requireCorporatePermission("news.view"),key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(!auth||!key)return NextResponse.json({error:"Sem permissão para consultar conteúdos."},{status:403});
 const q=request.nextUrl.searchParams, filters=["select=*&order=updated_at.desc&limit=250"]; for(const field of ["status","platform","category"]){const value=q.get(field);if(value)filters.push(`${field}=eq.${encodeURIComponent(value)}`)} const search=q.get("search");if(search)filters.push(`title=ilike.*${encodeURIComponent(search)}*`);
 const rows=await rest(key,`news?${filters.join("&")}`);return NextResponse.json({news:rows},{headers:{"Cache-Control":"private, no-store"}});
}

export async function POST(request:NextRequest) {
 const auth=await requireCorporatePermission("news.create"),key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(!auth||!key)return NextResponse.json({error:"Sem permissão para criar notícias."},{status:403});
 const body=await request.json() as {record?:Record<string,unknown>}; const record=body.record||{};const title=String(record.title||"").trim(),content=String(record.content||"").trim(),slug=slugify(String(record.slug||title)); if(!title||!content||!slug)return NextResponse.json({error:"Título, conteúdo e slug válido são obrigatórios."},{status:400});
 try { const created=(await rest(key,"news",{method:"POST",body:JSON.stringify({...record,title,content,slug,status:"draft",published:false,author_id:auth.actor.employee_id,author_name:auth.actor.name})}))[0] as News; await audit(key,auth.actor.employee_id,"news.created",created.id,null,created); return NextResponse.json({news:created},{status:201}); } catch { return NextResponse.json({error:"Não foi possível criar. Confirme que o slug é único."},{status:409}); }
}

export async function PATCH(request:NextRequest) {
 const key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(!key)return NextResponse.json({error:"Serviço indisponível."},{status:503}); const body=await request.json() as {id?:string;action?:string;record?:Record<string,unknown>;reason?:string};if(!body.id)return NextResponse.json({error:"Notícia inválida."},{status:400});
 const view=await requireCorporatePermission("news.view");if(!view)return NextResponse.json({error:"Sem sessão autorizada."},{status:403}); const existingRows=await rest(key,`news?id=eq.${encodeURIComponent(body.id)}&select=*`);const current=existingRows[0] as News|undefined;if(!current)return NextResponse.json({error:"Notícia não encontrada."},{status:404});
 const action=body.action||"edit"; const permission:Record<string,string>={edit:"news.edit",submit:"news.review",approve:"news.approve",publish:"news.publish",schedule:"news.schedule",archive:"news.archive",delete:"news.delete"};const required=permission[action];const auth=required?await requireCorporatePermission(required):null;if(!auth)return NextResponse.json({error:"Sem permissão para esta ação."},{status:403});
 if(["edit","submit"].includes(action)&&current.author_id!==auth.actor.employee_id&&!auth.isSuperAdmin&&!auth.permissions.includes("news.approve"))return NextResponse.json({error:"Só pode alterar conteúdos próprios."},{status:403});
 let changes:Record<string,unknown>={};let auditAction=`news.${action}`;
 if(action==="edit"){const r=body.record||{};const title=String(r.title||current.title).trim(),slug=slugify(String(r.slug||title));if(!title||!slug)return NextResponse.json({error:"Título e slug são obrigatórios."},{status:400});changes={...r,title,slug,status:current.status==="archived"?"draft":current.status};}
 if(action==="submit"){if(current.status!=="draft")return NextResponse.json({error:"Apenas rascunhos podem ser enviados para revisão."},{status:409});changes={status:"in_review",published:false};auditAction="news.submitted_for_review";}
 if(action==="approve"){if(current.status!=="in_review")return NextResponse.json({error:"A notícia não está em revisão."},{status:409});changes={approved_at:new Date().toISOString(),approved_by:auth.actor.employee_id};auditAction="news.approved";}
 if(action==="publish"){if(current.status!=="in_review"||!current.approved_at)return NextResponse.json({error:"A notícia precisa de revisão e aprovação antes da publicação."},{status:409});changes={status:"published",published:true,published_at:new Date().toISOString()};auditAction="news.published";}
 if(action==="schedule"){const scheduledAt=body.record?.scheduled_at;if(!scheduledAt||new Date(String(scheduledAt)).getTime()<=Date.now())return NextResponse.json({error:"Defina uma data futura para o agendamento."},{status:400});if(!current.approved_at)return NextResponse.json({error:"A notícia precisa de aprovação antes do agendamento."},{status:409});changes={status:"scheduled",published:false,scheduled_at:scheduledAt};auditAction="news.scheduled";}
 if(action==="archive"){if(!["published","scheduled"].includes(current.status))return NextResponse.json({error:"Apenas notícias publicadas ou agendadas podem ser arquivadas."},{status:409});changes={status:"archived",published:false};auditAction="news.archived";}
 if(action==="delete"){await rest(key,`news?id=eq.${encodeURIComponent(body.id)}`,{method:"DELETE"});await audit(key,auth.actor.employee_id,"news.deleted",body.id,current,null);return NextResponse.json({ok:true});}
 try {const updated=(await rest(key,`news?id=eq.${encodeURIComponent(body.id)}`,{method:"PATCH",body:JSON.stringify(changes)}))[0] as News;await audit(key,auth.actor.employee_id,auditAction,updated.id,current,updated);
  if(action==="submit") for(const id of await admins(key)) await notify(key,id,"news_review","Notícia aguardando revisão",updated.title,updated.id);
  if(["approve","publish"].includes(action)&&updated.author_id) await notify(key,updated.author_id,action==="approve"?"news_approved":"news_published",action==="approve"?"Notícia aprovada":"Notícia publicada",updated.title,updated.id);
  return NextResponse.json({news:updated});
 } catch {return NextResponse.json({error:"Não foi possível guardar. Confirme o slug e o estado editorial."},{status:409});}
}
