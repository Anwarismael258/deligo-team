import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

type WeatherResponse = {
  main?: { temp?: number; temp_max?: number; temp_min?: number; humidity?: number };
  wind?: { speed?: number };
  weather?: Array<{ main?: string; description?: string; icon?: string }>;
};

export async function GET() {
  const apiKey = process.env.OPENWEATHER_API_KEY?.trim();
  if (!apiKey) {
    return NextResponse.json({ status: "unconfigured", message: "Meteorologia não configurada no servidor." }, { status: 503 });
  }

  const url = new URL("https://api.openweathermap.org/data/2.5/weather");
  url.searchParams.set("lat", "-25.9653");
  url.searchParams.set("lon", "32.5892");
  url.searchParams.set("appid", apiKey);
  url.searchParams.set("units", "metric");
  url.searchParams.set("lang", "pt");

  try {
    const response = await fetch(url, { next: { revalidate: 600 } });
    if (!response.ok) {
      return NextResponse.json({ status: "unavailable", message: "Serviço meteorológico indisponível." }, { status: 502 });
    }
    const data = await response.json() as WeatherResponse;
    const main = data.main;
    if (!main || !Number.isFinite(main.temp)) {
      return NextResponse.json({ status: "unavailable", message: "Dados meteorológicos incompletos." }, { status: 502 });
    }
    const condition = data.weather?.[0];
    return NextResponse.json({
      status: "ok",
      location: "Maputo",
      current: main.temp,
      maximum: main.temp_max,
      minimum: main.temp_min,
      humidity: main.humidity,
      windKmh: typeof data.wind?.speed === "number" ? data.wind.speed * 3.6 : null,
      condition: condition?.main || "",
      description: condition?.description || "",
      icon: condition?.icon || null,
    }, { headers: { "Cache-Control": "private, max-age=300, stale-while-revalidate=600" } });
  } catch {
    return NextResponse.json({ status: "unavailable", message: "Não foi possível consultar a meteorologia." }, { status: 502 });
  }
}
