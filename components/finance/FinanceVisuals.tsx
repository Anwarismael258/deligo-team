"use client";

import type { ReactNode } from "react";

export type FinanceRevenueItem = {
  slug: string;
  label: string;
  value: number | null;
};

type FinanceKpiProps = {
  label: string;
  value: string;
  note: string;
  icon: ReactNode;
  tone: "cyan" | "violet" | "blue";
};

export function FinanceKpi({ label, value, note, icon, tone }: FinanceKpiProps) {
  return (
    <article className={`financeOverviewKpi financeOverviewKpi-${tone}`}>
      <div className="financeOverviewKpiIcon" aria-hidden="true">{icon}</div>
      <div className="financeOverviewKpiBody">
        <div className="financeOverviewKpiLabel"><span>{label}</span><span className="financeInfoHint" title={note} aria-label={`Informação: ${note}`}>i</span></div>
        <strong>{value}</strong>
        <small>{note}</small>
      </div>
    </article>
  );
}

type FinanceRevenueBarsProps = {
  items: FinanceRevenueItem[];
  formatValue: (value: number) => string;
};

export function FinanceRevenueBars({ items, formatValue }: FinanceRevenueBarsProps) {
  const available = items.map(item => item.value).filter((value): value is number => typeof value === "number" && Number.isFinite(value) && value >= 0);
  const maximum = Math.max(...available, 0);

  return (
    <section className="financeVisualCard financeRevenueChart" aria-labelledby="finance-revenue-title">
      <div className="financeVisualHeading">
        <div><span className="financeEyebrow">COMPARAÇÃO</span><h2 id="finance-revenue-title">Receita por plataforma</h2></div>
        <span className="financeChartLegend">Receita confirmada</span>
      </div>
      <div className="financeRevenueRows" role="list" aria-label="Receita confirmada por plataforma">
        {items.map(item => {
          const hasValue = typeof item.value === "number" && Number.isFinite(item.value);
          const width = hasValue && maximum > 0 ? Math.max(0, Math.min(100, (item.value! / maximum) * 100)) : 0;
          return (
            <div className="financeRevenueRow" role="listitem" key={item.slug} title={`${item.label}: ${hasValue ? formatValue(item.value!) : "Indisponível"}`}>
              <span className="financeRevenueLabel">{item.label}</span>
              <div className="financeRevenueTrack" aria-hidden="true"><span className="financeRevenueFill" style={{ width: `${width}%` }} /></div>
              <strong className={hasValue ? "" : "financeUnavailableValue"}>{hasValue ? formatValue(item.value!) : "Indisponível"}</strong>
            </div>
          );
        })}
      </div>
      <small className="financeChartFootnote">Valores de receita da Central confirmada. Carteiras de terceiros ficam separadas.</small>
    </section>
  );
}

type FinanceCustodyDonutProps = {
  centralRevenue: number | null;
  thirdPartyWallets: number | null;
  custodyTotal: number | null;
  formatValue: (value: number) => string;
};

export function FinanceCustodyDonut({ centralRevenue, thirdPartyWallets, custodyTotal, formatValue }: FinanceCustodyDonutProps) {
  const validNumbers = [centralRevenue, thirdPartyWallets, custodyTotal].every(value => typeof value === "number" && Number.isFinite(value) && value >= 0);
  const sum = validNumbers ? centralRevenue! + thirdPartyWallets! : null;
  const validComposition = validNumbers && custodyTotal! > 0 && Math.abs(sum! - custodyTotal!) <= 0.01;
  const centralPercent = validComposition ? (centralRevenue! / custodyTotal!) * 100 : 0;
  const walletPercent = validComposition ? 100 - centralPercent : 0;

  return (
    <section className="financeVisualCard financeCustodyChart" aria-labelledby="finance-custody-title">
      <div className="financeVisualHeading"><div><span className="financeEyebrow">COMPOSIÇÃO VALIDADA</span><h2 id="finance-custody-title">Composição sob custódia</h2></div></div>
      {validComposition ? <>
        <div className="financeDonutLayout">
          <div className="financeDonut" role="img" aria-label={`Custódia total ${formatValue(custodyTotal!)}`} style={{ background: `conic-gradient(#8B5CF6 0 ${centralPercent}%, #22D3EE ${centralPercent}% 100%)` }}>
            <div className="financeDonutHole"><span>Total</span><strong>{formatValue(custodyTotal!)}</strong></div>
          </div>
          <div className="financeDonutLegend">
            <div><span className="financeLegendDot financeLegendDot-violet" /><span>Receita da Central <small>{centralPercent.toFixed(2).replace(".", ",")}%</small></span><strong>{formatValue(centralRevenue!)}</strong></div>
            <div><span className="financeLegendDot financeLegendDot-cyan" /><span>Carteiras de terceiros <small>{walletPercent.toFixed(2).replace(".", ",")}%</small></span><strong>{formatValue(thirdPartyWallets!)}</strong></div>
          </div>
        </div>
        <p className="financeChartFootnote">Carteiras de terceiros não representam receita da empresa.</p>
      </> : <div className="financeChartEmpty">Composição indisponível sem valores do mesmo âmbito e momento.</div>}
    </section>
  );
}
