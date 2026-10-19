"use client";
import { useState } from "react";

export function ManualCommunication() {
  const [preview, setPreview] = useState(false);
  const [notice, setNotice] = useState("");
  const [sending, setSending] = useState(false);
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const title = String(form.get("title") || "").trim();
    const body = String(form.get("body") || "").trim();
    setNotice("");
    if (title.length < 3 || body.length < 3) { setNotice("Preencha um título e uma mensagem com pelo menos 3 caracteres."); return; }
    if (!preview) { setPreview(true); return; }
    if (!window.confirm("Confirmar o envio desta comunicação para os trabalhadores seleccionados?")) return;
    setSending(true);
    const response = await fetch("/api/notifications", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ title, body }) });
    const result = await response.json();
    setNotice(response.ok ? `Comunicação criada para ${result.recipientCount} destinatários.` : result.error || "Não foi possível criar a comunicação.");
    setSending(false);
    if (response.ok) { setPreview(false); event.currentTarget.reset(); }
  }
  return <section className="workflowInbox"><div className="workflowInboxHead"><div><span>INBOX INTERNA</span><h2>Comunicação interna</h2><p>Escreva uma mensagem com título. Todos os trabalhadores activos recebem a notificação.</p></div></div><form className="financeEntryForm" onSubmit={submit}><label><span>Título</span><input name="title" required minLength={3} maxLength={120} placeholder="Título da comunicação" /></label><label className="institutionalWide"><span>Mensagem</span><textarea name="body" required minLength={3} maxLength={1000} rows={5} placeholder="Escreva a mensagem..." /></label><div className="institutionalActions"><button type="submit" disabled={sending}>{preview ? "Confirmar e enviar" : "Pré-visualizar"}</button>{preview && <button type="button" onClick={() => { setPreview(false); setNotice(""); }}>Editar</button>}</div></form>{notice && <div className="operationalNotice">{notice}</div>}</section>;
}
