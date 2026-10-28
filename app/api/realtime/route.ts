import {NextRequest,NextResponse} from "next/server";
import {corporateAuthorization,stagingRest} from "@/lib/hq-server";

export const dynamic="force-dynamic";
const inboxRoles=new Set(["SUPER_ADMIN","FINANCE","SUPERVISOR","CUSTOMER_SUPPORT","MARKETING","FIELD"]);

export async function GET(request:NextRequest){
  const authorization=await corporateAuthorization();
  if(!authorization)return NextResponse.json({error:"Sessão necessária."},{status:401});
  if(!inboxRoles.has(authorization.actor.role))return NextResponse.json({error:"Sem acesso ao feed operacional."},{status:403});
  const after=Math.max(0,Number(request.nextUrl.searchParams.get("after")||0));
  const scope=authorization.isSuperAdmin?"":authorization.platformIds.length
    ? `&or=(platform_id.is.null,platform_id.in.(${authorization.platformIds.join(",")}))`
    :"&platform_id=is.null";
  try{
    const events=await stagingRest(`realtime_events?id=gt.${after}&select=id,topic,resource_type,resource_id,event_type,workflow_case_id,platform_id,department_id,created_at&order=id.asc&limit=200${scope}`,{headers:{"Accept-Profile":"hq","Content-Profile":"hq"}});
    const rows=Array.isArray(events)?events:[];
    return NextResponse.json({events:rows,cursor:rows.length?Number(rows[rows.length-1].id):after,checkedAt:new Date().toISOString()},{headers:{"Cache-Control":"private, no-store"}});
  }catch{
    // Realtime is an enhancement. Preserve the dashboard and allow its normal
    // polling cycle to continue when an adapter is temporarily unavailable.
    return NextResponse.json({events:[],cursor:after,checkedAt:new Date().toISOString(),degraded:true},{headers:{"Cache-Control":"private, no-store"}});
  }
}
