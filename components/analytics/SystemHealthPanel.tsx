import { ChartContainer } from "./ChartContainer";

type HealthState = "operational" | "degraded" | "unavailable" | "unknown";
type HealthItem = { id: string; label: string; state: HealthState; detail: string };

const stateLabel: Record<HealthState, string> = { operational: "Operacional", degraded: "Degradado", unavailable: "Indisponível", unknown: "Desconhecido" };

export function SystemHealthPanel({ platforms, commandCenterCheckedAt }: { platforms: Array<{ name: string; connected?: boolean; platform_status?: string; data_freshness?: string }>; commandCenterCheckedAt?: string }) {
  const platformItems: HealthItem[] = platforms.map((platform) => {
    const status = String(platform.platform_status || "").toLowerCase();
    const state: HealthState = platform.connected && ["connected", "operational", "active"].includes(status) ? "operational" : platform.connected || platform.data_freshness ? "degraded" : "unknown";
    return { id: `platform-${platform.name}`, label: platform.name, state, detail: platform.data_freshness || "Sem confirmação recente da fonte." };
  });
  const items: HealthItem[] = [
    ...platformItems,
    { id: "realtime", label: "Feed operacional", state: commandCenterCheckedAt ? "degraded" : "unknown", detail: commandCenterCheckedAt ? "Polling/cursor activo; Supabase Realtime uniforme não confirmado." : "Sem verificação recente." },
    { id: "paysuite", label: "PaySuite", state: "unknown", detail: "Saldo/saúde externa não disponível por endpoint oficial verificado." },
    { id: "webhooks", label: "Webhooks", state: "unknown", detail: "Sem health-check recente agregado." },
    { id: "notifications", label: "Notificações", state: "unknown", detail: "Entrega do provedor requer confirmação recente." },
  ];
  return <ChartContainer title="Saúde das plataformas e integrações" description="Estados só são marcados como operacionais quando existe confirmação recente; desconhecido não significa online."><div className="analyticsBarList">{items.map(item => <div className="analyticsBarRow" key={item.id}><div><strong>{item.label}</strong><small>{item.detail}</small></div><span><b className={`analyticsHealth-${item.state}`}>{stateLabel[item.state]}</b></span></div>)}</div></ChartContainer>;
}
