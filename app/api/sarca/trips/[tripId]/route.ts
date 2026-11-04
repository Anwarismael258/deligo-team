import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRest, hqRpc, requireCorporatePermission, stagingRest } from "@/lib/hq-server";
import { platformRest } from "@/lib/platform-backends";

export const dynamic = "force-dynamic";

type Row = Record<string, unknown>;
type Point = { latitude: number; longitude: number; recordedAt: string; accuracyMeters: number | null; speedKmh: number | null; phase: string | null; segment: "to_pickup" | "trip" | "unknown"; source: "driver" | "rider"; isOfflineSync: boolean };

const num = (value: unknown) => {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};
const validPoint = (row: Row, source: Point["source"]): Point | null => {
  const latitude = num(row.latitude);
  const longitude = num(row.longitude);
  const recordedAt = String(row.recorded_at || row.recordedAt || "");
  if (latitude === null || longitude === null || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 || !recordedAt || !Number.isFinite(Date.parse(recordedAt))) return null;
  const metadata = row.metadata && typeof row.metadata === "object" ? row.metadata as Row : {};
  const phase = typeof row.phase === "string" ? row.phase : typeof metadata.phase === "string" ? metadata.phase : null;
  const segment = metadata.segment === "to_pickup" || phase === "driver_assigned" || phase === "driver_arriving"
    ? "to_pickup"
    : phase === "in_progress" || phase === "payment_pending" ? "trip" : "unknown";
  return { latitude, longitude, recordedAt, accuracyMeters: num(row.accuracy_meters), speedKmh: num(row.speed_kmh), phase, segment, source, isOfflineSync: row.source === "offline_sync" || Boolean(row.is_offline_sync) };
};
const planned = (trip: Row) => {
  const aLat = num(trip.pickup_lat), aLng = num(trip.pickup_lng), bLat = num(trip.dropoff_lat), bLng = num(trip.dropoff_lng);
  return aLat === null || aLng === null || bLat === null || bLng === null ? [] : [[aLat, aLng], [bLat, bLng]];
};
const tripIdFromRequest = (request: NextRequest, params: { tripId: string }) => params.tripId || request.nextUrl.pathname.split("/").filter(Boolean).pop() || "";

const routeIngestionSecret = () => process.env.HQ_ROUTE_INGESTION_SECRET?.trim() || "";
const distanceMeters = (a: Point, b: Point) => {
  const radians = (value: number) => value * Math.PI / 180;
  const dLat = radians(b.latitude - a.latitude);
  const dLng = radians(b.longitude - a.longitude);
  const base = Math.sin(dLat / 2) ** 2 + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(base), Math.sqrt(Math.max(0, 1 - base)));
};

