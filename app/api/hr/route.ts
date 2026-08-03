import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, supabaseUrl } from "@/lib/hq-server";
const resources = ["hr_contracts","hr_documents","hr_attendance","hr_leave_requests","hr_payroll_records","hr_employee_events"] as const;
const headers = (key:string) => ({ apikey:key, Authorization:`Bearer ${key}`, "Accept-Profile":"hq", "Content-Profile":"hq", "Content-Type":"application/json", Prefer:"return=representation" });

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
  const response=await fetch(`${supabaseUrl()}/rest/v1/${body.resource}`,{method:"POST",headers:headers(key),body:JSON.stringify(body.record)});
  if(!response.ok)return NextResponse.json({error:"Não foi possível guardar o registo de RH."},{status:400});
  return NextResponse.json({record:(await response.json())[0]},{status:201});
}
