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

const firstValue = (row: MapMarker, keys: string[]) => keys.map((key) => row[key]).find((value) => value !== null && value !== undefined && value !== "");
const operationReference = (row: MapMarker, fallback: string) => String(firstValue(row, ["order_number", "order_code", "reference", "tracking_number", "code"]) || fallback);

export async function GET() {
  if (!(await cookies()).get("hq_access_token")?.value || !(await corporateActor())) {
    return NextResponse.json({ error: "Sessao corporativa necessaria." }, { status: 401 });
  }

  try {
    const anonKey = process.env.SUPABASE_ANON_KEY;
    const integrationSecret = process.env.DELIGO_STAGING_DB_PASSWORD;
    const centralUrl = process.env.SUPABASE_URL?.trim();
    // The central live-location adapter is optional. Do not make the whole
    // map unusable when that adapter is not configured; platform sources can
    // still provide verified orders, trips and places.
    let base: { checkedAt?: string; markers?: MapMarker[]; sourceStatus?: string; sourceMessage?: string } = {
      checkedAt: new Date().toISOString(),
      markers: [],
      sourceStatus: "unavailable",
      sourceMessage: "A integração de localização ao vivo não está configurada; a consultar as fontes autorizadas.",
    };
    if (centralUrl && anonKey && integrationSecret) {
      try {
        const response = await fetch(`${centralUrl.replace(/\/$/, "")}/rest/v1/rpc/hq_live_map_v1`, {
          method: "POST",
          headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}`, "Content-Type": "application/json", "x-hq-integration-secret": integrationSecret },
          body: "{}",
          cache: "no-store",
          signal: AbortSignal.timeout(12_000),
        });
        if (response.ok) base = await response.json() as typeof base;
        else base.sourceMessage = `A fonte de localização ao vivo respondeu com ${response.status}.`;
      } catch {
        base.sourceMessage = "A fonte de localização ao vivo não respondeu; as fontes autorizadas continuam disponíveis.";
      }
    }
    const checkedAt = base.checkedAt || new Date().toISOString();
    const markers = Array.isArray(base.markers) ? [...base.markers] : [];
    const routes: MapRoute[] = [];
    const markerIds = new Set(markers.map((marker) => String(marker.id || "")));
    const addMarker = (marker: MapMarker) => {
      const id = String(marker.id || "");
      if (!id || markerIds.has(id)) return;
      markerIds.add(id);
      markers.push(marker);
    };

    // DeliGo's already-authorized operational RPC contains active orders,
    // couriers and restaurants. Only add map objects when coordinates exist.
    const deligoAccess = await requireCorporatePermission("operations.view", "deligo");
    if (deligoAccess) {
      const deligo = await safeRows(() => hqRpc("hq_deligo_operational_map_v1", { p_actor_auth_user_id: deligoAccess.actor.authUserId })) as { orders?: MapMarker[]; restaurants?: MapMarker[]; couriers?: MapMarker[] } | null;
      for (const restaurant of deligo?.restaurants || []) {
        const location = point(restaurant.latitude, restaurant.longitude);
        if (!location) continue;
        addMarker({ id: `deligo:restaurant:${String(restaurant.id)}`, platform: "DeliGo", role: "Restaurante", workerName: restaurant.name, status: restaurant.is_open ? "disponivel" : "offline", service: `${restaurant.active_orders || 0} pedidos ativos`, latitude: location[0], longitude: location[1], updatedAt: checkedAt });
      }
      for (const order of deligo?.orders || []) {
        const orderId = String(order.id || "");
        const reference = operationReference(order, orderId);
        const origin = point(order.origin_latitude, order.origin_longitude);
        const destination = point(order.destination_latitude, order.destination_longitude);
        const updatedAt = typeof order.updated_at === "string" ? order.updated_at : checkedAt;
        if (origin) addMarker({ id: `deligo:order:${orderId}:origin`, platform: "DeliGo", role: "Pedido", service: `#${reference}`, status: "em_servico", latitude: origin[0], longitude: origin[1], updatedAt });
        if (destination) addMarker({ id: `deligo:order:${orderId}:destination`, platform: "DeliGo", role: "Cliente", service: `#${reference}`, status: "ocupado", latitude: destination[0], longitude: destination[1], updatedAt });
        if (origin && destination) routes.push({ id: `deligo:order:${orderId}`, platform: "DeliGo", label: `Pedido #${reference}`, coordinates: [origin, destination], updatedAt });
      }

      // Some DeliGo environments expose coordinates in the platform tables,
      // while the HQ RPC only returns the live courier snapshot. Read both
      // existing operational sources and merge them without duplicating IDs.
      const [orders, deliveries, restaurants] = await Promise.all([
        safeRows(() => platformRest("deligo", "orders?select=*&order=updated_at.desc&limit=500")),
        safeRows(() => platformRest("deligo", "deliveries?select=*&order=updated_at.desc&limit=500")),
        safeRows(() => platformRest("deligo", "restaurants?select=*&order=updated_at.desc&limit=500")),
      ]) as [MapMarker[] | null, MapMarker[] | null, MapMarker[] | null];
      for (const restaurant of restaurants || []) {
        const location = point(firstValue(restaurant, ["latitude", "lat"]), firstValue(restaurant, ["longitude", "lng", "lon"]));
        if (!location) continue;
        addMarker({ id: `deligo:restaurant:${String(restaurant.id)}`, platform: "DeliGo", role: "Restaurante", workerName: String(firstValue(restaurant, ["name", "restaurant_name"]) || "Restaurante"), status: restaurant.is_open === false ? "offline" : "disponivel", latitude: location[0], longitude: location[1], updatedAt: String(firstValue(restaurant, ["updated_at", "created_at"]) || checkedAt) });
      }
      const active = (row: MapMarker) => !["delivered", "cancelled", "failed", "completed"].includes(String(row.status || "").toLowerCase());
      for (const order of orders || []) {
        if (!active(order)) continue;
        const id = String(order.id || order.order_id || "");
        if (!id) continue;
        const reference = operationReference(order, id);
        const origin = point(firstValue(order, ["origin_latitude", "pickup_latitude", "restaurant_latitude", "pickup_lat"]), firstValue(order, ["origin_longitude", "pickup_longitude", "restaurant_longitude", "pickup_lng"]));
        const destination = point(firstValue(order, ["destination_latitude", "delivery_latitude", "customer_latitude", "dropoff_lat"]), firstValue(order, ["destination_longitude", "delivery_longitude", "customer_longitude", "dropoff_lng"]));
        const updatedAt = String(firstValue(order, ["updated_at", "created_at"]) || checkedAt);
        if (origin) addMarker({ id: `deligo:order:${id}:origin`, platform: "DeliGo", role: "Pedido", service: `#${reference}`, status: "em_servico", latitude: origin[0], longitude: origin[1], updatedAt });
        if (destination) addMarker({ id: `deligo:order:${id}:destination`, platform: "DeliGo", role: "Cliente", service: `#${reference}`, status: "ocupado", latitude: destination[0], longitude: destination[1], updatedAt });
        if (origin && destination && !routes.some((route) => route.id === `deligo:order:${id}`)) routes.push({ id: `deligo:order:${id}`, platform: "DeliGo", label: `Pedido #${reference}`, coordinates: [origin, destination], updatedAt });
      }
      for (const delivery of deliveries || []) {
        if (!active(delivery)) continue;
        const id = String(delivery.id || delivery.delivery_id || delivery.order_id || "");
        const current = point(firstValue(delivery, ["current_latitude", "latitude", "current_lat"]), firstValue(delivery, ["current_longitude", "longitude", "current_lng"]));
        if (!id || !current) continue;
        addMarker({ id: `deligo:delivery:${id}:current`, platform: "DeliGo", role: "Estafeta", service: `#${operationReference(delivery, String(delivery.order_id || id))}`, status: "em_servico", latitude: current[0], longitude: current[1], updatedAt: String(firstValue(delivery, ["location_recorded_at", "updated_at", "created_at"]) || checkedAt) });
      }
    }

    // DeliGo Market uses the same read-only operational contract when the
    // platform exposes its active orders and delivery positions. A missing
    // endpoint remains unavailable; it is never represented as zero data.
    const marketAccess = await requireCorporatePermission("operations.view", "taomoz");
    if (marketAccess) {
      const [marketOrders, marketDeliveries] = await Promise.all([
        safeRows(() => platformRest("taomoz", "orders?select=*&order=updated_at.desc&limit=500")),
        safeRows(() => platformRest("taomoz", "deliveries?select=*&order=updated_at.desc&limit=500")),
      ]) as [MapMarker[] | null, MapMarker[] | null];
      const activeMarket = (row: MapMarker) => !["delivered", "cancelled", "failed", "completed"].includes(String(row.status || "").toLowerCase());
      for (const order of marketOrders || []) {
        if (!activeMarket(order)) continue;
        const id = String(order.id || order.order_id || "");
        if (!id) continue;
        const reference = operationReference(order, id);
        const origin = point(firstValue(order, ["origin_latitude", "pickup_latitude", "seller_latitude", "pickup_lat"]), firstValue(order, ["origin_longitude", "pickup_longitude", "seller_longitude", "pickup_lng"]));
        const destination = point(firstValue(order, ["destination_latitude", "delivery_latitude", "customer_latitude", "dropoff_lat"]), firstValue(order, ["destination_longitude", "delivery_longitude", "customer_longitude", "dropoff_lng"]));
        const updatedAt = String(firstValue(order, ["updated_at", "created_at"]) || checkedAt);
        if (origin) addMarker({ id: `market:order:${id}:origin`, platform: "DeliGo Market", role: "Encomenda", service: `#${reference}`, status: "em_servico", latitude: origin[0], longitude: origin[1], updatedAt });
        if (destination) addMarker({ id: `market:order:${id}:destination`, platform: "DeliGo Market", role: "Cliente", service: `#${reference}`, status: "ocupado", latitude: destination[0], longitude: destination[1], updatedAt });
        if (origin && destination) routes.push({ id: `market:order:${id}`, platform: "DeliGo Market", label: `Encomenda #${reference}`, coordinates: [origin, destination], updatedAt });
      }
      for (const delivery of marketDeliveries || []) {
        if (!activeMarket(delivery)) continue;
        const id = String(delivery.id || delivery.delivery_id || delivery.order_id || "");
        const current = point(firstValue(delivery, ["current_latitude", "latitude", "current_lat"]), firstValue(delivery, ["current_longitude", "longitude", "current_lng"]));
        if (!id || !current) continue;
        addMarker({ id: `market:delivery:${id}:current`, platform: "DeliGo Market", role: "Entregador", service: `#${operationReference(delivery, String(delivery.order_id || id))}`, status: "em_servico", latitude: current[0], longitude: current[1], updatedAt: String(firstValue(delivery, ["location_recorded_at", "updated_at", "created_at"]) || checkedAt) });
      }
    }

    // SARCA exposes verified trip endpoints. Keep this read-only and scoped
    // to workers who have the platform operations permission.
    const sarcaAccess = await requireCorporatePermission("operations.view", "sarca");
    if (sarcaAccess) {
      const trips = await safeRows(() => platformRest("sarca", "trips?select=*&status=in.(searching_driver,driver_assigned,driver_arriving,in_progress)&order=updated_at.desc&limit=200")) as MapMarker[] | null;
      for (const trip of trips || []) {
        const tripId = String(trip.id || "");
        const reference = operationReference(trip, tripId);
        const origin = point(trip.pickup_lat, trip.pickup_lng);
        const destination = point(trip.dropoff_lat, trip.dropoff_lng);
        const updatedAt = typeof trip.updated_at === "string" ? trip.updated_at : checkedAt;
        if (origin) addMarker({ id: `saraca:trip:${tripId}:origin`, platform: "SARCA", role: "Viagem", service: `#${reference}`, status: "em_servico", latitude: origin[0], longitude: origin[1], updatedAt });
        if (destination) addMarker({ id: `saraca:trip:${tripId}:destination`, platform: "SARCA", role: "Rider", service: `#${reference}`, status: "ocupado", latitude: destination[0], longitude: destination[1], updatedAt });
        const driver = point(firstValue(trip, ["driver_latitude", "driver_current_latitude", "driver_lat", "current_driver_latitude"]), firstValue(trip, ["driver_longitude", "driver_current_longitude", "driver_lng", "current_driver_longitude"]));
        const rider = point(firstValue(trip, ["rider_latitude", "rider_current_latitude", "rider_lat", "current_rider_latitude"]), firstValue(trip, ["rider_longitude", "rider_current_longitude", "rider_lng", "current_rider_longitude"]));
        if (driver) addMarker({ id: `saraca:trip:${tripId}:driver`, platform: "SARCA", role: "Driver", workerId: String(firstValue(trip, ["driver_id", "driver_user_id"]) || ""), workerName: String(firstValue(trip, ["driver_name", "driver_full_name"]) || "") || undefined, service: `#${reference}`, status: "em_servico", latitude: driver[0], longitude: driver[1], updatedAt });
        if (rider) addMarker({ id: `saraca:trip:${tripId}:rider`, platform: "SARCA", role: "Rider", workerId: String(firstValue(trip, ["rider_id", "rider_user_id"]) || ""), workerName: String(firstValue(trip, ["rider_name", "rider_full_name"]) || "") || undefined, service: `#${reference}`, status: "ocupado", latitude: rider[0], longitude: rider[1], updatedAt });
        if (origin && destination) routes.push({ id: `saraca:trip:${tripId}`, platform: "SARCA", label: `Viagem #${reference}`, coordinates: [origin, destination], updatedAt });
      }
    }

    return NextResponse.json({ ...base, checkedAt, markers, routes, sourceStatus: base.sourceStatus || "fresh" }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    // Do not turn an unavailable GPS adapter into a misleading zero.
    return NextResponse.json({ checkedAt: new Date().toISOString(), markers: [], sourceStatus: "unavailable", sourceMessage: "A fonte de localização não respondeu." }, { status: 502, headers: { "Cache-Control": "private, no-store" } });
  }
}
