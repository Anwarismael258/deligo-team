"use client";
import { useState } from "react";

export function ManualCommunication() {
  const [preview, setPreview] = useState(false);
  const [notice, setNotice] = useState("");
  const [sending, setSending] = useState(false);
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    if (!preview) { setPreview(true); return; }
    if (!window.confirm("Confirmar o envio desta comunicação para os trabalhadores seleccionados?")) return;
    setSending(true);
    const response = await fetch("/api/notifications", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ platform: form.get("platform"), audience: form.get("audience"), title: form.get("title"), body: form.get("body"), channels: ["in_app"] }) });
    const result = await response.json();
    setNotice(response.ok ? `Comunicação criada para ${result.recipientCount} destinatários.` : result.error || "Não foi possível criar a comunicação.");
    setSending(false);
    if (response.ok) { setPreview(false); event.currentTarget.reset(); }
  }
  return <section className="workflowInbox"><div className="workflowInboxHead"><div><span>COMUNICAÇÃO MANUAL</span><h2>Enviar comunicação interna</h2><p>Pré-visualização obrigatória. O envio fica registado e usa apenas destinatários activos.</p></div></div><form className="financeEntryForm" onSubmit={submit}><label><span>Plataforma</span><select name="platform" defaultValue="all"><option value="all">Todas as plataformas</option><option value="deligo">DeliGo</option><option value="sarca">SARCA</option><option value="mestre24">Mestre24</option><option value="comunhao">Comunhão</option></select></label><label><span>Público interno</span><select name="audience" defaultValue="all"><option value="all">Todos os trabalhadores autorizados</option><option value="finance">Finanças</option><option value="hr">Recursos Humanos</option><option value="support">Apoio ao Cliente</option><option value="operations">Operações</option></select></label><label><span>Título</span><input name="title" required maxLength={120} placeholder="Título da comunicação" /></label><label className="institutionalWide"><span>Mensagem</span><textarea name="body" required maxLength={1000} rows={5} placeholder="Escreva a mensagem..." /></label><div className="institutionalActions"><button type="submit" disabled={sending}>{preview ? "Confirmar e enviar" : "Pré-visualizar"}</button>{preview && <button type="button" onClick={() => setPreview(false)}>Editar</button>}</div></form>{notice && <div className="operationalNotice">{notice}</div>}</section>;
}
