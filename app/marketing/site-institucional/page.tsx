"use client";

import { FormEvent, useEffect, useState } from "react";

type News = { id: string; title: string; slug: string; summary?: string; status: string; published?: boolean; approved_at?: string | null; created_at?: string };

export default function InstitutionalCmsPage() {
  const [news, setNews] = useState<News[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [notice, setNotice] = useState("");

  const load = async () => {
    const response = await fetch("/api/institutional/news?scope=all", { cache: "no-store" });
    if (response.ok) setNews((await response.json()).news || []);
  };
  useEffect(() => { void load(); }, []);

  const create = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setNotice("A guardar notícia…");
    const form = new FormData(event.currentTarget);
    const response = await fetch("/api/institutional/news", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ record: { title: form.get("title"), summary: form.get("summary"), content: form.get("content"), category: "institucional" }, title: form.get("title"), content: form.get("content") }) });
    const result = await response.json();
    setNotice(response.ok ? "Notícia criada como rascunho." : result.error || "Não foi possível criar a notícia.");
    if (response.ok) { setShowForm(false); await load(); }
  };

  const action = async (id: string, actionName: string) => {
    const response = await fetch("/api/institutional/news", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id, action: actionName }) });
    const result = await response.json(); setNotice(response.ok ? `Ação “${actionName}” concluída.` : result.error || "Ação bloqueada.");
    if (response.ok) await load();
  };

  return <main className="moduleWorkspace">
    <section className="moduleHero"><div><span>SITE INSTITUCIONAL · CMS</span><h1>Conteúdo público da DeliGo Triunfal</h1><p>Marketing gere o conteúdo; o site público recebe apenas publicações aprovadas.</p></div><button onClick={() => setShowForm(!showForm)}>{showForm ? "Fechar" : "Nova notícia"}</button></section>
    {notice && <div className="operationalNotice">{notice}</div>}
    {showForm && <form className="financeEntryForm" onSubmit={create}><label><span>Título</span><input name="title" required /></label><label><span>Resumo público</span><textarea name="summary" required /></label><label><span>Conteúdo</span><textarea name="content" required /></label><button className="primaryAction">Guardar rascunho</button></form>}
    <section className="reportGrid">{news.map(item => <article key={item.id}><strong>{item.title}</strong><span>{item.status} · {item.published ? "visível no site" : item.approved_at ? "aprovada · pronta para publicar" : "interno"}</span><div>{item.status === "draft" && <button onClick={() => void action(item.id, "submit")}>Enviar para revisão</button>}{item.status === "in_review" && !item.approved_at && <button onClick={() => void action(item.id, "approve")}>Aprovar</button>}{item.status === "in_review" && Boolean(item.approved_at) && <button className="primaryAction" onClick={() => void action(item.id, "publish")}>Publicar no site</button>}{["published", "scheduled"].includes(item.status) && <button onClick={() => void action(item.id, "archive")}>Arquivar</button>}</div></article>)}{!news.length && <div className="peopleEmpty">Ainda não existem notícias institucionais.</div>}</section>
    <div className="safeNotice"><b>Separação interna/pública</b><span>Orçamentos, leads, candidatos e dados de aprovação permanecem na Central. O site lê apenas conteúdos publicados.</span></div>
  </main>;
}
