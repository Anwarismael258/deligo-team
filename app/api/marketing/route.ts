import { NextRequest, NextResponse } from "next/server";
import { corporateActor, supabaseUrl } from "@/lib/hq-server";

const entity = "10000000-0000-0000-0000-000000000001";
const platformIds: Record<string,string> = { deligo:"20000000-0000-0000-0000-000000000001", comunhao:"20000000-0000-0000-0000-000000000002", taomoz:"20000000-0000-0000-0000-000000000003", sarca:"20000000-0000-0000-0000-000000000004" };
const readRoles = new Set(["SUPER_ADMIN","MARKETING","FINANCE","OPERATIONS","SUPERVISOR"]);
const writeRoles = new Set(["SUPER_ADMIN","MARKETING"]);
const resources = ["marketing_campaigns","campaign_platforms","marketing_channels","marketing_content_calendar","marketing_promotions","marketing_creatives","marketing_leads","marketing_metrics","marketing_history","platforms","approval_requests"];
const headers=(key:string)=>({apikey:key,Authorization:`Bearer ${key}`,"Accept-Profile":"hq","Content-Profile":"hq","Content-Type":"application/json",Prefer:"return=representation"});
async function context(){const actor=await corporateActor(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;return actor&&key&&readRoles.has(actor.role)?{actor,key}:null}
async function rest(key:string,path:string,init:RequestInit={}){const response=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...headers(key),...(init.headers||{})},cache:"no-store"});if(!response.ok)throw new Error(await response.text());return response.status===204?null:response.json()}
async function history(key:string,campaignId:string,eventType:string,description:string,actorId:string,metadata:Record<string,unknown>={}){await rest(key,"marketing_history",{method:"POST",body:JSON.stringify({campaign_id:campaignId,event_type:eventType,description,actor_employee_id:actorId,metadata})})}

export async function GET(){
  const c=await context();if(!c)return NextResponse.json({error:"Acesso reservado a Marketing e gestão autorizada."},{status:403});
  const rows=await Promise.all(resources.map(async name=>{try{const order=["marketing_campaigns","marketing_history"].includes(name)?"&order=created_at.desc":"";return[name,await rest(c.key,`${name}?select=*&limit=500${order}`)] as const}catch{return[name,[]] as const}}));
  const data=Object.fromEntries(rows) as Record<string,Array<Record<string,unknown>>>;
  const reports=Object.values(platformIds).map(platformId=>{const platform=data.platforms?.find(p=>p.id===platformId);const metrics=(data.marketing_metrics||[]).filter(m=>m.platform_id===platformId);const leads=(data.marketing_leads||[]).filter(l=>l.platform_id===platformId);return {platform_id:platformId,platform:String(platform?.name||"Plataforma"),impressions:metrics.reduce((n,m)=>n+Number(m.impressions||0),0),clicks:metrics.reduce((n,m)=>n+Number(m.clicks||0),0),leads:Math.max(leads.length,metrics.reduce((n,m)=>n+Number(m.leads||0),0)),conversions:Math.max(leads.filter(l=>l.status==="converted").length,metrics.reduce((n,m)=>n+Number(m.conversions||0),0)),spend:metrics.reduce((n,m)=>n+Number(m.spend||0),0)} });
  return NextResponse.json({data,reports},{headers:{"Cache-Control":"private, no-store"}});
}

export async function POST(request:NextRequest){
  const c=await context();if(!c||!writeRoles.has(c.actor.role))return NextResponse.json({error:"Sem permissão para gerir campanhas."},{status:403});
  const body=await request.json() as {resource?:string;record?:Record<string,unknown>;platforms?:string[]};
  try{
    if(body.resource==="campaign"&&body.record){
      const created=(await rest(c.key,"marketing_campaigns",{method:"POST",body:JSON.stringify({...body.record,legal_entity_id:entity,owner_id:c.actor.employee_id,status:"draft"})}))?.[0];
      const ids=(body.platforms||[]).map(slug=>platformIds[slug]).filter(Boolean);
      if(ids.length)await rest(c.key,"campaign_platforms",{method:"POST",body:JSON.stringify(ids.map(platform_id=>({campaign_id:created.id,platform_id})))});
      await history(c.key,created.id,"created","Campanha criada em rascunho",c.actor.employee_id,{platforms:body.platforms||[]});
      return NextResponse.json({record:created},{status:201});
    }
    const mapping:Record<string,string>={channel:"marketing_channels",content:"marketing_content_calendar",promotion:"marketing_promotions",creative:"marketing_creatives",lead:"marketing_leads",metric:"marketing_metrics"};
    const table=body.resource&&mapping[body.resource];if(!table||!body.record)return NextResponse.json({error:"Registo de marketing inválido."},{status:400});
    const record={...body.record} as Record<string,unknown>;
    if(typeof record.platform_slug==="string"){record.platform_id=platformIds[String(record.platform_slug)]||null;delete record.platform_slug}
    if(["marketing_content_calendar","marketing_creatives"].includes(table))record.created_by=c.actor.employee_id;
    const created=(await rest(c.key,table,{method:"POST",body:JSON.stringify(record)}))?.[0];
    if(created?.campaign_id)await history(c.key,created.campaign_id,`${body.resource}_created`,`${body.resource} adicionado à campanha`,c.actor.employee_id);
    return NextResponse.json({record:created},{status:201});
  }catch{return NextResponse.json({error:"Não foi possível guardar. Confirme a campanha e os dados obrigatórios."},{status:409})}
}

