import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { handleCentralEmployeePayout } from "./handler.ts";
const db=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return Response.json({error:"Method not allowed"},{status:405});
 const token=(req.headers.get("authorization")||"").replace(/^Bearer /,"");
 if(!token)return Response.json({error:"Unauthorized"},{status:401});
 const {data,error}=await db.auth.getUser(token);
 if(error||!data.user)return Response.json({error:"Unauthorized"},{status:401});
 const body=await req.json().catch(()=>null);
 if(!body||!["central_employee_payout","central_employee_reconcile"].includes(body.action))return Response.json({error:"Invalid action"},{status:400});
 try{return await handleCentralEmployeePayout(body,data.user,db,{baseUrl:Deno.env.get("PAYSUITE_BASE_URL")||"https://paysuite.tech",token:Deno.env.get("PAYSUITE_API_TOKEN")||""})}
 catch{return Response.json({error:"Payout confirmation pending"},{status:503})}
});