export async function GET(request: NextRequest, { params }: { params: Promise<{ tripId: string }> }) {
  const authorization = await corporateAuthorization();
  const allowed = await requireCorporatePermission("operations.view", "sarca", authorization || undefined);
  if (!allowed || !authorization) return NextResponse.json({ error: "Sem permissão para consultar viagens SARCA." }, { status: 403 });
  const tripId = tripIdFromRequest(request, await params);
  if (!/^[0-9a-f-]{36}$/i.test(tripId)) return NextResponse.json({ error: "ID de viagem inválido." }, { status: 400 });

  try {
    const accessAction = request.nextUrl.searchParams.get("export") === "1" ? "export_trip_audit" : "view_trip_audit";
    const trips = await platformRest("sarca", `trips?id=eq.${encodeURIComponent(tripId)}&select=*&limit=1`) as Row[];
    const trip = trips[0];
    if (!trip) return NextResponse.json({ error: "Viagem não encontrada." }, { status: 404 });
    await platformRest("sarca", "rpc/record_trip_access_audit", {
      method: "POST",
      body: JSON.stringify({
        p_trip_id: tripId,
        p_actor_user_id: authorization.actor.authUserId,
        p_actor_role: authorization.actor.role,
        p_action: accessAction,
        p_metadata: { source: "central_hq", route: "/api/sarca/trips/[tripId]" },
      }),
    });
    const start = String(trip.requested_at || trip.created_at || new Date(0).toISOString());
    const end = String(trip.completed_at || trip.cancelled_at || trip.updated_at || new Date().toISOString());
    const range = `&recorded_at=gte.${encodeURIComponent(start)}&recorded_at=lte.${encodeURIComponent(end)}`;
    const [driverRows, riderRows, routeRows, centralRouteRows, tripEvents, incidents, offers, accessAudit, driverProfiles, vehicles, financialReservations, financialOperations, tollReconciliations] = await Promise.all([
      platformRest("sarca", `driver_location_events?select=*&driver_user_id=eq.${encodeURIComponent(String(trip.driver_user_id || ""))}${range}&order=recorded_at.asc&limit=5000`).catch(() => []),
      platformRest("sarca", `rider_location_events?select=*&trip_id=eq.${encodeURIComponent(tripId)}${range}&order=recorded_at.asc&limit=5000`).catch(() => []),
      platformRest("sarca", `trip_route_points?trip_id=eq.${encodeURIComponent(tripId)}&select=*&order=recorded_at.asc,id.asc&limit=10000`).catch(() => []),
      hqRest(`sarca_trip_route_points?trip_id=eq.${encodeURIComponent(tripId)}&select=*&order=recorded_at.asc,id.asc&limit=10000`).catch(() => []),
      platformRest("sarca", `trip_events?trip_id=eq.${encodeURIComponent(tripId)}&select=id,actor_user_id,event_type,payload,created_at&order=created_at.asc&limit=1000`).catch(() => []),
      platformRest("sarca", `trip_incidents?trip_id=eq.${encodeURIComponent(tripId)}&select=*&order=created_at.asc&limit=500`).catch(() => []),
      platformRest("sarca", `trip_dispatch_offers?trip_id=eq.${encodeURIComponent(tripId)}&select=*&order=created_at.asc&limit=100`).catch(() => []),
      platformRest("sarca", `trip_access_audit?trip_id=eq.${encodeURIComponent(tripId)}&select=*&order=created_at.desc&limit=100`).catch(() => []),
      platformRest("sarca", `driver_profiles?user_id=eq.${encodeURIComponent(String(trip.driver_user_id || ""))}&select=*`).catch(() => []),
      platformRest("sarca", `vehicles?driver_user_id=eq.${encodeURIComponent(String(trip.driver_user_id || ""))}&select=*&order=updated_at.desc&limit=1`).catch(() => []),
      platformRest("sarca", `trip_financial_reservations?trip_id=eq.${encodeURIComponent(tripId)}&select=*&order=created_at.asc`).catch(() => []),
      platformRest("sarca", `trip_financial_operations?trip_id=eq.${encodeURIComponent(tripId)}&select=*&order=created_at.asc`).catch(() => []),
      platformRest("sarca", `trip_toll_reconciliations?trip_id=eq.${encodeURIComponent(tripId)}&select=*&order=created_at.asc`).catch(() => []),
    ]) as [Row[], Row[], Row[], Row[], Row[], Row[], Row[], Row[], Row[], Row[], Row[], Row[], Row[]];
    const centralPoints = ((centralRouteRows?.length ? centralRouteRows : routeRows) || []).map(row => validPoint(row, row.source === "rider" ? "rider" : "driver")).filter(Boolean) as Point[];
    const driverPoints = (driverRows || []).map(row => validPoint(row, "driver")).filter(Boolean) as Point[];
    const riderPoints = (riderRows || []).map(row => validPoint(row, "rider")).filter(Boolean) as Point[];
    const actual = centralPoints.length ? centralPoints : [...driverPoints, ...riderPoints].sort((a, b) => Date.parse(a.recordedAt) - Date.parse(b.recordedAt));
    const actualDriver = centralPoints.length ? centralPoints.filter(point => point.source === "driver") : driverPoints;
    const actualRider = centralPoints.length ? centralPoints.filter(point => point.source === "rider") : riderPoints;
    const actualDistance = actualDriver.slice(1).reduce((total, point, index) => total + distanceMeters(actualDriver[index], point), 0);
    const plannedRoute = trip.planned_route && typeof trip.planned_route === "object" ? trip.planned_route as Row : null;
    const plannedCoordinates = Array.isArray(plannedRoute?.coordinates) ? plannedRoute.coordinates : planned(trip);
    const identityIds = [String(trip.passenger_user_id || ""), String(trip.driver_user_id || "")].filter(Boolean);
    const identities = identityIds.length ? await stagingRest(`profiles?select=id,user_id,full_name,phone,avatar_url&or=(id.in.(${identityIds.join(",")}),user_id.in.(${identityIds.join(",")}))`).catch(() => []) as Row[] : [];
    const identityFor = (userId: unknown) => identities.find(row => String(row.id || row.user_id || "") === String(userId || "")) || null;
    const passenger = identityFor(trip.passenger_user_id);
    const driver = identityFor(trip.driver_user_id);
    const vehicle = vehicles[0] || null;
    const timeline = [
      ...(tripEvents || []).map(event => ({ at: event.created_at, type: event.event_type, actorUserId: event.actor_user_id, payload: event.payload })),
      ...(trip.requested_at ? [{ at: trip.requested_at, type: "trip_requested" }] : []),
      ...(trip.accepted_at ? [{ at: trip.accepted_at, type: "trip_accepted" }] : []),
      ...(trip.started_at ? [{ at: trip.started_at, type: "trip_started" }] : []),
      ...(trip.completed_at ? [{ at: trip.completed_at, type: "trip_completed" }] : []),
      ...(trip.cancelled_at ? [{ at: trip.cancelled_at, type: "trip_cancelled" }] : []),
    ].sort((a, b) => Date.parse(String(a.at || "")) - Date.parse(String(b.at || "")));
    const tripView = { ...trip, passengerName: passenger?.full_name || null, driverName: driver?.full_name || null, vehiclePlate: vehicle?.plate_number || null };
    return NextResponse.json({
      trip: tripView,
      identification: { tripId, passenger: { id: trip.passenger_user_id, name: passenger?.full_name || null, phone: passenger?.phone || null }, driver: { id: trip.driver_user_id, name: driver?.full_name || null, phone: driver?.phone || null }, vehicle: { id: trip.vehicle_id || vehicle?.id || null, make: vehicle?.make || null, model: vehicle?.model || null, color: vehicle?.color || null, plateNumber: vehicle?.plate_number || null } },
      locations: { pickup: { address: trip.pickup_address, latitude: trip.pickup_lat, longitude: trip.pickup_lng }, dropoff: { address: trip.dropoff_address, latitude: trip.dropoff_lat, longitude: trip.dropoff_lng }, stops: trip.intermediate_stops || [] },
      schedule: { requestedAt: trip.requested_at || trip.created_at, acceptedAt: trip.accepted_at || null, arrivedAt: timeline.find(item => item.type === "driver_arriving")?.at || null, startedAt: trip.started_at || null, completedAt: trip.completed_at || null, cancelledAt: trip.cancelled_at || null },
      route: { plannedCoordinates, actualCoordinates: actualDriver.map(point => [point.latitude, point.longitude]), riderCoordinates: actualRider.map(point => [point.latitude, point.longitude]), points: actual, segments: { toPickup: actualDriver.filter(point => point.segment === "to_pickup"), trip: actualDriver.filter(point => point.segment === "trip") }, distanceMeters: Math.round(actualDistance), durationSeconds: actualDriver.length > 1 ? Math.max(0, Math.round((Date.parse(actualDriver.at(-1)!.recordedAt) - Date.parse(actualDriver[0].recordedAt)) / 1000)) : 0, gaps: actualDriver.slice(1).filter((point, index) => Date.parse(point.recordedAt) - Date.parse(actualDriver[index].recordedAt) > 120000).map((point, index) => ({ from: actualDriver[index].recordedAt, to: point.recordedAt, seconds: Math.round((Date.parse(point.recordedAt) - Date.parse(actualDriver[index].recordedAt)) / 1000) })) },
      values: { currency: trip.currency_code || "MZN", estimatedFareMinor: trip.estimated_fare_minor || null, finalFareMinor: trip.final_fare_minor || null, commissionMinor: trip.commission_minor || null, driverNetMinor: trip.driver_net_minor || null, tollAmountMinor: trip.toll_amount_minor || 0, commissionableFareMinor: trip.commissionable_fare_minor || null, tollDetails: trip.toll_details || [], paymentMethod: trip.payment_method || null, paymentStatus: trip.payment_status || null, fundsStatus: trip.funds_status || null },
      financial: { reservations: financialReservations || [], operations: financialOperations || [], tollReconciliations: tollReconciliations || [] },
      occurrences: { timeline, incidents: incidents || [], dispatchOffers: offers || [] },
      audit: { access: accessAudit || [] },
      plannedCoordinates,
      actualCoordinates: actualDriver.map(point => [point.latitude, point.longitude]),
      riderCoordinates: actualRider.map(point => [point.latitude, point.longitude]),
      points: actual,
      telemetry: { available: actualDriver.length >= 2, pointCount: actual.length, driverPointCount: actualDriver.length, riderPointCount: actualRider.length, gaps: actualDriver.slice(1).filter((point, index) => Date.parse(point.recordedAt) - Date.parse(actualDriver[index].recordedAt) > 120000).length },
    }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    console.error("SARCA_TRIP_ROUTE_READ_FAILED", error instanceof Error ? error.message : "unknown");
    return NextResponse.json({ error: "Não foi possível ler a viagem ou a telemetria autorizada." }, { status: 502 });
  }
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ tripId: string }> }) {
  const configuredSecret = routeIngestionSecret();
  const suppliedSecret = request.headers.get("x-hq-route-ingestion-secret")?.trim() || "";
  if (!configuredSecret || !suppliedSecret || suppliedSecret !== configuredSecret) {
    return NextResponse.json({ error: "Ingestão de telemetria não autorizada." }, { status: 401 });
  }
  const tripId = tripIdFromRequest(request, await params);
  if (!/^[0-9a-f-]{36}$/i.test(tripId)) return NextResponse.json({ error: "ID de viagem inválido." }, { status: 400 });
  try {
    const body = await request.json() as { source?: unknown; points?: unknown };
    const source = body.source;
    const points = body.points;
    if (source !== "driver" && source !== "rider" && source !== "system") {
      return NextResponse.json({ error: "Fonte de telemetria inválida." }, { status: 400 });
    }
    if (!Array.isArray(points) || points.length === 0 || points.length > 5000) {
      return NextResponse.json({ error: "Envie entre 1 e 5000 posições GPS." }, { status: 400 });
    }
    const inserted = await hqRpc("record_sarca_trip_route_points", { p_trip_id: tripId, p_source: source, p_points: points }, "hq");
    return NextResponse.json({ ok: true, tripId, inserted: Number(inserted) || 0 }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("SARCA_TRIP_ROUTE_WRITE_FAILED", error instanceof Error ? error.message : "unknown");
    return NextResponse.json({ error: "Não foi possível guardar a telemetria da viagem." }, { status: 502 });
  }
}
