"use client";

import { useEffect, useState } from "react";

type Weather = {
  status: "ok" | "unconfigured" | "unavailable";
  location?: string;
  current?: number;
  maximum?: number;
  minimum?: number;
  humidity?: number;
  windKmh?: number | null;
  condition?: string;
  description?: string;
  message?: string;
};

const degree = (value?: number) => typeof value === "number" && Number.isFinite(value) ? `${Math.round(value)}°` : "—";
const isRain = (condition = "") => /rain|drizzle|thunderstorm|chuva|trovoada/i.test(condition);

export function WeatherWidget() {
  const [weather, setWeather] = useState<Weather | null>(null);
  const [hydrationDismissed, setHydrationDismissed] = useState(false);

  useEffect(() => {
    let disposed = false;
    const load = async () => {
      try {
        const response = await fetch("/api/weather", { cache: "no-store" });
        const body = await response.json() as Weather;
        if (!disposed) setWeather(body);
      } catch {
        if (!disposed) setWeather({ status: "unavailable", message: "Meteorologia indisponível." });
      }
    };
    void load();
    const timer = window.setInterval(load, 600_000);
    return () => { disposed = true; window.clearInterval(timer); };
  }, []);

  if (!weather || weather.status !== "ok") {
    return <span className="weatherWidget weatherWidgetMuted" title={weather?.message || "A carregar meteorologia"}>Maputo · —</span>;
  }

  const rain = isRain(weather.condition);
  const hot = Number(weather.maximum) > 36 || Number(weather.current) > 36;
  return <div className={`weatherWidget ${rain ? "weatherWidgetRain" : ""}`} title={`${weather.location} · ${weather.description || weather.condition || "Condições actuais"}`}>
    {rain && <span className="weatherRain" aria-hidden="true"><i /><i /><i /><i /><i /></span>}
    <span className="weatherPlace">{weather.location}</span>
    <strong className="weatherCurrent">{degree(weather.current)}</strong>
    <span className="weatherRange"><b>{degree(weather.maximum)}</b><b>{degree(weather.minimum)}</b></span>
    <span className="weatherMeta">{weather.humidity ?? "—"}% · {typeof weather.windKmh === "number" ? Math.round(weather.windKmh) : "—"} km/h</span>
    {hot && !hydrationDismissed && <span className="hydrationNotice"><span>Hidratação recomendada</span><button type="button" aria-label="Fechar aviso de hidratação" onClick={() => setHydrationDismissed(true)}>×</button></span>}
  </div>;
}
