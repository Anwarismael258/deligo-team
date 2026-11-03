"use client";

import { useEffect, useState } from "react";

type RecordRow = Record<string, unknown> & { id?: string };
type PricingData = { policy: RecordRow | null; zones: RecordRow[]; timeWindows: RecordRow[]; tolls: RecordRow[] };

const empty: PricingData = { policy: null, zones: [], timeWindows: [], tolls: [] };
const numberValue = (value: unknown, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;

function Field({ label, value, onChange, type = "number", step }: { label: string; value: string | number; onChange: (value: string) => void; type?: string; step?: string }) {
  return <label style={{ display: "grid", gap: 6, color: "#9fb2c7", fontSize: 12 }}>{label}<input type={type} step={step} value={value} onChange={(event) => onChange(event.target.value)} style={{ width: "100%", border: "1px solid #2a405b", borderRadius: 10, background: "#0b1b2d", color: "#f6f9fc", padding: "10px 12px" }} /></label>;
}

export default function SarcaPricingPage() {
  const [data, setData] = useState<PricingData>(empty);
  const [notice, setNotice] = useState("A carregar as regras reais do SARCA…");
  const [saving, setSaving] = useState(false);
  const [toll, setToll] = useState({ name: "", city: "", road_name: "", direction: "", latitude: "", longitude: "", radius_meters: "100", vehicle_class: "", amount_minor: "", currency_code: "MZN", effective_from: "", effective_until: "", source_name: "", source_url: "", notes: "" });

  const load = async () => {
    setNotice("A carregar as regras reais do SARCA…");
    const response = await fetch("/api/sarca/pricing", { cache: "no-store" });
    const body = await response.json();
    if (response.status === 401) { window.location.assign(`/login?next=${encodeURIComponent(window.location.pathname)}`); return; }
    if (!response.ok) throw new Error(body.error || "Não foi possível carregar as regras.");
    setData({ ...empty, ...body });
    setNotice("");
  };

  useEffect(() => {
    let cancelled = false;
    fetch("/api/sarca/pricing", { cache: "no-store" }).then(async (response) => {
      const body = await response.json();
      if (response.status === 401) { window.location.assign(`/login?next=${encodeURIComponent(window.location.pathname)}`); return; }
      if (!response.ok) throw new Error(body.error || "Não foi possível carregar as regras.");
      if (!cancelled) { setData({ ...empty, ...body }); setNotice(""); }
    }).catch((error) => { if (!cancelled) setNotice(error instanceof Error ? error.message : "Não foi possível carregar as regras."); });
    return () => { cancelled = true; };
  }, []);

  const save = async (resource: string, record: RecordRow) => {
    setSaving(true); setNotice("A guardar na Central…");
    try {
      const response = await fetch("/api/sarca/pricing", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ resource, record }) });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || "Não foi possível guardar.");
      await load();
      setNotice("Guardado. O próximo orçamento já usa esta regra.");
    } catch (error) { setNotice(error instanceof Error ? error.message : "Não foi possível guardar."); }
    finally { setSaving(false); }
  };

  const remove = async (resource: string, id: string) => {
    if (!window.confirm("Remover esta configuração? A ação não deve ser usada para apagar histórico de viagens.")) return;
    setSaving(true);
    try {
      const response = await fetch("/api/sarca/pricing", { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ resource, id }) });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || "Não foi possível remover.");
      await load(); setNotice("Configuração removida.");
    } catch (error) { setNotice(error instanceof Error ? error.message : "Não foi possível remover."); }
    finally { setSaving(false); }
  };

  const policy = data.policy || {};
  return <main className="financePanel" style={{ maxWidth: 1420, margin: "0 auto", padding: 32 }}>
    <div className="technologyHero"><div><span>OPERAÇÕES · SARCA</span><h1>Preço, ajustes e portagens</h1><p>Uma fonte operacional para a tarifa da viagem. A comissão é aplicada apenas à viagem; a portagem fica separada e é mostrada ao passageiro.</p></div><span style={{ color: "#9fb2c7" }}>Central · configuração protegida</span></div>
    {notice && <div className="operationalNotice">{notice}</div>}
    <section className="financePanel" style={{ marginTop: 18 }}><div className="panelTitle"><div><span>POLÍTICA GLOBAL</span><h2>Limite e ajustes</h2><p>Os valores estão em pontos-base: 100 = 1%. Temperatura normal não aumenta o preço por padrão.</p></div></div><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(170px,1fr))", gap: 14 }}>
      {[['max_adjustment_bps', 'Limite total (%)'], ['peak_hour_adjustment_bps', 'Pico (%)'], ['night_adjustment_bps', 'Madrugada (%)'], ['rain_adjustment_bps', 'Chuva (%)'], ['heat_adjustment_bps', 'Calor ≥36º (%)'], ['demand_adjustment_bps', 'Procura (%)'], ['zone_default_adjustment_bps', 'Zona padrão (%)']].map(([key, label]) => <Field key={key} label={label} value={(numberValue(policy[key]) / 100).toFixed(2)} step="0.01" onChange={(value) => setData((current) => ({ ...current, policy: { ...policy, [key]: Math.round(numberValue(value) * 100) } }))} />)}
    </div><button disabled={saving || !data.policy} onClick={() => save("pricing_adjustment_policy", data.policy || {})} style={{ marginTop: 16, background: "#f7b32b", color: "#101d2b", border: 0, borderRadius: 10, padding: "11px 18px", fontWeight: 700 }}>Guardar política</button></section>

    <section className="financePanel" style={{ marginTop: 18 }}><div className="panelTitle"><div><span>PORTAGENS VERIFICADAS</span><h2>Portagens da rota</h2><p>Nenhuma praça é inventada: cadastre apenas uma portagem real, com coordenadas, classe e valor confirmados.</p></div></div><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(180px,1fr))", gap: 14 }}>
      <Field label="Nome da praça" type="text" value={toll.name} onChange={(value) => setToll({ ...toll, name: value })} /><Field label="Cidade" type="text" value={toll.city} onChange={(value) => setToll({ ...toll, city: value })} /><Field label="Estrada/avenida" type="text" value={toll.road_name} onChange={(value) => setToll({ ...toll, road_name: value })} /><Field label="Sentido (N/S/L/O ou graus)" type="text" value={toll.direction} onChange={(value) => setToll({ ...toll, direction: value })} /><Field label="Latitude" step="any" value={toll.latitude} onChange={(value) => setToll({ ...toll, latitude: value })} /><Field label="Longitude" step="any" value={toll.longitude} onChange={(value) => setToll({ ...toll, longitude: value })} /><Field label="Raio (m)" value={toll.radius_meters} onChange={(value) => setToll({ ...toll, radius_meters: value })} /><Field label="Classe do veículo (opcional)" type="text" value={toll.vehicle_class} onChange={(value) => setToll({ ...toll, vehicle_class: value })} /><Field label="Valor em MZN" value={toll.amount_minor} onChange={(value) => setToll({ ...toll, amount_minor: value })} /><Field label="Vigência inicial" type="datetime-local" value={toll.effective_from} onChange={(value) => setToll({ ...toll, effective_from: value })} /><Field label="Vigência final (opcional)" type="datetime-local" value={toll.effective_until} onChange={(value) => setToll({ ...toll, effective_until: value })} /><Field label="Fonte" type="text" value={toll.source_name} onChange={(value) => setToll({ ...toll, source_name: value })} /><Field label="URL da fonte" type="url" value={toll.source_url} onChange={(value) => setToll({ ...toll, source_url: value })} /><Field label="Notas de verificação" type="text" value={toll.notes} onChange={(value) => setToll({ ...toll, notes: value })} />
    </div><button disabled={saving || !toll.name || !toll.latitude || !toll.longitude || !toll.amount_minor} onClick={() => { save("toll_points", { ...toll, latitude: numberValue(toll.latitude), longitude: numberValue(toll.longitude), radius_meters: numberValue(toll.radius_meters, 100), amount_minor: Math.round(numberValue(toll.amount_minor) * 100), effective_from: toll.effective_from ? new Date(toll.effective_from).toISOString() : null, effective_until: toll.effective_until ? new Date(toll.effective_until).toISOString() : null, is_active: true }); setToll({ name: "", city: "", road_name: "", direction: "", latitude: "", longitude: "", radius_meters: "100", vehicle_class: "", amount_minor: "", currency_code: "MZN", effective_from: "", effective_until: "", source_name: "", source_url: "", notes: "" }); }} style={{ marginTop: 16, background: "#f7b32b", color: "#101d2b", border: 0, borderRadius: 10, padding: "11px 18px", fontWeight: 700 }}>Adicionar portagem real</button><div className="institutionalTable" style={{ marginTop: 18 }}><div className="institutionalRow institutionalHead"><span>Praça</span><span>Cidade</span><span>Classe</span><span>Valor</span><span>Estado</span><span>Ação</span></div>{data.tolls.map((row) => <div className="institutionalRow" key={String(row.id)}><span>{String(row.name)}</span><span>{String(row.city || "—")}</span><span>{String(row.vehicle_class || "todas")}</span><span>{(numberValue(row.amount_minor) / 100).toFixed(2)} MZN</span><span>{row.is_active === false ? "Inativa" : "Ativa"}</span><button onClick={() => remove("toll_points", String(row.id))}>Remover</button></div>)}{!data.tolls.length && <div className="peopleEmpty">Nenhuma portagem cadastrada. Isso é correto até a Central confirmar dados reais.</div>}</div></section>

    <section className="financePanel" style={{ marginTop: 18 }}><div className="panelTitle"><div><span>JANELAS E ZONAS</span><h2>Configuração operacional</h2><p>As tabelas estão prontas para janelas de madrugada/pico e zonas específicas. O cálculo usa apenas registros ativos e dentro da validade.</p></div></div><div className="institutionalTable"><div className="institutionalRow institutionalHead"><span>Janelas horárias</span><span>Zona</span><span>Portagens</span></div><div className="institutionalRow"><span>{data.timeWindows.length} configuradas pela Central</span><span>{data.zones.length} configuradas pela Central</span><span>{data.tolls.length} verificadas</span></div></div></section>
  </main>;
}
