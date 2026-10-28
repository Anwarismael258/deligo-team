import { NextRequest, NextResponse } from "next/server";
import { hqRpc, requireCorporatePermission, supabaseUrl } from "@/lib/hq-server";
const resources = ["hr_contracts","hr_documents","hr_attendance","hr_leave_requests","hr_payroll_records","hr_employee_events"] as const;
const writableFields: Record<string, readonly string[]> = {
  hr_contracts: ["employee_id", "contract_type", "starts_on", "ends_on", "status", "document_path"],
  hr_documents: ["employee_id", "document_type", "storage_path", "expires_on"],
  hr_attendance: ["employee_id", "work_date", "shift_code", "checked_in_at", "checked_out_at", "status", "minutes_late"],
  hr_leave_requests: ["employee_id", "leave_type", "starts_on", "ends_on", "status"],
};
const headers = (key:string) => ({ apikey:key, Authorization:`Bearer ${key}`, "Accept-Profile":"hq", "Content-Profile":"hq", "Content-Type":"application/json", Prefer:"return=representation" });

function pickWritableRecord(resource: string, input: Record<string, unknown>) {
  const fields = writableFields[resource] || [];
  return Object.fromEntries(fields.filter((field) => Object.prototype.hasOwnProperty.call(input, field)).map((field) => [field, input[field]]));
}

export async function GET() {
  const authorization=await requireCorporatePermission("hr.viewEmployees"),actor=authorization?.actor;
  if(!actor) return NextResponse.json({error:"Sem permissão para consultar RH."},{status:403});
  const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!key) return NextResponse.json({error:"Serviço de RH indisponível."},{status:503});
  const canViewSalary=authorization.permissions.includes("hr.viewSalary")||authorization.isSuperAdmin;
  const results=await Promise.all(resources.map(async resource=>{if(resource==="hr_payroll_records"&&!canViewSalary)return[resource,[]]as const;const response=await fetch(`${supabaseUrl()}/rest/v1/${resource}?select=*&order=${resource==="hr_attendance"?"work_date":"created_at"}.desc&limit=100`,{headers:headers(key),cache:"no-store"});return [resource,response.ok?await response.json():[]] as const;}));
  return NextResponse.json({data:Object.fromEntries(results)},{headers:{"Cache-Control":"private, no-store"}});
}

export async function POST(request:NextRequest) {
  const body=await request.json() as {resource?:string;record?:Record<string,unknown>};
  const permission=body.resource==="hr_payroll_records"?"hr.viewSalary":body.resource==="hr_leave_requests"?"hr.approveLeave":"hr.viewEmployees",authorization=await requireCorporatePermission(permission),actor=authorization?.actor;
  if(!actor) return NextResponse.json({error:"Sem permissão para gerir este registo de RH."},{status:403});
  const key=process.env.SUPABASE_SERVICE_ROLE_KEY; if(!key)return NextResponse.json({error:"Serviço de RH indisponível."},{status:503});
  if(!body.resource||!resources.includes(body.resource as typeof resources[number])||!body.record) return NextResponse.json({error:"Registo de RH inválido."},{status:400});
  if (typeof body.record !== "object" || Array.isArray(body.record)) return NextResponse.json({error:"Registo de RH inválido."},{status:400});
  const safeRecord = writableFields[body.resource] ? pickWritableRecord(body.resource, body.record) : body.record;
  if (Object.keys(safeRecord).length === 0) return NextResponse.json({error:"Nenhum campo permitido para este registo de RH."},{status:400});
  let record:Record<string,unknown>;
  if(body.resource==="hr_payroll_records"||body.resource==="hr_employee_events") record=await hqRpc("hq_create_hr_record_v1",{p_resource:body.resource,p_record:body.record}) as Record<string,unknown>;
  else {
    const response=await fetch(`${supabaseUrl()}/rest/v1/${body.resource}`,{method:"POST",headers:headers(key),body:JSON.stringify(safeRecord)});
    if(!response.ok)return NextResponse.json({error:"Não foi possível guardar o registo de RH."},{status:400});
    record=(await response.json())[0] as Record<string,unknown>;
  }
  if(body.resource==="hr_employee_events"&&record.employee_id){
    const notificationResponse=await fetch(`${supabaseUrl()}/rest/v1/notifications`,{method:"POST",headers:headers(key),body:JSON.stringify({employee_id:record.employee_id,type:"hr_lifecycle_event",title:`Novo registo laboral: ${String(record.title)}`,body:`Foi criado um registo de ${String(record.event_type)} no seu ciclo laboral.`,target_url:"/recursos-humanos",priority:"normal",origin_department_id:null,responsible_employee_id:record.employee_id,source_type:"hr_employee_event",source_id:record.id,dedupe_key:`hr-event:${record.id}`})});
    const notification=notificationResponse.ok?(await notificationResponse.json())[0]:null;
    if(notification?.id) await fetch(`${supabaseUrl()}/rest/v1/notification_deliveries`,{method:"POST",headers:headers(key),body:JSON.stringify([{notification_id:notification.id,employee_id:record.employee_id,channel:"sms",provider:"moz_esms",template_code:"HR_LIFECYCLE_NOTICE",payload:{title:String(record.title),message:"Tem uma nova comunicação laboral na Central DeliGo Triunfal."},status:"pending"}])});
  }
  return NextResponse.json({record},{status:201});
}