export async function PATCH(request:NextRequest){
  const c=await context();if(!c||!writeRoles.has(c.actor.role))return NextResponse.json({error:"Sem permissão para alterar campanhas."},{status:403});
  const body=await request.json() as {campaignId?:string;action?:string;comments?:string};if(!body.campaignId||!body.action)return NextResponse.json({error:"Ação inválida."},{status:400});
  try{
    const campaign=(await rest(c.key,`marketing_campaigns?id=eq.${encodeURIComponent(body.campaignId)}&select=*`))?.[0];if(!campaign)return NextResponse.json({error:"Campanha não encontrada."},{status:404});
    if(body.action==="submit"){
      if(campaign.status!=="draft")return NextResponse.json({error:"Apenas rascunhos podem ser enviados para aprovação."},{status:409});
      const approval=(await rest(c.key,"approval_requests",{method:"POST",body:JSON.stringify({legal_entity_id:entity,request_type:"marketing_publication",target_type:"marketing_campaign",target_id:campaign.id,title:`Publicar campanha: ${campaign.title}`,amount:campaign.budget_amount,currency:campaign.currency,status:"submitted",required_approvals:1,requested_by:c.actor.employee_id,submitted_at:new Date().toISOString()})}))?.[0];
      await rest(c.key,`marketing_campaigns?id=eq.${campaign.id}`,{method:"PATCH",body:JSON.stringify({status:"pending_approval",approval_request_id:approval.id})});
      await history(c.key,campaign.id,"submitted","Campanha enviada para aprovação",c.actor.employee_id);return NextResponse.json({ok:true});
    }
    if(body.action==="approve"){
      if(c.actor.role!=="SUPER_ADMIN")return NextResponse.json({error:"A aprovação final é reservada ao Super Admin."},{status:403});
      if(campaign.status!=="pending_approval"||campaign.owner_id===c.actor.employee_id)return NextResponse.json({error:"O autor não pode aprovar a própria campanha ou a campanha não está pendente."},{status:409});
      await rest(c.key,"approval_decisions",{method:"POST",body:JSON.stringify({request_id:campaign.approval_request_id,approver_id:c.actor.employee_id,decision:"approved",comments:body.comments||null})});
      await rest(c.key,`approval_requests?id=eq.${campaign.approval_request_id}`,{method:"PATCH",body:JSON.stringify({status:"approved",completed_at:new Date().toISOString(),updated_at:new Date().toISOString()})});
      await rest(c.key,`marketing_campaigns?id=eq.${campaign.id}`,{method:"PATCH",body:JSON.stringify({status:"approved"})});
      await history(c.key,campaign.id,"approved","Campanha aprovada para publicação",c.actor.employee_id);return NextResponse.json({ok:true});
    }
    const next:Record<string,string>={publish:"published",pause:"paused",complete:"completed",archive:"archived"};const status=next[body.action];if(!status)return NextResponse.json({error:"Ação inválida."},{status:400});
    await rest(c.key,`marketing_campaigns?id=eq.${campaign.id}`,{method:"PATCH",body:JSON.stringify({status})});
    await history(c.key,campaign.id,status,`Campanha ${status}`,c.actor.employee_id);return NextResponse.json({ok:true});
  }catch{return NextResponse.json({error:"A transição foi bloqueada: confirme a aprovação e o estado atual."},{status:409})}
}
