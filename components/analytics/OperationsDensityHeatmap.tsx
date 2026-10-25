"use client";

import { useEffect, useMemo, useRef } from "react";
import type { OperationsMapMarker } from "@/components/LiveOperationsMap";

export function OperationsDensityHeatmap({ markers }: { markers: OperationsMapMarker[] }) {
  const container = useRef<HTMLDivElement | null>(null);
  const points = useMemo(() => {
    const valid = markers.filter((marker) => Number.isFinite(marker.latitude) && Number.isFinite(marker.longitude));
    if (!valid.length) return null;
    const minLat = Math.min(...valid.map((marker) => marker.latitude));
    const maxLat = Math.max(...valid.map((marker) => marker.latitude));
    const minLng = Math.min(...valid.map((marker) => marker.longitude));
    const maxLng = Math.max(...valid.map((marker) => marker.longitude));
    const latSpan = Math.max(maxLat - minLat, 0.002);
    const lngSpan = Math.max(maxLng - minLng, 0.002);
    const columns = Array.from({ length: 12 }, (_, index) => `${(minLng + ((index + 0.5) / 12) * lngSpan).toFixed(3)}`);
    const rows = Array.from({ length: 8 }, (_, index) => `${(maxLat - ((index + 0.5) / 8) * latSpan).toFixed(3)}`);
    const counts = new Map<string, number>();
    const icons: Array<{ value: [number, number]; role: string; platform: string }> = [];
    valid.forEach((marker) => {
      const column = Math.min(11, Math.max(0, Math.floor(((marker.longitude - minLng) / lngSpan) * 12)));
      const row = Math.min(7, Math.max(0, Math.floor(((maxLat - marker.latitude) / latSpan) * 8)));
      const key = `${column}:${row}`;
      counts.set(key, (counts.get(key) || 0) + 1);
      icons.push({ value: [column, row], role: marker.role, platform: marker.platform });
    });
    return { columns, rows, data: Array.from(counts.entries()).map(([key, value]) => { const [column, row] = key.split(":").map(Number); return [column, row, value]; }), icons };
  }, [markers]);

  useEffect(() => {
    if (!container.current || !points) return;
    let disposed = false;
    let chart: { setOption: (option: unknown) => void; resize: () => void; dispose: () => void } | null = null;
    const resize = () => chart?.resize();
    void import("echarts").then((echarts) => {
      if (disposed || !container.current) return;
      const instance = echarts.init(container.current);
      chart = instance;
      instance.setOption({
        animation: false,
        grid: { top: 8, right: 12, bottom: 42, left: 48 },
        tooltip: { formatter: (params: { value?: [number, number, number]; role?: string; platform?: string }) => params.role ? `${params.role} · ${params.platform || ""}` : params.value ? `Posições: ${params.value[2]}` : "Posições" },
        xAxis: { type: "category", data: points.columns, name: "longitude", nameLocation: "middle", nameGap: 28, axisLabel: { fontSize: 9 }, splitArea: { show: true } },
        yAxis: { type: "category", data: points.rows, name: "latitude", nameLocation: "middle", nameGap: 34, axisLabel: { fontSize: 9 }, splitArea: { show: true } },
        visualMap: { min: 0, max: Math.max(1, ...points.data.map((item) => item[2])), calculable: false, orient: "horizontal", left: "center", bottom: 0, itemWidth: 120, textStyle: { fontSize: 9 }, inRange: { color: ["#fff4e8", "#f6a24c", "#c5223b"] } },
        series: [
          { type: "heatmap", data: points.data, emphasis: { itemStyle: { shadowBlur: 10, shadowColor: "rgba(0,0,0,.25)" } } },
          {
            type: "scatter",
            data: points.icons,
            symbolSize: 22,
            encode: { x: 0, y: 1 },
            itemStyle: { color: "#111827", borderColor: "#ffffff", borderWidth: 1 },
            label: { show: true, position: "inside", color: "#ffffff", fontSize: 13, formatter: (params: { data?: { role?: string } }) => { const role = String(params.data?.role || "").toLowerCase(); return role.includes("restaurante") ? "🍽" : role.includes("cliente") ? "●" : role.includes("pedido") ? "▣" : "🏍"; } },
            tooltip: { formatter: (params: { data?: { role?: string; platform?: string } }) => params.data ? `${params.data.role || "Posição"} · ${params.data.platform || ""}` : "Posição" },
          },
        ],
      });
      window.addEventListener("resize", resize);
    });
    return () => { disposed = true; window.removeEventListener("resize", resize); chart?.dispose(); chart = null; };
  }, [points]);

  if (!points) return <p className="analyticsDataNote">Sem coordenadas atuais verificáveis para calcular a densidade.</p>;
  return <div><div ref={container} className="operationsHeatmap" aria-label="Densidade de posições operacionais atuais" /><p className="analyticsDataNote operationsHeatmapLegend">🏍 Estafeta/driver · 🍽 Restaurante · ▣ Pedido · ● Cliente</p></div>;
}
