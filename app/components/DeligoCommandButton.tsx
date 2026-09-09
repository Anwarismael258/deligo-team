"use client";

import { useState } from "react";

export type DeligoAdminAction = "block_client"|"unblock_client"|"suspend_restaurant"|"reactivate_restaurant"|"disable_courier"|"reactivate_courier"|"cancel_order"|"resolve_incident"|"approve_kyc"|"reject_kyc";

export function DeligoCommandButton({ action, entityId, label, danger=false }:{action:DeligoAdminAction;entityId:string;label:string;danger?:boolean}) {
  const [open,setOpen]=useState(false),[reason,setReason]=useState(""),[busy,setBusy]=useState(false),[error,setError]=useState("");
  async function confirm(){
    if(reason.trim().length<6){setError("Indique um motivo com pelo menos 6 caracteres.");return}
    setBusy(true);setError("");
    try{
      const response=await fetch("/api/deligo/admin-command",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({action,entityId,reason:reason.trim(),sessionId:sessionStorage.getItem("hq_session_id")})});
      const payload=await response.json();
      if(!response.ok)throw new Error(payload.error||"A decisão não foi aplicada.");
      setOpen(false);window.location.reload();
    }catch(value){setError(value instanceof Error?value.message:"A decisão não foi aplicada.")}finally{setBusy(false)}
  }
  return <>
    <button className={danger?"deligo-command danger":"deligo-command"} onClick={()=>setOpen(true)}>{label}</button>
    {open&&<div className="deligo-confirm-backdrop" role="dialog" aria-modal="true" aria-label={`Confirmar ${label}`}>
      <div className="deligo-confirm-card"><strong>Confirmar ação crítica</strong><p>{label}</p><label>Motivo obrigatório<textarea value={reason} onChange={event=>setReason(event.target.value)} minLength={6} placeholder="Explique a decisão administrativa" autoFocus/></label>{error&&<p className="deligo-command-error">{error}</p>}<div><button onClick={()=>setOpen(false)} disabled={busy}>Voltar</button><button className={danger?"danger":""} onClick={confirm} disabled={busy}>{busy?"A aplicar…":"Confirmar"}</button></div></div>
    </div>}
  </>;
}
