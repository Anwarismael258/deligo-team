import {NextRequest,NextResponse} from "next/server";
import {corporateAuthorization,hqRpc,stagingRest} from "@/lib/hq-server";

export const dynamic="force-dynamic";
const profile={"Accept-Profile":"hq","Content-Profile":"hq"};

async function processContext(id:string){
  const authorization=await corporateAuthorization();
  if(!authorization)return null;
  const rows=await stagingRest(`workflow_cases?id=eq.${encodeURIComponent(id)}&select=id,case_number,title,platform_id,origin_department_id,current_department_id,created_by,assigned_to,status`,{headers:profile});
  const process=Array.isArray(rows)?rows[0]:null;
  if(!process)return null;
  if(!authorization.isSuperAdmin&&process.platform_id&&!authorization.platformIds.includes(process.platform_id))return null;
  return{authorization,process};
}

export async function GET(_request:NextRequest,{params}:{params:Promise<{id:string}>}){
  const{id}=await params,current=await processContext(id);
  if(!current)return NextResponse.json({error:"Processo não encontrado ou fora do seu âmbito."},{status:404});
  const[events,comments,employees]=await Promise.all([
    stagingRest(`process_events?workflow_case_id=eq.${id}&select=*,actor:employees!process_events_actor_employee_id_fkey(id,name,employee_code),department:departments(id,name,code)&order=occurred_at.asc&limit=1000`,{headers:profile}),
    stagingRest(`process_comments?workflow_case_id=eq.${id}&select=*,author:employees!process_comments_author_employee_id_fkey(id,name,employee_code)&order=created_at.asc&limit=500`,{headers:profile}),
    stagingRest("employees?status=eq.active&select=id,name,employee_code&order=name&limit=500",{headers:profile})
  ]);
  return NextResponse.json({process:current.process,events,comments,employees},{headers:{"Cache-Control":"private, no-store"}});
}

export async function POST(request:NextRequest,{params}:{params:Promise<{id:string}>}){
  const{id}=await params,current=await processContext(id);
  if(!current)return NextResponse.json({error:"Processo não encontrado ou fora do seu âmbito."},{status:404});
  const body=await request.json() as{body?:string;attachmentReference?:string};
  if(!String(body.body||"").trim())return NextResponse.json({error:"Escreva um comentário."},{status:400});
  try{
    const comment=await hqRpc("hq_add_process_comment_v1",{p_case_id:id,p_actor_employee_id:current.authorization.actor.employee_id,p_body:String(body.body).trim(),p_attachment_reference:String(body.attachmentReference||"").trim()||null});
    return NextResponse.json({comment},{status:201});
  }catch{
    return NextResponse.json({error:"Não foi possível guardar o comentário neste processo."},{status:409});
  }
}
