"use client";

import { useEffect, useRef, useState } from "react";
import type { LatLngTuple, LayerGroup, Map as LeafletMap } from "leaflet";
import { clusterMapMarkers, escapeMapText, mapColor, markerGlyph, markerName } from "@/lib/map-presentation";
import "leaflet/dist/leaflet.css";
import styles from "./LiveOperationsMap.module.css";

export type OperationsMapMarker = {
  id: string; platform: string; role: string; workerId?: string; workerName?: string;
  status?: "disponivel" | "ocupado" | "offline" | "em_servico";
  service?: string; latitude: number; longitude: number; updatedAt: string;
  origin?: string; destination?: string; operationStatus?: string; operationId?: string; locationKind?: "gps" | "endpoint" | "place";
};
export type OperationsMapRoute = {
  id: string; platform: string; label: string; coordinates: LatLngTuple[]; updatedAt: string;
  origin?: string; destination?: string; workerId?: string; workerName?: string; operationStatus?: string;
};
export type MapSelection = { kind: "marker" | "route"; id: string };

type Props = { markers: OperationsMapMarker[]; routes?: OperationsMapRoute[]; onSelect?: (selection: MapSelection) => void; selected?: MapSelection | null; following?: boolean; followId?: string; recenterKey?: number };
export default function LiveOperationsMap({ markers, routes = [], onSelect, selected, following = false, followId, recenterKey = 0 }: Props) {
  const container = useRef<HTMLDivElement | null>(null);
  const map = useRef<LeafletMap | null>(null);
  const layer = useRef<LayerGroup | null>(null);
  const fitted = useRef(false);
  const lastSelection = useRef("");
  const onSelectRef = useRef(onSelect); onSelectRef.current = onSelect;
  const [ready, setReady] = useState(false);
  const [zoom, setZoom] = useState(13);

  useEffect(() => {
    if (!container.current) return;
    let disposed = false;
    let instance: LeafletMap | null = null;
    let resize: ResizeObserver | null = null;
    void import("leaflet").then(L => {
      if (disposed || !container.current) return;
      instance = L.map(container.current, { zoomControl: false }).setView([-25.965, 32.575], 13);
      L.control.zoom({ position: "topright" }).addTo(instance);
      const mapboxToken = process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN || process.env.NEXT_PUBLIC_MAPBOX_TOKEN;
      const fallback = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
      const osmAttribution = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';
      const addBase = (useMapbox: boolean) => {
        if (!instance) return;
        container.current?.classList.toggle(styles.osmTiles, !useMapbox);
        const tiles = useMapbox ? `https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}?access_token=${encodeURIComponent(mapboxToken!)}` : fallback;
        const base = L.tileLayer(tiles, { maxZoom: 19, updateWhenIdle: true, keepBuffer: 1, attribution: useMapbox ? `© Mapbox ${osmAttribution}` : osmAttribution }).addTo(instance);
        if (useMapbox) base.once("tileerror", () => { if (!disposed && instance) { instance.removeLayer(base); addBase(false); } });
      };
      addBase(Boolean(mapboxToken?.trim()));
      instance.on("zoomend", () => { if (instance) setZoom(instance.getZoom()); });
      map.current = instance;
      layer.current = L.layerGroup().addTo(instance);
      resize = new ResizeObserver(() => instance?.invalidateSize({ pan: false }));
      resize.observe(container.current);
      setReady(true);
    });
    return () => { disposed = true; resize?.disconnect(); instance?.remove(); map.current = null; layer.current = null; fitted.current = false; };
  }, []);

  useEffect(() => {
    if (!ready || !map.current || !layer.current) return;
    let disposed = false;
    void import("leaflet").then(L => {
      const instance = map.current;
      const group = layer.current;
      if (disposed || !instance || !group) return;
      group.clearLayers();
      const points: LatLngTuple[] = [];
      for (const route of routes) {
        if (route.coordinates.length < 2) continue;
        const tooltip = document.createElement("span");
        tooltip.textContent = `${route.label} · ${route.coordinates.length === 2 ? "Origem e destino" : "Pontos registados"}`;
        L.polyline(route.coordinates, { color: mapColor(route.platform), weight: selected?.id === route.id ? 6 : 3, opacity: .8, dashArray: route.coordinates.length === 2 ? "6 8" : undefined })
          .bindTooltip(tooltip).on("click", () => onSelectRef.current?.({ kind: "route", id: route.id })).addTo(group);
        points.push(...route.coordinates);
      }
      const clusters = zoom >= 17 ? markers.map(marker => [marker]) : clusterMapMarkers(markers, marker => instance.project([marker.latitude, marker.longitude], zoom));
      for (const cluster of clusters) {
        if (cluster.length === 1 || cluster.some(marker => selected?.id === marker.id)) continue;
        const bounds = L.latLngBounds(cluster.map(marker => [marker.latitude, marker.longitude] as LatLngTuple));
        const tooltip = document.createElement("span");tooltip.textContent = cluster.slice(0, 8).map(markerName).join("\n");
        const icon = L.divIcon({ className: "", html: `<span class="${styles.glyph}" style="--pin-color:#22d3ee">${cluster.length}</span>`, iconSize: [34,34], iconAnchor: [17,17] });
        L.marker(bounds.getCenter(), { icon, title: `${cluster.length} entidades` }).bindTooltip(tooltip).on("click", () => instance.fitBounds(bounds, { padding: [40,40], maxZoom: Math.min(18, zoom + 3) })).addTo(group);
      }
      const shownMarkers = clusters.flatMap(cluster => cluster.length === 1 || cluster.some(marker => selected?.id === marker.id) ? cluster : []);
      for (const marker of shownMarkers) {
        const name = markerName(marker);
        const html = `<span class="${styles.pin} ${selected?.id === marker.id ? styles.selected : ""}" style="--pin-color:${mapColor(marker.platform)}"><span class="${styles.glyph}">${markerGlyph(marker.role, marker.platform)}</span><span class="${styles.name}">${escapeMapText(name)}</span></span>`;
        const tooltip = document.createElement("span");
        tooltip.textContent = `${name}\n${marker.role} · ${marker.platform}\n${marker.locationKind === "gps" || !marker.locationKind ? "Última posição" : "Registado"}: ${new Date(marker.updatedAt).toLocaleString("pt-MZ")}`;
        const icon = L.divIcon({ className: "", html, iconSize: [34, 34], iconAnchor: [17, 17] });
        L.marker([marker.latitude, marker.longitude], { icon, title: `${name} · ${marker.role}`, keyboard: true, zIndexOffset: selected?.id === marker.id ? 1000 : 0 })
          .bindTooltip(tooltip, { direction: "top", offset: [0, -20] }).on("click", () => onSelectRef.current?.({ kind: "marker", id: marker.id })).addTo(group);
        points.push([marker.latitude, marker.longitude]);
      }
      if (markers.length) points.push(...markers.map(marker => [marker.latitude, marker.longitude] as LatLngTuple));
      if (!fitted.current && points.length) { instance.fitBounds(L.latLngBounds(points), { padding: [45, 45], maxZoom: 15 }); fitted.current = true; }
      const selectionKey = selected ? `${selected.kind}:${selected.id}` : "";
      const marker = following && followId ? markers.find(item => item.id === followId) : selected?.kind === "marker" ? markers.find(item => item.id === selected.id) : undefined;
      const route = selected?.kind === "route" ? routes.find(item => item.id === selected.id) : undefined;
      if (marker && (following || selectionKey !== lastSelection.current)) instance.panTo([marker.latitude, marker.longitude], { animate: true, duration: .5 });
      if (route && selectionKey !== lastSelection.current) instance.fitBounds(L.latLngBounds(route.coordinates), { padding: [50, 50], maxZoom: 16 });
      lastSelection.current = selectionKey;
    });
    return () => { disposed = true; };
  }, [markers, routes, ready, selected, following, followId, zoom]);

  useEffect(() => {
    if (!recenterKey || !map.current || !markers.length) return;
    void import("leaflet").then(L => map.current?.fitBounds(L.latLngBounds(markers.map(marker => [marker.latitude, marker.longitude] as LatLngTuple)), { padding: [45, 45], maxZoom: 15 }));
  }, [recenterKey]);
  return <div ref={container} className={`operationsMap ${styles.map}`} aria-label="Mapa operacional com nomes e posições registadas" />;
}
