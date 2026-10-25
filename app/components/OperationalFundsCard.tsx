"use client";

import { useEffect, useState } from "react";

export function OperationalFundsCard({ role }: { role: string }) {
  const [value, setValue] = useState<number | null>(null);
  const [checkedAt, setCheckedAt] = useState("");
  useEffect(() => {
    let cancelled = false;
    let busy = false;
    const load = async () => {
      if (cancelled || busy) return;
      busy = true;
      try {
        const response = await fetch("/api/finance/operational-summary", { cache: "no-store" });
        if (!response.ok) return;
        const data = await response.json() as { available?: number; checkedAt?: string };
        if (!cancelled && typeof data.available === "number" && Number.isFinite(data.available)) { setValue(data.available); setCheckedAt(data.checkedAt || ""); }
      } finally { busy = false; }
    };
    void load();
    const timer = window.setInterval(() => void load(), 10_000);
    return () => { cancelled = true; window.clearInterval(timer); };
  }, [role]);
  if (value == null) return null;
  return <article className="analyticsKpiCard operationalFundsCard"><span>Total operacional</span><strong>{value.toLocaleString("pt-MZ", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} MT</strong><small>Carteiras autorizadas · sem receita corporativa{checkedAt ? ` · ${new Date(checkedAt).toLocaleTimeString("pt-MZ", { hour: "2-digit", minute: "2-digit" })}` : ""}</small></article>;
}
