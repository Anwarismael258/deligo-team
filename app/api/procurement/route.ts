import { NextRequest, NextResponse } from "next/server";
import { corporateActor, supabaseUrl } from "@/lib/hq-server";
const entity="10000000-0000-0000-0000-000000000001";
const readRoles=new Set(["SUPER_ADMIN","PROCUREMENT","FINANCE","ACCOUNTING"]),writeRoles=new Set(["SUPER_ADMIN","PROCUREMENT"]);
const resources=["suppliers","purchase_requests","purchase_request_items","supplier_quotes","purchase_orders","goods_receipts","procurement_invoices","procurement_history","budgets","departments","approval_requests"];
const headers=(key:string)=>({apikey:key,Authorization:`Bearer ${key}`,"Accept-Profile":"hq","Content-Profile":"hq","Content-Type":"application/json",Prefer:"return=representation"});
async function ctx(){const actor=await corporateActor(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;return actor&&key&&readRoles.has(actor.role)?{actor,key}:null}
async function rest(key:string,path:string,init:RequestInit={}){const response=await fetch(`${supabaseUrl()}/rest/v1/${path}`,{...init,headers:{...headers(key),...(init.headers||{})},cache:"no-store"});if(!response.ok)throw new Error(await response.text());return response.status===204?null:response.json()}

export async function GET(){const c=await ctx();if(!c)return NextResponse.json({error:"Acesso reservado a Compras."},{status:403});const rows=await Promise.all(resources.map(async name=>{try{return[name,await rest(c.key,`${name}?select=*&limit=500`)] as const}catch{return[name,[]] as const}}));return NextResponse.json({data:Object.fromEntries(rows)},{headers:{"Cache-Control":"private, no-store"}})}

export async function POST(request:NextRequest){
  const c=await ctx();if(!c||!writeRoles.has(c.actor.role))return NextResponse.json({error:"Sem permissão para gerir compras."},{status:403});
  const body=await request.json() as {resource?:string;record?:Record<string,unknown>;items?:Array<Record<string,unknown>>};
  try{
    if(body.resource==="purchase_request"&&body.record){
      const approval=(await rest(c.key,"approval_requests",{method:"POST",body:JSON.stringify({legal_entity_id:entity,request_type:"purchase",target_type:"purchase_request",title:`Pedido de compra: ${body.record.justification}`,amount:body.record.estimated_amount,currency:"MZN",status:"submitted",required_approvals:1,requested_by:c.actor.employee_id,submitted_at:new Date().toISOString()})}))?.[0];
      const purchase=(await rest(c.key,"purchase_requests",{method:"POST",body:JSON.stringify({...body.record,legal_entity_id:entity,requested_by:c.actor.employee_id,approval_request_id:approval.id,status:"pending_approval"})}))?.[0];
      await rest(c.key,`approval_requests?id=eq.${approval.id}`,{method:"PATCH",body:JSON.stringify({target_id:purchase.id})});
      if(body.items?.length)await rest(c.key,"purchase_request_items",{method:"POST",body:JSON.stringify(body.items.map(item=>({...item,purchase_request_id:purchase.id})))});
      await rest(c.key,"procurement_history",{method:"POST",body:JSON.stringify({purchase_request_id:purchase.id,event_type:"request_submitted",description:"Pedido submetido para aprovação",actor_employee_id:c.actor.employee_id})});
      return NextResponse.json({record:purchase},{status:201});
    }
    if(!body.resource||!body.record||!["suppliers","supplier_quotes","purchase_orders","goods_receipts","procurement_invoices"].includes(body.resource))return NextResponse.json({error:"Operação de compra inválida."},{status:400});
    const record={...body.record} as Record<string,unknown>;
    if(body.resource==="suppliers")record.legal_entity_id=entity;
    if(body.resource==="purchase_orders")record.created_by=c.actor.employee_id;
    if(body.resource==="goods_receipts")record.received_by=c.actor.employee_id;
    if(body.resource==="procurement_invoices"){
      const payment=(await rest(c.key,"payment_requests",{method:"POST",body:JSON.stringify({legal_entity_id:entity,payee:record.payee||"Fornecedor",description:`Fatura ${record.invoice_number}`,amount:record.amount,currency:"MZN",due_at:record.due_on,status:"pending",requested_by:c.actor.employee_id})}))?.[0];
      record.payment_request_id=payment.id;delete record.payee;
    }
    const created=(await rest(c.key,body.resource,{method:"POST",body:JSON.stringify(record)}))?.[0];
    return NextResponse.json({record:created},{status:201});
  }catch{return NextResponse.json({error:"A etapa anterior, a aprovação ou os dados obrigatórios ainda não permitem avançar."},{status:409})}
}

export async function PATCH(request:NextRequest){
  const c=await ctx();if(!c)return NextResponse.json({error:"Sem acesso."},{status:403});
  const body=await request.json() as {action?:string;purchaseRequestId?:string;quoteId?:string};
  try{
    if(body.action==="approve"){
      if(!["SUPER_ADMIN","FINANCE"].includes(c.actor.role)||!body.purchaseRequestId)return NextResponse.json({error:"Aprovação financeira necessária."},{status:403});
      const purchase=(await rest(c.key,`purchase_requests?id=eq.${body.purchaseRequestId}&select=*`))?.[0];
      if(!purchase||purchase.requested_by===c.actor.employee_id)return NextResponse.json({error:"O solicitante não pode aprovar a própria compra."},{status:409});
      await rest(c.key,"approval_decisions",{method:"POST",body:JSON.stringify({request_id:purchase.approval_request_id,approver_id:c.actor.employee_id,decision:"approved"})});
      await rest(c.key,`approval_requests?id=eq.${purchase.approval_request_id}`,{method:"PATCH",body:JSON.stringify({status:"approved",completed_at:new Date().toISOString()})});
      await rest(c.key,`purchase_requests?id=eq.${purchase.id}`,{method:"PATCH",body:JSON.stringify({status:"approved",updated_at:new Date().toISOString()})});
      await rest(c.key,"procurement_history",{method:"POST",body:JSON.stringify({purchase_request_id:purchase.id,event_type:"approved",description:"Pedido aprovado",actor_employee_id:c.actor.employee_id})});
      return NextResponse.json({ok:true});
    }
    if(body.action==="select_quote"&&writeRoles.has(c.actor.role)&&body.quoteId&&body.purchaseRequestId){
      const quote=(await rest(c.key,`supplier_quotes?id=eq.${body.quoteId}&select=*`))?.[0];
      await rest(c.key,`supplier_quotes?purchase_request_id=eq.${body.purchaseRequestId}`,{method:"PATCH",body:JSON.stringify({is_selected:false})});
      await rest(c.key,`supplier_quotes?id=eq.${body.quoteId}`,{method:"PATCH",body:JSON.stringify({is_selected:true})});
      await rest(c.key,`purchase_requests?id=eq.${body.purchaseRequestId}`,{method:"PATCH",body:JSON.stringify({status:"sourcing",selected_supplier_id:quote.supplier_id})});
      return NextResponse.json({ok:true});
    }
    return NextResponse.json({error:"Ação inválida."},{status:400});
  }catch{return NextResponse.json({error:"Não foi possível avançar esta compra."},{status:409})}
}
