import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { corporateActor, hqRpc, requireCorporatePermission } from "@/lib/hq-server";
import { platformRest } from "@/lib/platform-backends";

export const dynamic = "force-dynamic";

type MapMarker = Record<string, unknown>;
type MapRoute = { id: string; platform: string; label: string; coordinates: [number, number][]; updatedAt: string };

const coordinate = (value: unknown) => {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

const point = (lat: unknown, lng: unknown): [number, number] | null => {
  const latitude = coordinate(lat);
  const longitude = coordinate(lng);
  if (latitude === null || longitude === null || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return [latitude, longitude];
};

const safeRows = async <T,>(loader: () => Promise<T>): Promise<T | null> => {
  try { return await loader(); } catch { return null; }
};

export async function GET() {
  if (!(await cookies()).get("hq_access_token")?.value || !(await corporateActor())) {
    return NextResponse.json({ error: "Sessao corporativa necessaria." }, { status: 401 });
  }

  const anonKey = process.env.SUPABASE_ANON_KEY;
  const integrationSecret = process.env.DELIGO_STAGING_DB_PASSWORD;
  if (!anonKey || !integrationSecret) {
    return NextResponse.json({ error: "Integracao de localizacao nao configurada." }, { status: 503 });
  }

  try {
    const centralUrl = process.env.SUPABASE_URL?.trim();
    if (!centralUrl) return NextResponse.json({ error: "Mapa operacional não configurado para produção." }, { status: 503 });
    const response = await fetch(`${centralUrl.replace(/\/$/, "")}/rest/v1/rpc/hq_live_map_v1`, {
      method: "POST",
      headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}`, "Content-Type": "application/json", "x-hq-integration-secret": integrationSecret },
      body: "{}",
      cache: "no-store",
      signal: AbortSignal.timeout(12_000),
    });
    if (!response.ok) throw new Error(`HQ_MAP_RPC_${response.status}`);
    const base = await response.json() as { checkedAt?: string; markers?: MapMarker[]; sourceStatus?: string; sourceMessage?: string };
    const checkedAt = base.checkedAt || new Date().toISOString();
    const markers = Array.isArray(base.markers) ? [...base.markers] : [];
    const routes: MapRoute[] = [];

    // DeliGo's already-authorized operational RPC contains active orders,
    // couriers and restaurants. Only add map objects when coordinates exist.
    const deligoAccess = await requireCorporatePermission("operations.view", "deligo");
    if (deligoAccess) {
      const deligo = await safeRows(() => hqRpc("hq_deligo_operational_map_v1", { p_actor_auth_user_id: deligoAccess.actor.authUserId })) as { orders?: MapMarker[]; restaurants?: MapMarker[]; couriers?: MapMarker[] } | null;
      for (const restaurant of deligo?.restaurants || []) {
        const location = point(restaurant.latitude, restaurant.longitude);
        if (!location) continue;
        markers.push({ id: `deligo:restaurant:${String(restaurant.id)}`, platform: "DeliGo", role: "Restaurante", workerName: restaurant.name, status: restaurant.is_open ? "disponivel" : "offline", service: `${restaurant.active_orders || 0} pedidos ativos`, latitude: location[0], longitude: location[1], updatedAt: checkedAt });
      }
      for (const order of deligo?.orders || []) {
        const origin = point(order.origin_latitude, order.origin_longitude);
        const destination = point(order.destination_latitude, order.destination_longitude);
        const updatedAt = typeof order.updated_at === "string" ? order.updated_at : checkedAt;
        if (origin) markers.push({ id: `deligo:order:${String(order.id)}:origin`, platform: "DeliGo", role: "Pedido", service: String(order.id), status: "em_servico", latitude: origin[0], longitude: origin[1], updatedAt });
        if (destination) markers.push({ id: `deligo:order:${String(order.id)}:destination`, platform: "DeliGo", role: "Cliente", service: String(order.id), status: "ocupado", latitude: destination[0], longitude: destination[1], updatedAt });
        if (origin && destination) routes.push({ id: `deligo:order:${String(order.id)}`, platform: "DeliGo", label: `Pedido ${String(order.id).slice(0, 8)}`, coordinates: [origin, destination], updatedAt });
      }
    }

    // SARCA exposes verified trip endpoints. Keep this read-only and scoped
    // to workers who have the platform operations permission.
    const sarcaAccess = await requireCorporatePermission("operations.view", "sarca");
    if (sarcaAccess) {
      const trips = await safeRows(() => platformRest("sarca", "trips?select=id,status,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng,requested_at,updated_at&status=in.(searching_driver,driver_assigned,driver_arriving,in_progress)&order=updated_at.desc&limit=200")) as MapMarker[] | null;
      for (const trip of trips || []) {
        const origin = point(trip.pickup_lat, trip.pickup_lng);
        const destination = point(trip.dropoff_lat, trip.dropoff_lng);
        const updatedAt = typeof trip.updated_at === "string" ? trip.updated_at : checkedAt;
        if (origin) markers.push({ id: `saraca:trip:${String(trip.id)}:origin`, platform: "SARCA", role: "Viagem", service: String(trip.id), status: "em_servico", latitude: origin[0], longitude: origin[1], updatedAt });
        if (destination) markers.push({ id: `saraca:trip:${String(trip.id)}:destination`, platform: "SARCA", role: "Cliente", service: String(trip.id), status: "ocupado", latitude: destination[0], longitude: destination[1], updatedAt });
        if (origin && destination) routes.push({ id: `saraca:trip:${String(trip.id)}`, platform: "SARCA", label: `Viagem ${String(trip.id).slice(0, 8)}`, coordinates: [origin, destination], updatedAt });
      }
    }

    return NextResponse.json({ ...base, checkedAt, markers, routes, sourceStatus: base.sourceStatus || "fresh" }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    // Do not turn an unavailable GPS adapter into a misleading zero.
    return NextResponse.json({ checkedAt: new Date().toISOString(), markers: [], sourceStatus: "unavailable", sourceMessage: "A fonte de localização não respondeu." }, { status: 502, headers: { "Cache-Control": "private, no-store" } });
  }
}
