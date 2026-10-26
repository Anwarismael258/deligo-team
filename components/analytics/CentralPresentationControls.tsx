"use client";

import { Maximize2, Minimize2, PauseCircle, PlayCircle } from "lucide-react";
import { useEffect, useState } from "react";

const STORAGE_KEY = "central-hq-motion-preference";

export function CentralPresentationControls() {
  const [reducedMotion, setReducedMotion] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);

  useEffect(() => {
    const saved = window.localStorage.getItem(STORAGE_KEY);
    const prefersReduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const next = saved === "reduced" || (!saved && prefersReduced);
    setReducedMotion(next);
    document.documentElement.dataset.centralMotion = next ? "reduced" : "normal";
    const onFullscreen = () => setFullscreen(Boolean(document.fullscreenElement));
    document.addEventListener("fullscreenchange", onFullscreen);
    return () => document.removeEventListener("fullscreenchange", onFullscreen);
  }, []);

  const toggleMotion = () => {
    const next = !reducedMotion;
    setReducedMotion(next);
    window.localStorage.setItem(STORAGE_KEY, next ? "reduced" : "normal");
    document.documentElement.dataset.centralMotion = next ? "reduced" : "normal";
  };

  const toggleFullscreen = async () => {
    if (document.fullscreenElement) {
      await document.exitFullscreen();
      return;
    }
    await document.documentElement.requestFullscreen?.();
  };

  return <div className="centralPresentationControls" aria-label="Apresentação da Central">
    <button type="button" onClick={toggleMotion} aria-pressed={reducedMotion} title={reducedMotion ? "Activar movimento suave" : "Reduzir movimento"}>
      {reducedMotion ? <PlayCircle size={14} aria-hidden="true" /> : <PauseCircle size={14} aria-hidden="true" />}
      <span>{reducedMotion ? "Movimento reduzido" : "Movimento normal"}</span>
    </button>
    <button type="button" onClick={() => void toggleFullscreen()} aria-pressed={fullscreen} title={fullscreen ? "Sair do ecrã inteiro" : "Abrir em ecrã inteiro"}>
      {fullscreen ? <Minimize2 size={14} aria-hidden="true" /> : <Maximize2 size={14} aria-hidden="true" />}
      <span>{fullscreen ? "Sair" : "Apresentar"}</span>
    </button>
  </div>;
}
