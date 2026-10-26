"use client";

import { useEffect, useRef, useState } from "react";
import type { LatLngTuple, LayerGroup, Map as LeafletMap } from "leaflet";
import "leaflet/dist/leaflet.css";

export type OperationsMapMarker = {
  id: string;
  platform: string;
  role: string;
  workerId?: string;
  workerName?: string;
  status?: "disponivel" | "ocupado" | "offline" | "em_servico";
  service?: string;
  latitude: number;
  longitude: number;
  updatedAt: string;
};

export type OperationsMapRoute = {
  id: string;
  platform: string;
  label: string;
  coordinates: LatLngTuple[];
  updatedAt: string;
};

type MapSelection = { kind: "marker" | "route"; id: string };

export default function LiveOperationsMap({ markers, routes = [], onSelect }: { markers: OperationsMapMarker[]; routes?: OperationsMapRoute[]; onSelect?: (selection: MapSelection) => void }) {
  const container = useRef<HTMLDivElement | null>(null);
  const map = useRef<LeafletMap | null>(null);
  const markerLayer = useRef<LayerGroup | null>(null);
  const [mapReady, setMapReady] = useState(false);

  useEffect(() => {
    if (!container.current || map.current) return;
    let disposed = false;
    let instance: LeafletMap | null = null;
    void import("leaflet").then((L) => {
      if (disposed || !container.current) return;
      instance = L.map(container.current, { zoomControl: false, attributionControl: true }).setView([-25.965, 32.575], 13);
      L.control.zoom({ position: "topright" }).addTo(instance);
      L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", {
        maxZoom: 19,
        attribution: "© OpenStreetMap contributors © CARTO",
      }).addTo(instance);
      map.current = instance;
      markerLayer.current = L.layerGroup().addTo(instance);
      setMapReady(true);
    });
    return () => { disposed = true; instance?.remove(); map.current = null; markerLayer.current = null; };
  }, []);

  useEffect(() => {
    const instance = map.current;
    const layer = markerLayer.current;
    if (!instance || !layer || !mapReady) return;
    let disposed = false;
    void import("leaflet").then((L) => {
      if (disposed || !map.current || !markerLayer.current) return;
      markerLayer.current.clearLayers();
      const points: LatLngTuple[] = [];
      routes.forEach((route) => {
        const color = route.platform === "SARCA" ? "#f97316" : "#dc2626";
        L.polyline(route.coordinates, { color, weight: 4, opacity: 0.9, dashArray: "8 7" })
          .bindTooltip(route.label, { sticky: true })
          .on("click", () => onSelect?.({ kind: "route", id: route.id }))
          .addTo(markerLayer.current!);
        route.coordinates.forEach((point) => points.push(point));
      });
      markers.forEach((marker) => {
      const colorClass = marker.platform.toLowerCase().replace(/[^a-z0-9]+/g, "-");
      const roleClass = marker.role.toLowerCase().replace(/[^a-z0-9]+/g, "-");
      const icon = L.divIcon({ className: "", html: `<span class="operations-map-pin ${colorClass} ${roleClass}" aria-label="${marker.role} ${marker.platform}"></span>`, iconSize: [30, 30], iconAnchor: [15, 15] });
        L.marker([marker.latitude, marker.longitude], { icon, title: `${marker.role} · ${marker.platform}` })
          .bindTooltip(`${marker.role} · ${marker.platform}`, { direction: "top", offset: [0, -10] })
          .on("click", () => onSelect?.({ kind: "marker", id: marker.id }))
          .addTo(markerLayer.current!);
        points.push([marker.latitude, marker.longitude]);
      });
      if (points.length === 1) map.current.setView(points[0], Math.max(map.current.getZoom(), 15));
      if (points.length > 1) map.current.fitBounds(points, { padding: [30, 30], maxZoom: 15 });
    });
    return () => { disposed = true; };
  }, [markers, routes, mapReady, onSelect]);

  return <div ref={container} className="operationsMap" aria-label="Mapa operacional em tempo real" />;
}
