"use client";

import { useEffect, useMemo, useState } from "react";
import { Activity, Cpu, FileText, Radio, RefreshCw } from "lucide-react";

export type MonitorState = "operational" | "degraded" | "offline" | "checking" | "unknown";

type MonitorPlatform = { name?: string; connected?: boolean; platform_status?: string; data_freshness?: string };
type MonitorEvent = { event_type?: string; entity_type?: string; occurred_at?: string; platforms?: { name?: string } };
type EngineMonitorProps = {
  checkedAt?: string;
  platforms?: MonitorPlatform[];
  realtimeState: MonitorState;
  realtimeCheckedAt?: string;
  lastEvent?: MonitorEvent;
};

const labels: Record<MonitorState, string> = {
  operational: "Operacional",
  degraded: "Degradado",
  offline: "Offline",
  checking: "A verificar",
  unknown: "Estado não verificado",
};

const stateClass = (state: MonitorState) => `centralEngineState-${state}`;
const validDate = (value?: string) => {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
const formatDate = (value?: string) => {
  const date = validDate(value);
  return date ? date.toLocaleString("pt-MZ", { dateStyle: "short", timeStyle: "short" }) : "—";
};
const relativeTime = (value?: string) => {
  const date = validDate(value);
  if (!date) return "—";
  const seconds = Math.max(0, Math.round((Date.now() - date.getTime()) / 1000));
  if (seconds < 60) return `há ${seconds} s`;
  const minutes = Math.round(seconds / 60);
  return `há ${minutes} min`;
};
const platformState = (platform: MonitorPlatform): MonitorState => {
  const status = String(platform.platform_status || "").toLowerCase();
  if (platform.connected && ["connected", "operational", "active"].includes(status)) return "operational";
  if (platform.connected || platform.data_freshness) return "degraded";
  return "unknown";
};

export function CentralEngineMonitor({ checkedAt, platforms = [], realtimeState, realtimeCheckedAt, lastEvent }: EngineMonitorProps) {
  const [visible, setVisible] = useState(true);
  const [diagnosticsOpen, setDiagnosticsOpen] = useState(false);
  const states = platforms.map(platformState);
  const serviceState: MonitorState = !platforms.length
    ? (checkedAt ? "unknown" : "checking")
    : states.some(state => state === "offline")
      ? "offline"
      : states.some(state => state === "degraded")
        ? "degraded"
        : states.every(state => state === "operational")
          ? "operational"
          : "unknown";
  const syncState: MonitorState = useMemo(() => {
    const date = validDate(checkedAt);
    if (!date) return "unknown";
    const age = Date.now() - date.getTime();
    return age <= 60_000 ? "operational" : age <= 180_000 ? "degraded" : "offline";
  }, [checkedAt]);
  const overallState: MonitorState = [serviceState, realtimeState, syncState].includes("offline")
    ? "offline"
    : [serviceState, realtimeState, syncState].includes("degraded")
      ? "degraded"
      : [serviceState, realtimeState, syncState].includes("checking")
        ? "checking"
        : [serviceState, realtimeState, syncState].every(state => state === "operational")
          ? "operational"
          : "unknown";
  const lastVerification = [checkedAt, realtimeCheckedAt].map(validDate).filter((date): date is Date => Boolean(date)).sort((a, b) => b.getTime() - a.getTime())[0];

  useEffect(() => {
    const update = () => setVisible(document.visibilityState === "visible");
    update();
    document.addEventListener("visibilitychange", update);
    return () => document.removeEventListener("visibilitychange", update);
  }, []);

  return <section className={`centralEngineMonitor ${visible ? "isVisible" : "isHidden"}`} aria-label="Motor da Central">
    <div className="centralEngineTopline">
      <div className="centralEngineTitle">
        <span className="centralEngineIcon" aria-hidden="true"><Cpu size={28} strokeWidth={1.8} /></span>
        <div><span className="centralEngineEyebrow">CENTRAL HQ · MONITORIZAÇÃO</span><h2>Motor da Central</h2><p>Monitorização ativa</p></div>
      </div>
      <div className="centralEngineStatusArea"><button type="button" className="centralEngineDiagnostics" onClick={() => setDiagnosticsOpen(value => !value)} aria-expanded={diagnosticsOpen}>Ver diagnóstico <span aria-hidden="true">→</span></button><span className={`centralEngineStatus ${stateClass(overallState)}`}><i />{labels[overallState]}</span></div>
    </div>
    <div className={`centralEngineWaves ${visible ? "isAnimating" : "isPaused"}`} aria-hidden="true">
      <span className="centralEngineGrid" /><svg viewBox="0 0 900 90" preserveAspectRatio="none"><path className="centralEngineWave centralEngineWaveCyan" d="M0 48 C85 3 150 80 230 46 S370 8 450 47 S590 80 670 43 S820 7 900 45" /><path className="centralEngineWave centralEngineWaveViolet" d="M0 53 C95 20 160 75 245 51 S380 20 465 52 S600 74 690 49 S815 18 900 51" /><circle className="centralEngineDot centralEngineDotOne" cx="230" cy="46" r="3" /><circle className="centralEngineDot centralEngineDotTwo" cx="670" cy="43" r="3" /></svg><span className="centralEngineWaveCaption">Estado dos serviços autorizados</span></div>
    <div className="centralEngineStates"><span className={stateClass(serviceState)}><i /><b>Serviços</b><small>{labels[serviceState]}</small></span><span className={stateClass(realtimeState)}><Radio size={16} /><b>Realtime</b><small>{labels[realtimeState]}</small></span><span className={stateClass(syncState)}><RefreshCw size={16} /><b>Sincronização</b><small>{labels[syncState]}</small></span></div>
    <div className="centralEngineMeta"><span><Activity size={17} /><b>Última verificação</b><strong>{lastVerification ? `${relativeTime(lastVerification.toISOString())} · ${formatDate(lastVerification.toISOString())}` : "Estado não verificado"}</strong></span><span><FileText size={17} /><b>Último evento</b><strong>{lastEvent?.occurred_at ? `${lastEvent.platforms?.name || "Central"} · ${String(lastEvent.event_type || lastEvent.entity_type || "Evento recebido")} · ${relativeTime(lastEvent.occurred_at)}` : "Nenhum evento autorizado disponível"}</strong></span></div>
    {diagnosticsOpen && <div className="centralEngineDiagnosticsPanel" role="status"><strong>Diagnóstico autorizado</strong><span>Serviços: {labels[serviceState]}</span><span>Realtime: {labels[realtimeState]}{realtimeCheckedAt ? ` · ${formatDate(realtimeCheckedAt)}` : ""}</span><span>Sincronização: {labels[syncState]}{checkedAt ? ` · ${formatDate(checkedAt)}` : ""}</span><small>Os estados dependem das verificações reais da Central; a ausência de eventos não é tratada como falha.</small></div>}
  </section>;
}
