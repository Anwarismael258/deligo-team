import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { corporateAuthorization, hqRest, hqRpc, requireCorporatePermission, stagingRest } from "@/lib/hq-server";
import { platformRest, signPlatformPath } from "@/lib/platform-backends";

export const dynamic = "force-dynamic";

type MapMarker = Record<string, unknown>;
type MapRoute = { id: string; platform: string; label: string; coordinates: [number, number][]; updatedAt: string; origin?: string; destination?: string; workerId?: string; workerName?: string; operationStatus?: string };

const LIVE_WINDOW_MS = 5 * 60_000;
const inServiceStatuses = new Set([
  "in_progress", "in_service", "on_trip", "started", "active", "ongoing",
  "on_the_way", "out_for_delivery", "in_delivery", "delivering", "picked_up",
]);
const terminalStatuses = new Set(["delivered", "cancelled", "canceled", "failed", "completed", "closed", "removed", "deleted", "suspended", "inactive", "archived"]);

const coordinate = (value: unknown) => {
  if (value === null || value === undefined || value === "") return null;
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
const profileImage = (row: MapMarker) => firstValue(row, ["avatar_url", "profile_photo_url", "profile_image_url", "photo_url", "image_url", "picture", "logo_url"]);
const profileId = (row: MapMarker) => firstValue(row, ["profile_id", "user_id", "owner_id", "restaurant_id", "courier_id", "driver_user_id", "driver_id", "rider_user_id", "passenger_user_id"]);
const operationReference = (row: MapMarker, fallback: string) => String(firstValue(row, ["order_number", "order_code", "reference", "tracking_number", "code"]) || fallback);
const statusValue = (row: MapMarker) => String(firstValue(row, ["status", "state", "trip_status"]) || "").toLowerCase();
const isRecent = (value: unknown, windowMs = LIVE_WINDOW_MS) => {
  const time = Date.parse(String(value || ""));
  return Number.isFinite(time) && Date.now() - time >= 0 && Date.now() - time <= windowMs;
};
const isInService = (row: MapMarker) => inServiceStatuses.has(statusValue(row)) && !terminalStatuses.has(statusValue(row));
const hasLiveSignal = (row: MapMarker, windowMs = LIVE_WINDOW_MS) =>
  row.online === true || row.is_online === true || row.isOnline === true || isRecent(firstValue(row, ["recorded_at", "location_recorded_at", "last_seen_at", "heartbeat_at", "updated_at", "updatedAt"]), windowMs);
const isActiveEntity = (row: MapMarker) => {
  const explicit = firstValue(row, ["status", "account_status", "profile_status", "membership_status", "state"]);
  const normalized = String(explicit || "").toLowerCase();
  if (row.is_active === false || row.deleted_at || row.removed_at || row.archived_at) return false;
  return !new Set(["removed", "deleted", "suspended", "inactive", "archived", "blocked", "deactivated", "profile_removed"]).has(normalized);
};
// Places have a stable address; an explicitly open/online place is a valid
// live entity even when it does not emit GPS heartbeats like a driver does.
// Removed, blocked and archived profiles are still excluded above.
const livePlace = (row: MapMarker) => isActiveEntity(row) && row.is_open !== false && row.online !== false && row.is_online !== false && (row.is_open === true || row.online === true || row.is_online === true || hasLiveSignal(row, 10 * 60_000));

export async function GET() {
  const authorization = await corporateAuthorization();
  if (!(await cookies()).get("hq_access_token")?.value || !authorization) {
    return NextResponse.json({ error: "Sessao corporativa necessaria." }, { status: 401 });
  }

  try {
    const accessPromise = Promise.all([requireCorporatePermission("operations.view", "deligo", authorization), requireCorporatePermission("operations.view", "taomoz", authorization), requireCorporatePermission("operations.view", "sarca", authorization)]);
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
          signal: AbortSignal.timeout(4_000),
        });
        if (response.ok) base = await response.json() as typeof base;
        else base.sourceMessage = `A fonte de localização ao vivo respondeu com ${response.status}.`;
      } catch {
        base.sourceMessage = "A fonte de localização ao vivo não respondeu; as fontes autorizadas continuam disponíveis.";
      }
    }
    let sourceAvailable = base.sourceStatus === "fresh";
    const checkedAt = new Date().toISOString();
    const [deligoAccess, marketAccess, sarcaAccess] = await accessPromise;
    const operationDetails = new Map<string, MapMarker>();
    const baseSlug = (value: unknown) => { const name = String(value || "").toLowerCase();return /sarca/.test(name) ? "sarca" : /market|taomoz/.test(name) ? "taomoz" : /comunh/.test(name) ? "comunhao" : /mestre/.test(name) ? "mestre24" : /deligo/.test(name) ? "deligo" : ""; };
    const markers = (Array.isArray(base.markers) ? [...base.markers] : []).filter(marker =>
      (authorization.isSuperAdmin || (authorization.permissions.includes("operations.view") && authorization.platformSlugs.includes(baseSlug(marker.platform)))) &&
      isActiveEntity(marker) && hasLiveSignal(marker) && !terminalStatuses.has(statusValue(marker)) && !["searching_driver", "driver_assigned", "driver_arriving", "pending", "created", "requested"].includes(statusValue(marker))
    );
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
    if (deligoAccess) {
      const deligo = await safeRows(() => hqRpc("hq_deligo_operational_map_v1", { p_actor_auth_user_id: deligoAccess.actor.authUserId })) as { orders?: MapMarker[]; restaurants?: MapMarker[]; couriers?: MapMarker[] } | null;
      if (deligo) sourceAvailable = true;
      for (const restaurant of deligo?.restaurants || []) {
        const location = point(restaurant.latitude, restaurant.longitude);
        if (!location || !livePlace(restaurant)) continue;
        addMarker({ id: `deligo:restaurant:${String(restaurant.id)}`, platform: "DeliGo", role: "Restaurante", workerName: restaurant.name, status: restaurant.is_open ? "disponivel" : "offline", service: `${restaurant.active_orders || 0} pedidos ativos`, latitude: location[0], longitude: location[1], updatedAt: checkedAt });
      }
      for (const order of deligo?.orders || []) {
        const orderId = String(order.id || "");
        if (!isInService(order) || !hasLiveSignal(order)) continue;
        const reference = operationReference(order, orderId);
        operationDetails.set(`deligo:order:${orderId}`, { origin: order.origin_address || order.restaurant_name, destination: order.destination_address || order.delivery_address, operationStatus: order.status, driverId: order.courier_id || order.driver_user_id });
        const origin = point(order.origin_latitude, order.origin_longitude);
        const destination = point(order.destination_latitude, order.destination_longitude);
        const updatedAt = typeof order.updated_at === "string" ? order.updated_at : checkedAt;
        if (origin) addMarker({ id: `deligo:order:${orderId}:origin`, platform: "DeliGo", role: "Pedido", service: `#${reference}`, status: "em_servico", latitude: origin[0], longitude: origin[1], updatedAt });
        if (destination) addMarker({ id: `deligo:order:${orderId}:destination`, platform: "DeliGo", role: "Cliente", service: `#${reference}`, status: "ocupado", latitude: destination[0], longitude: destination[1], updatedAt });
        // Do not draw a route from a search or from two static addresses.
        // A route requires actual telemetry from an active delivery.
      }

      // Some DeliGo environments expose coordinates in the platform tables,
      // while the HQ RPC only returns the live courier snapshot. Read both
      // existing operational sources and merge them without duplicating IDs.
      const [orders, deliveries, restaurants] = await Promise.all([
        safeRows(() => platformRest("deligo", "orders?select=*&order=updated_at.desc&limit=500")),
        safeRows(() => platformRest("deligo", "deliveries?select=*&order=updated_at.desc&limit=500")),
        safeRows(() => platformRest("deligo", "restaurants?select=*&order=updated_at.desc&limit=500")),
      ]) as [MapMarker[] | null, MapMarker[] | null, MapMarker[] | null];
      if (orders !== null || deliveries !== null || restaurants !== null) sourceAvailable = true;
      for (const restaurant of restaurants || []) {
        const location = point(firstValue(restaurant, ["latitude", "lat"]), firstValue(restaurant, ["longitude", "lng", "lon"]));
        if (!location) continue;
        if (!livePlace(restaurant)) continue;
        addMarker({ id: `deligo:restaurant:${String(restaurant.id)}`, profileId: String(profileId(restaurant) || restaurant.id), profilePlatform: "deligo", profilePhotoUrl: profileImage(restaurant) || undefined, platform: "DeliGo", role: "Restaurante", workerName: String(firstValue(restaurant, ["name", "restaurant_name"]) || "Restaurante"), status: restaurant.is_open === false ? "offline" : "disponivel", latitude: location[0], longitude: location[1], updatedAt: String(firstValue(restaurant, ["updated_at", "created_at"]) || checkedAt) });
      }
      const active = (row: MapMarker) => isInService(row) && hasLiveSignal(row);
      for (const order of orders || []) {
        if (!active(order)) continue;
        const id = String(order.id || order.order_id || "");
        if (!id) continue;
        const reference = operationReference(order, id);
        operationDetails.set(`deligo:order:${id}`, { origin: order.pickup_address || order.restaurant_name || order.origin_address, destination: order.delivery_address || order.destination_address, operationStatus: order.status, driverId: order.courier_id || order.driver_user_id });
        const origin = point(firstValue(order, ["origin_latitude", "pickup_latitude", "restaurant_latitude", "pickup_lat"]), firstValue(order, ["origin_longitude", "pickup_longitude", "restaurant_longitude", "pickup_lng"]));
        const destination = point(firstValue(order, ["destination_latitude", "delivery_latitude", "customer_latitude", "dropoff_lat"]), firstValue(order, ["destination_longitude", "delivery_longitude", "customer_longitude", "dropoff_lng"]));
        const updatedAt = String(firstValue(order, ["updated_at", "created_at"]) || checkedAt);
        if (origin) addMarker({ id: `deligo:order:${id}:origin`, profileId: String(firstValue(order, ["restaurant_id", "seller_id"]) || "") || undefined, profilePlatform: "deligo", profilePhotoUrl: profileImage(order) || undefined, platform: "DeliGo", role: "Pedido", service: `#${reference}`, status: "em_servico", latitude: origin[0], longitude: origin[1], updatedAt });
        if (destination) addMarker({ id: `deligo:order:${id}:destination`, profileId: String(firstValue(order, ["customer_id", "user_id", "client_id"]) || "") || undefined, profilePlatform: "deligo", profilePhotoUrl: profileImage(order) || undefined, platform: "DeliGo", role: "Cliente", service: `#${reference}`, status: "ocupado", latitude: destination[0], longitude: destination[1], updatedAt });
        // Static pickup/drop-off points are not a real route.
      }
      for (const delivery of deliveries || []) {
        if (!active(delivery)) continue;
        const id = String(delivery.id || delivery.delivery_id || delivery.order_id || "");
        const current = point(firstValue(delivery, ["current_latitude", "latitude", "current_lat"]), firstValue(delivery, ["current_longitude", "longitude", "current_lng"]));
        if (!id || !current) continue;
        addMarker({ id: `deligo:delivery:${id}:current`, profileId: String(delivery.courier_id || delivery.driver_user_id || "") || undefined, profilePlatform: "deligo", profilePhotoUrl: profileImage(delivery) || undefined, platform: "DeliGo", role: "Estafeta", workerId: String(delivery.courier_id || delivery.driver_user_id || ""), workerName: String(delivery.courier_name || delivery.driver_name || "") || undefined, service: `#${operationReference(delivery, String(delivery.order_id || id))}`, status: "em_servico", latitude: current[0], longitude: current[1], updatedAt: String(firstValue(delivery, ["location_recorded_at", "updated_at", "created_at"]) || checkedAt) });
      }
    }

    // DeliGo Market uses the same read-only operational contract when the
    // platform exposes its active orders and delivery positions. A missing
    // endpoint remains unavailable; it is never represented as zero data.
    if (marketAccess) {
      const [marketOrders, marketDeliveries] = await Promise.all([
        safeRows(() => platformRest("taomoz", "orders?select=*&order=updated_at.desc&limit=500")),
        safeRows(() => platformRest("taomoz", "deliveries?select=*&order=updated_at.desc&limit=500")),
      ]) as [MapMarker[] | null, MapMarker[] | null];
      if (marketOrders !== null || marketDeliveries !== null) sourceAvailable = true;
      const activeMarket = (row: MapMarker) => isInService(row) && hasLiveSignal(row);
      for (const order of marketOrders || []) {
        if (!activeMarket(order)) continue;
        const id = String(order.id || order.order_id || "");
        if (!id) continue;
        const reference = operationReference(order, id);
        operationDetails.set(`market:order:${id}`, { origin: order.pickup_address || order.seller_name || order.origin_address, destination: order.delivery_address || order.destination_address, operationStatus: order.status, driverId: order.courier_id || order.driver_user_id });
        const origin = point(firstValue(order, ["origin_latitude", "pickup_latitude", "seller_latitude", "pickup_lat"]), firstValue(order, ["origin_longitude", "pickup_longitude", "seller_longitude", "pickup_lng"]));
        const destination = point(firstValue(order, ["destination_latitude", "delivery_latitude", "customer_latitude", "dropoff_lat"]), firstValue(order, ["destination_longitude", "delivery_longitude", "customer_longitude", "dropoff_lng"]));
        const updatedAt = String(firstValue(order, ["updated_at", "created_at"]) || checkedAt);
        if (origin) addMarker({ id: `market:order:${id}:origin`, profileId: String(firstValue(order, ["seller_id", "vendor_id", "store_id"]) || "") || undefined, profilePlatform: "taomoz", profilePhotoUrl: profileImage(order) || undefined, platform: "DeliGo Market", role: "Encomenda", service: `#${reference}`, status: "em_servico", latitude: origin[0], longitude: origin[1], updatedAt });
        if (destination) addMarker({ id: `market:order:${id}:destination`, profileId: String(firstValue(order, ["customer_id", "buyer_id", "user_id"]) || "") || undefined, profilePlatform: "taomoz", profilePhotoUrl: profileImage(order) || undefined, platform: "DeliGo Market", role: "Cliente", service: `#${reference}`, status: "ocupado", latitude: destination[0], longitude: destination[1], updatedAt });
        // Do not draw a route from two static addresses. A real route needs
        // telemetry from an active delivery.
      }
      for (const delivery of marketDeliveries || []) {
        if (!activeMarket(delivery)) continue;
        const id = String(delivery.id || delivery.delivery_id || delivery.order_id || "");
        const current = point(firstValue(delivery, ["current_latitude", "latitude", "current_lat"]), firstValue(delivery, ["current_longitude", "longitude", "current_lng"]));
        if (!id || !current) continue;
        addMarker({ id: `market:delivery:${id}:current`, profileId: String(delivery.courier_id || delivery.driver_user_id || "") || undefined, profilePlatform: "taomoz", profilePhotoUrl: profileImage(delivery) || undefined, platform: "DeliGo Market", role: "Entregador", workerId: String(delivery.courier_id || delivery.driver_user_id || ""), workerName: String(delivery.courier_name || delivery.driver_name || "") || undefined, service: `#${operationReference(delivery, String(delivery.order_id || id))}`, status: "em_servico", latitude: current[0], longitude: current[1], updatedAt: String(firstValue(delivery, ["location_recorded_at", "updated_at", "created_at"]) || checkedAt) });
      }
    }

    // SARCA exposes verified trip endpoints. Keep this read-only and scoped
    // to workers who have the platform operations permission.
    if (sarcaAccess) {
      const trips = await safeRows(() => platformRest("sarca", "trips?select=*&status=in.(searching_driver,offered_to_driver,driver_assigned,driver_arriving,in_progress,on_trip,started,active)&order=updated_at.desc&limit=200")) as MapMarker[] | null;
      if (trips !== null) sourceAvailable = true;
      const since = encodeURIComponent(new Date(Date.now() - 5 * 60_000).toISOString());
      const [driverRows, riderRows, onlineDrivers] = await Promise.all([
        safeRows(() => platformRest("sarca", `driver_location_events?select=driver_user_id,latitude,longitude,recorded_at&recorded_at=gte.${since}&order=recorded_at.desc&limit=500`)),
        safeRows(() => platformRest("sarca", `rider_location_events?select=rider_user_id,trip_id,latitude,longitude,recorded_at&recorded_at=gte.${since}&order=recorded_at.desc&limit=500`)),
        // Some SARCA versions keep the driver's current GPS in the profile
        // and do not emit a location event for every heartbeat. Read that
        // canonical online snapshot as a fallback for the live map.
        safeRows(() => platformRest("sarca", "driver_profiles?select=*&status=eq.active&is_online=eq.true&current_lat=not.is.null&current_lng=not.is.null&order=updated_at.desc&limit=500")),
      ]) as [MapMarker[] | null, MapMarker[] | null, MapMarker[] | null];
      const activeTripIds = (trips || []).map(trip => String(trip.id || "")).filter(id => /^[0-9a-f-]{36}$/i.test(id));
      const platformRouteRows = activeTripIds.length
        ? await safeRows(() => platformRest("sarca", `trip_route_points?trip_id=in.(${activeTripIds.join(",")})&recorded_at=gte.${since}&select=trip_id,source,latitude,longitude,recorded_at,accuracy_meters&order=recorded_at.asc&limit=5000`)) as MapMarker[] | null
        : [];
      const hqRouteRows = activeTripIds.length
        ? await safeRows(() => hqRest(`sarca_trip_route_points?trip_id=in.(${activeTripIds.join(",")})&recorded_at=gte.${since}&select=trip_id,source,latitude,longitude,recorded_at,accuracy_meters&order=recorded_at.asc&limit=5000`)) as MapMarker[] | null
        : [];
      const routeRows = [...(platformRouteRows || []), ...(hqRouteRows || [])];
      const centralTrackByTrip = new Map<string, Array<{ position: [number, number]; recordedAt: string; source: string }>>();
      const routePointKeys = new Set<string>();
      for (const row of routeRows) {
        const position = point(row.latitude, row.longitude);
        const tripId = String(row.trip_id || "");
        const recordedAt = String(row.recorded_at || "");
        if (!position || !tripId || !Number.isFinite(Date.parse(recordedAt))) continue;
        const pointKey = `${tripId}:${String(row.source || "system")}:${recordedAt}:${position[0]}:${position[1]}`;
        if (routePointKeys.has(pointKey)) continue;
        routePointKeys.add(pointKey);
        const track = centralTrackByTrip.get(tripId) || [];
        track.push({ position, recordedAt, source: String(row.source || "system") });
        centralTrackByTrip.set(tripId, track);
      }
      const latestDrivers = new Map<string, MapMarker>();
      const latestRiders = new Map<string, MapMarker>();
      for (const row of driverRows || []) if (!latestDrivers.has(String(row.driver_user_id))) latestDrivers.set(String(row.driver_user_id), row);
      for (const row of riderRows || []) if (!latestRiders.has(String(row.trip_id))) latestRiders.set(String(row.trip_id), row);
      // Recent GPS events also represent people who are online but not
      // currently assigned to a trip. Show those positions as availability
      // markers; they must never create an operation or a route.
      for (const [driverId, row] of latestDrivers) {
        const position = point(row.latitude, row.longitude);
        if (!position || !isRecent(row.recorded_at)) continue;
        addMarker({ id: `sarca:driver:${driverId}:current`, platform: "SARCA", role: "Driver", workerId: driverId, status: "disponivel", latitude: position[0], longitude: position[1], updatedAt: String(row.recorded_at) });
      }
      for (const row of onlineDrivers || []) {
        if (!isActiveEntity(row) || row.is_online !== true) continue;
        const driverId = String(row.user_id || "");
        const position = point(row.current_lat, row.current_lng);
        if (!driverId || !position) continue;
        addMarker({ id: `sarca:driver:${driverId}:current`, profileId: driverId, profilePlatform: "sarca", profilePhotoUrl: profileImage(row) || undefined, platform: "SARCA", role: "Driver", workerId: driverId, workerName: String(firstValue(row, ["full_name", "display_name"]) || "Motorista SARCA"), status: "disponivel", latitude: position[0], longitude: position[1], updatedAt: String(row.updated_at) });
      }
      const latestRidersByUser = new Map<string, MapMarker>();
      for (const row of riderRows || []) {
        const riderId = String(row.rider_user_id || "");
        if (riderId && !latestRidersByUser.has(riderId)) latestRidersByUser.set(riderId, row);
      }
      for (const [riderId, row] of latestRidersByUser) {
        const position = point(row.latitude, row.longitude);
        if (!position || !isRecent(row.recorded_at)) continue;
        addMarker({ id: `sarca:rider:${riderId}:current`, profileId: riderId, profilePlatform: "sarca", platform: "SARCA", role: "Rider", workerId: riderId, status: "disponivel", latitude: position[0], longitude: position[1], updatedAt: String(row.recorded_at) });
      }
      for (const trip of trips || []) {
        const tripId = String(trip.id || "");
        const centralTrack = centralTrackByTrip.get(tripId) || [];
        const centralLatestDriver = [...centralTrack].reverse().find(item => item.source === "driver");
        const centralLatestRider = [...centralTrack].reverse().find(item => item.source === "rider");
        const driverId = String(firstValue(trip, ["driver_id", "driver_user_id"]) || "");
        const driverTrack = (driverRows || [])
          .filter(row => String(row.driver_user_id || "") === driverId)
          .map(row => point(row.latitude, row.longitude) ? { position: point(row.latitude, row.longitude) as [number, number], recordedAt: String(row.recorded_at || "") } : null)
          .filter((row): row is { position: [number, number]; recordedAt: string } => Boolean(row && Number.isFinite(Date.parse(row.recordedAt))))
          .sort((a, b) => Date.parse(a.recordedAt) - Date.parse(b.recordedAt));
        const driverPosition = latestDrivers.get(String(trip.driver_user_id));
        const riderPosition = latestRiders.get(String(trip.id));
        if (driverPosition) Object.assign(trip, { driver_latitude: driverPosition.latitude, driver_longitude: driverPosition.longitude, driver_recorded_at: driverPosition.recorded_at });
        else if (centralLatestDriver) Object.assign(trip, { driver_latitude: centralLatestDriver.position[0], driver_longitude: centralLatestDriver.position[1], driver_recorded_at: centralLatestDriver.recordedAt });
        if (riderPosition) Object.assign(trip, { rider_latitude: riderPosition.latitude, rider_longitude: riderPosition.longitude, rider_recorded_at: riderPosition.recorded_at });
        else if (centralLatestRider) Object.assign(trip, { rider_latitude: centralLatestRider.position[0], rider_longitude: centralLatestRider.position[1], rider_recorded_at: centralLatestRider.recordedAt });
        const reference = operationReference(trip, tripId);
        operationDetails.set(`sarca:trip:${tripId}`, { origin: trip.pickup_address, destination: trip.dropoff_address, operationStatus: trip.status, driverId: trip.driver_user_id, passengerId: trip.passenger_user_id });
        const origin = point(trip.pickup_lat, trip.pickup_lng);
        const destination = point(trip.dropoff_lat, trip.dropoff_lng);
        const updatedAt = typeof trip.updated_at === "string" ? trip.updated_at : checkedAt;
        if (origin) addMarker({ id: `sarca:trip:${tripId}:origin`, platform: "SARCA", role: "Viagem", service: `#${reference}`, status: "em_servico", latitude: origin[0], longitude: origin[1], updatedAt });
        if (destination) addMarker({ id: `sarca:trip:${tripId}:destination`, platform: "SARCA", role: "Destino", workerId: String(trip.passenger_user_id || ""), service: `#${reference}`, status: "ocupado", latitude: destination[0], longitude: destination[1], updatedAt });
        const driver = point(firstValue(trip, ["driver_latitude", "driver_current_latitude", "driver_lat", "current_driver_latitude"]), firstValue(trip, ["driver_longitude", "driver_current_longitude", "driver_lng", "current_driver_longitude"]));
        const rider = point(firstValue(trip, ["rider_latitude", "rider_current_latitude", "rider_lat", "current_rider_latitude"]), firstValue(trip, ["rider_longitude", "rider_current_longitude", "rider_lng", "current_rider_longitude"]));
        if (driver) addMarker({ id: `sarca:trip:${tripId}:driver`, profileId: String(firstValue(trip, ["driver_id", "driver_user_id"]) || "") || undefined, profilePlatform: "sarca", platform: "SARCA", role: "Driver", workerId: String(firstValue(trip, ["driver_id", "driver_user_id"]) || ""), workerName: String(firstValue(trip, ["driver_name", "driver_full_name"]) || "") || undefined, service: `#${reference}`, status: "em_servico", latitude: driver[0], longitude: driver[1], updatedAt: trip.driver_recorded_at || updatedAt });
        if (rider) addMarker({ id: `sarca:trip:${tripId}:rider`, profileId: String(firstValue(trip, ["rider_id", "rider_user_id", "passenger_user_id"]) || "") || undefined, profilePlatform: "sarca", platform: "SARCA", role: "Rider", workerId: String(firstValue(trip, ["rider_id", "rider_user_id", "passenger_user_id"]) || ""), workerName: String(firstValue(trip, ["rider_name", "rider_full_name"]) || "") || undefined, service: `#${reference}`, status: "ocupado", latitude: rider[0], longitude: rider[1], updatedAt: trip.rider_recorded_at || updatedAt });
        const tripStatus = String(trip.status || "");
        const tripHasAssignedRoute = ["driver_assigned", "driver_arriving", "in_progress", "on_trip", "started", "active"].includes(tripStatus);
        if (origin && destination && tripHasAssignedRoute) {
          const actualCoordinates = centralTrack.length >= 2 ? centralTrack.map(item => item.position) : driverTrack.map(item => item.position);
          const coordinates = actualCoordinates.length >= 2 ? actualCoordinates : [origin, destination];
          routes.push({ id: `sarca:trip:${tripId}`, platform: "SARCA", label: actualCoordinates.length >= 2 ? `Percurso #${reference}` : `Rota prevista #${reference}`, coordinates, updatedAt: centralTrack.at(-1)?.recordedAt || driverTrack.at(-1)?.recordedAt || updatedAt, origin: String(trip.pickup_address || "") || undefined, destination: String(trip.dropoff_address || "") || undefined, workerId: driverId || undefined, workerName: String(firstValue(trip, ["driver_name", "driver_full_name"]) || "") || undefined, operationStatus: tripStatus });
        }
      }
    }

    const enrichedMarkers: MapMarker[] = markers.map(marker => {
      const key = String(marker.id).split(":").slice(0, -1).join(":");
      const details = operationDetails.get(key);
      return { ...marker, origin: details?.origin, destination: details?.destination, operationStatus: details?.operationStatus,
        locationKind: /:(origin|destination)$/.test(String(marker.id)) ? "endpoint" : /restaurante|loja/i.test(String(marker.role)) ? "place" : "gps" };
    });
    const workerIds = [...new Set([...enrichedMarkers.map(marker => String(marker.workerId || "")), ...[...operationDetails.values()].map(details => String(details.driverId || ""))].filter(id => /^[0-9a-f-]{36}$/i.test(id)))];
    const names = new Map<string, string | undefined>();
    if (workerIds.length) {
      const batches = Array.from({ length: Math.ceil(workerIds.length / 75) }, (_, index) => workerIds.slice(index * 75, (index + 1) * 75));
      const results = await Promise.all(batches.map(ids => safeRows(() => stagingRest(`profiles?select=id,user_id,full_name&or=(id.in.(${ids.join(",")}),user_id.in.(${ids.join(",")}))`))));
      const identities = results.flatMap(rows => Array.isArray(rows) ? rows : []) as Array<{id:string;user_id?:string;full_name?:string;avatar_url?:string|null}>;
      for (const profile of identities || []) { names.set(profile.id, profile.full_name);if (profile.user_id) names.set(profile.user_id, profile.full_name); }
      for (const marker of enrichedMarkers) {
        if (!marker.workerName && marker.workerId) marker.workerName = names.get(String(marker.workerId)) || undefined;
        if (!marker.profilePhotoUrl && marker.workerId) {
          const profile = identities.find(item => item.id === marker.workerId || item.user_id === marker.workerId);
          if (profile?.avatar_url) marker.profilePhotoUrl = profile.avatar_url;
        }
      }
    }
    const signedMarkers = await Promise.all(enrichedMarkers.map(async marker => {
      const platform = String(marker.profilePlatform || "").toLowerCase();
      const supported = ["deligo", "comunhao", "sarca", "taomoz", "mestre24"].includes(platform) ? platform as "deligo" | "comunhao" | "sarca" | "taomoz" | "mestre24" : null;
      return marker.profilePhotoUrl && supported ? { ...marker, profilePhotoUrl: await signPlatformPath(supported, String(marker.profilePhotoUrl)) } : marker;
    }));
    const enrichedRoutes = routes
      .filter(route => route.coordinates.length >= 2 && ["driver_assigned", "driver_arriving", "in_progress", "on_trip", "started", "active"].includes(String(route.operationStatus || "")) && isRecent(route.updatedAt))
      .map(route => ({ ...route, origin: operationDetails.get(route.id)?.origin, destination: operationDetails.get(route.id)?.destination, operationStatus: operationDetails.get(route.id)?.operationStatus || route.operationStatus, workerId: operationDetails.get(route.id)?.driverId || route.workerId, workerName: names.get(String(operationDetails.get(route.id)?.driverId || route.workerId || "")) || route.workerName }));
    return NextResponse.json({ ...base, checkedAt, markers: signedMarkers, routes: enrichedRoutes, sourceStatus: sourceAvailable ? "fresh" : "unavailable" }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    // Do not turn an unavailable GPS adapter into a misleading zero.
    return NextResponse.json({ checkedAt: new Date().toISOString(), markers: [], sourceStatus: "unavailable", sourceMessage: "A fonte de localização não respondeu." }, { status: 502, headers: { "Cache-Control": "private, no-store" } });
  }
}
