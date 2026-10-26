"use client";

export type AnalyticsChartItem = { label: string; value: number };
export type AnalyticsSeriesItem = { date: string; value: number; secondary?: number };

const cyan = "#22d3ee";
const violet = "#8b5cf6";
const blue = "#3b82f6";
const red = "#f05b78";
const orange = "#f3b84b";
const axis = "#7392ad";
const grid = "#315174";
const text = "#d7e8f8";
const strongText = "#f5f9ff";
const palette = [cyan, violet, blue, "#4fd1a5", orange, red];
const formatNumber = (value: number) => value.toLocaleString("pt-MZ", Number.isInteger(value) ? { maximumFractionDigits: 0 } : { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const hasValues = (items: Array<{ value: number }> | undefined) => Boolean(items?.some(item => Number.isFinite(item.value)));

function ChartFrame({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="analyticsChartCanvas" aria-label={label} style={{ width: "100%", height: 240, minWidth: 0 }}>
    <svg viewBox="0 0 720 240" role="img" aria-label={label} preserveAspectRatio="none" width="100%" height="240">{children}</svg>
  </div>;
}

function unavailable(title: string) {
  return <ChartFrame label={title}>
    <line x1="54" x2="704" y1="208" y2="208" stroke={axis} />
    <line x1="54" x2="54" y1="32" y2="208" stroke={axis} />
    {[0, 1, 2, 3].map(step => <line key={step} x1="54" x2="704" y1={50 + step * 42} y2={50 + step * 42} stroke={grid} strokeDasharray="3 3" />)}
    <text x="379" y="116" textAnchor="middle" fill={text} fontSize="14" fontWeight="700">A aguardar dados confirmados</text>
    <text x="379" y="138" textAnchor="middle" fill={text} fontSize="11">O gráfico actualiza automaticamente quando a fonte responde</text>
  </ChartFrame>;
}

function Grid({ max, left = 54 }: { max: number; left?: number }) {
  return <g aria-hidden="true">{[0, 1, 2, 3, 4].map(step => {
    const y = 208 - step * 42;
    return <g key={step}><line x1={left} x2={704} y1={y} y2={y} stroke={grid} strokeDasharray="3 3" /><text x={left - 8} y={y + 4} textAnchor="end" fill={axis} fontSize="11">{formatNumber(max * step / 4)}</text></g>;
  })}</g>;
}

function labelDate(value: string) { return value.length > 10 ? value.slice(5, 10) : value; }

export function AnalyticsLineChart({ data, label = "Valor", secondaryLabel }: { data?: AnalyticsSeriesItem[]; label?: string; secondaryLabel?: string }) {
  if (!hasValues(data)) return unavailable("Série histórica indisponível");
  const items = data || [];
  const max = Math.max(1, ...items.flatMap(item => [item.value, item.secondary || 0]));
  const x = (index: number) => 54 + (index * 650) / Math.max(1, items.length - 1);
  const y = (value: number) => 208 - (value / max) * 168;
  const points = (key: "value" | "secondary") => items.map((item, index) => `${x(index)},${y(Number(item[key] || 0))}`).join(" ");
  const labelStep = Math.max(1, Math.ceil(items.length / 7));
  return <ChartFrame label={label}><Grid max={max} /><line x1="54" x2="704" y1="208" y2="208" stroke={axis} /><polyline className="analyticsLineSeries" points={points("value")} fill="none" stroke={cyan} strokeWidth="3" strokeLinejoin="round" strokeLinecap="round" />{items.map((item, index) => <circle className="analyticsLinePoint" key={`${item.date}-${index}`} cx={x(index)} cy={y(item.value)} r="3" fill={cyan} stroke="#0b1d31" strokeWidth="1.5"><title>{`${item.date}: ${formatNumber(item.value)}`}</title></circle>)}{secondaryLabel && <polyline className="analyticsLineSeries analyticsLineSeriesSecondary" points={points("secondary")} fill="none" stroke={violet} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" />}{items.map((item, index) => (index % labelStep === 0 || index === items.length - 1) && <text key={`label-${item.date}-${index}`} x={x(index)} y="230" textAnchor="middle" fill={text} fontSize="10"><title>{item.date}</title>{labelDate(item.date)}</text>)}</ChartFrame>;
}

export function AnalyticsBarChart({ data, label = "Total" }: { data?: AnalyticsChartItem[]; label?: string }) {
  if (!hasValues(data)) return unavailable("Distribuição indisponível");
  const items = data || [];
  const max = Math.max(1, ...items.map(item => item.value));
  const slot = 650 / Math.max(1, items.length);
  const barWidth = Math.max(18, Math.min(72, slot * 0.62));
  return <ChartFrame label={label}><defs><linearGradient id="analyticsBarGradient" x1="0" x2="1"><stop offset="0%" stopColor={cyan} /><stop offset="100%" stopColor={violet} /></linearGradient></defs><Grid max={max} /><line x1="54" x2="704" y1="208" y2="208" stroke={axis} />{items.map((item, index) => { const height = Math.max(2, (item.value / max) * 168); const center = 54 + slot * index + slot / 2; return <g className="analyticsBarGroup" style={{ animationDelay: `${index * 45}ms` }} key={`${item.label}-${index}`}><rect x={center - barWidth / 2} y={208 - height} width={barWidth} height={height} rx="5" fill="url(#analyticsBarGradient)" opacity={item.value === 0 ? .32 : 1}><title>{`${item.label}: ${formatNumber(item.value)}`}</title></rect><text x={center} y="224" textAnchor="middle" fill={text} fontSize="10"><title>{item.label}</title>{item.label.length > 14 ? `${item.label.slice(0, 12)}…` : item.label}</text><text x={center} y={Math.max(198 - height, 18)} textAnchor="middle" fill={strongText} fontSize="10" fontWeight="700">{formatNumber(item.value)}</text></g>; })}</ChartFrame>;
}

export function AnalyticsHorizontalBarChart({ data, label = "Total" }: { data?: AnalyticsChartItem[]; label?: string }) {
  if (!hasValues(data)) return unavailable("Distribuição indisponível");
  const items = (data || []).slice(0, 8);
  const max = Math.max(1, ...items.map(item => item.value));
  const rowHeight = 24;
  return <ChartFrame label={label}><defs><linearGradient id="analyticsHorizontalGradient" x1="0" x2="1"><stop offset="0%" stopColor={cyan} /><stop offset="100%" stopColor={violet} /></linearGradient></defs><g aria-hidden="true">{items.map((item, index) => { const y = 20 + index * rowHeight; const width = Math.max(item.value === 0 ? 0 : 4, (item.value / max) * 470); const itemText = item.label.length > 25 ? `${item.label.slice(0, 23)}…` : item.label; return <g className="analyticsBarGroup" style={{ animationDelay: `${index * 45}ms` }} key={`${item.label}-${index}`}><text x="8" y={y + 13} fill={text} fontSize="10"><title>{item.label}</title>{itemText}</text><rect x="205" y={y} width="470" height="14" rx="5" fill="#142f4c" /><rect x="205" y={y} width={width} height="14" rx="5" fill="url(#analyticsHorizontalGradient)" opacity={item.value === 0 ? .32 : 1}><title>{`${item.label}: ${formatNumber(item.value)}`}</title></rect><text x="684" y={y + 11} textAnchor="end" fill={strongText} fontSize="10" fontWeight="700">{formatNumber(item.value)}</text></g>; })}</g></ChartFrame>;
}

export function AnalyticsDonutChart({ data }: { data?: AnalyticsChartItem[] }) {
  if (!hasValues(data)) return unavailable("Distribuição indisponível");
  const items = data || [];
  const total = items.reduce((sum, item) => sum + Math.max(0, item.value), 0) || 1;
  const circumference = 2 * Math.PI * 66;
  return <ChartFrame label="Distribuição"><g transform="translate(185 120) rotate(-90)"><circle r="66" fill="none" stroke="#142f4c" strokeWidth="30" />{items.map((item, index) => { const length = (Math.max(0, item.value) / total) * circumference; const offset = items.slice(0, index).reduce((sum, previous) => sum + (Math.max(0, previous.value) / total) * circumference, 0); return <circle className="analyticsDonutSegment" key={`${item.label}-${index}`} r="66" fill="none" stroke={palette[index % palette.length]} strokeWidth="30" strokeDasharray={`${length} ${circumference - length}`} strokeDashoffset={-offset}><title>{`${item.label}: ${formatNumber(item.value)}`}</title></circle>; })}</g><text x="185" y="116" textAnchor="middle" fill={strongText} fontSize="18" fontWeight="700">{formatNumber(total)}</text><text x="185" y="133" textAnchor="middle" fill={axis} fontSize="10">Total</text>{items.slice(0, 6).map((item, index) => <g key={`legend-${item.label}-${index}`} transform={`translate(320 ${45 + index * 28})`}><rect width="12" height="12" rx="3" fill={palette[index % palette.length]} /><text x="20" y="10" fill={text} fontSize="11"><title>{item.label}</title>{item.label.length > 28 ? `${item.label.slice(0, 26)}…` : item.label}</text><text x="350" y="10" textAnchor="end" fill={strongText} fontSize="11" fontWeight="700">{formatNumber(item.value)}</text></g>)}</ChartFrame>;
}
