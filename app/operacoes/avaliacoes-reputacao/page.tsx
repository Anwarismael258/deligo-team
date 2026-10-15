"use client";
import { useEffect, useMemo, useState } from "react";

type ReputationData = { reviews?: Array<Record<string, unknown>>; ratings?: Array<Record<string, unknown>>; restaurants?: Array<Record<string, unknown>>; metrics?: { total: number; average: number; negative: number; unanswered: number; reports: number } };

export default function ReputationPage() {
  const [platform, setPlatform] = useState("all");
  const [data, setData] = useState<ReputationData>({});
  const [notice, setNotice] = useState("A carregar avaliações autorizadas…");
  useEffect(() => {
    let cancelled = false;
    setNotice("A carregar avaliações autorizadas…");
    fetch(`/api/reputation${platform === "all" ? "" : `?platform=${platform}`}`, { cache: "no-store" }).then(async r => {
      const value = await r.json();
      if (r.status === 401) { window.location.assign(`/login?next=${encodeURIComponent(window.location.pathname)}`); return; }
      if (!r.ok) throw new Error(value.error);
      if (!cancelled) { setData(value.data || {}); setNotice(""); }
    }).catch(e => { if (!cancelled) { setData({}); setNotice(e instanceof Error ? e.message : "Não foi possível carregar as avaliações."); } });
    return () => { cancelled = true; };
  }, [platform]);
  const metrics = data.metrics || { total: 0, average: 0, negative: 0, unanswered: 0, reports: 0 };
  const rows = useMemo(() => [...(data.ratings || []), ...(data.reviews || [])].slice(0, 100), [data]);
  return <main className="financePanel" style={{ maxWidth: 1400, margin: "0 auto", padding: 32 }}>
    <div className="technologyHero"><div><span>OPERAÇÕES · QUALIDADE</span><h1>Avaliações &amp; Reputação</h1><p>Supervisão central da qualidade de restaurantes, pratos e entregas em todas as plataformas.</p></div><select value={platform} onChange={e => setPlatform(e.target.value)}><option value="all">Todas as plataformas</option><option value="deligo">DeliGo</option><option value="sarca">SARCA</option><option value="taomoz">DeliGo Market</option><option value="mestre24">Mestre24</option><option value="comunhao">Comunhão</option></select></div>
    {notice && <div className="operationalNotice">{notice}</div>}
    <div className="financeKpis">{[["Avaliações", metrics.total], ["Média global", metrics.average.toFixed(2)], ["Negativas (1–2⭐)", metrics.negative], ["Sem resposta", metrics.unanswered], ["Denúncias", metrics.reports]].map(([label, value]) => <article key={String(label)}><span>{label}</span><strong>{value}</strong><small>dados reais autorizados</small></article>)}</div>
    <section className="financePanel"><div className="panelTitle"><div><span>MODERAÇÃO E QUALIDADE</span><h2>Todas as avaliações</h2><p>Comida, restaurante e entrega mantêm dimensões separadas.</p></div></div><div className="institutionalTable"><div className="institutionalRow institutionalHead"><span>Pedido</span><span>Restaurante</span><span>Comida</span><span>Entrega</span><span>Comentário</span><span>Data</span><span>Estado</span></div>{rows.map((row, index) => <div className="institutionalRow" key={String(row.id || index)}><span>{String(row.order_id || "—")}</span><span>{String(row.restaurant_food_rating || row.rating || "—")} ⭐</span><span>{String(row.restaurant_food_rating || row.food_rating || "—")} ⭐</span><span>{String(row.courier_time_rating || row.service_rating || "—")} ⭐</span><span>{String(row.restaurant_comment || row.courier_comment || row.comment || "Sem comentário")}</span><span>{row.created_at ? new Date(String(row.created_at)).toLocaleDateString("pt-MZ") : "—"}</span><b>{row.visible === false ? "Oculta" : "Visível"}</b></div>)}{!rows.length && <div className="peopleEmpty">Sem avaliações registadas.</div>}</div></section>
    <div className="safeNotice"><b>Regra de reputação</b><span>A Central supervisiona e modera. O restaurante responde pela comida e o estafeta pela entrega; nenhuma avaliação é removida sem motivo e auditoria.</span></div>
  </main>;
}
