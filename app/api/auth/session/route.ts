import { NextResponse } from "next/server";
import { corporateActor, supabaseUrl } from "@/lib/hq-server";

export async function GET() {
  const actor=await corporateActor(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!actor||!key)return NextResponse.json({authenticated:false},{status:401});
  const response=await fetch(`${supabaseUrl()}/rest/v1/employees?id=eq.${actor.employee_id}&select=id,employee_code,display_name,corporate_email,phone_e164,job_title,status,joined_on,last_login_at,department_id,manager_id`,{headers:{apikey:key,Authorization:`Bearer ${key}`,"Accept-Profile":"hq"},cache:"no-store"});
  const employee=response.ok?(await response.json())[0]:null;
  return NextResponse.json({authenticated:true,user:{id:actor.employee_id,hq_role:actor.role,name:employee?.display_name||actor.name,employee_code:employee?.employee_code||actor.employee_code,email:employee?.corporate_email||null,phone:employee?.phone_e164||null,job_title:employee?.job_title||null,status:employee?.status||actor.status,joined_on:employee?.joined_on||null,last_login_at:employee?.last_login_at||null,department_id:employee?.department_id||null,manager_id:employee?.manager_id||null}},{headers:{"Cache-Control":"private, no-store"}});
}
