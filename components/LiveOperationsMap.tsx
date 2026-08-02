"use client";

import { useEffect, useRef, useState } from "react";
import type { LatLngExpression, LayerGroup, Map as LeafletMap } from "leaflet";
import "leaflet/dist/leaflet.css";

export type OperationsMapMarker = {
  id: string;
  platform: "DeliGo" | "SARCA" | "TaoMoz";
  role: string;
  latitude: number;
  longitude: number;
  updatedAt: string;
};

export default function LiveOperationsMap({ markers }: { markers: OperationsMapMarker[] }) {
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
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: "© OpenStreetMap contributors",
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
      const points: LatLngExpression[] = [];
      markers.forEach((marker) => {
      const colorClass = marker.platform.toLowerCase();
      const icon = L.divIcon({ className: "", html: `<span class="operations-map-pin ${colorClass}" aria-label="${marker.role} ${marker.platform}"></span>`, iconSize: [20, 20], iconAnchor: [10, 10] });
        L.marker([marker.latitude, marker.longitude], { icon, title: `${marker.role} · ${marker.platform}` })
          .bindTooltip(`${marker.role} · ${marker.platform}`, { direction: "top", offset: [0, -10] })
          .addTo(markerLayer.current!);
        points.push([marker.latitude, marker.longitude]);
      });
      if (points.length === 1) map.current.setView(points[0], Math.max(map.current.getZoom(), 15));
      if (points.length > 1) map.current.fitBounds(points, { padding: [30, 30], maxZoom: 15 });
    });
    return () => { disposed = true; };
  }, [markers, mapReady]);

  return <div ref={container} className="operationsMap" aria-label="Mapa operacional em tempo real" />;
}
