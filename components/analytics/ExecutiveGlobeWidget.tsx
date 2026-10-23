export function ExecutiveGlobeWidget() {
  return <div className="executiveGlobeWidget" role="img" aria-label="Supervisão visual do ecossistema DeliGo Triunfal; sem dados operacionais">
    <span className="executiveGlobeGlow" />
    <svg viewBox="0 0 120 88" aria-hidden="true" focusable="false">
      <defs>
        <radialGradient id="executive-globe-fill" cx="35%" cy="28%" r="75%"><stop offset="0" stopColor="#ff8a58" stopOpacity=".36" /><stop offset=".62" stopColor="#c5223b" stopOpacity=".18" /><stop offset="1" stopColor="#240d24" stopOpacity=".08" /></radialGradient>
        <clipPath id="executive-globe-clip"><circle cx="60" cy="44" r="31" /></clipPath>
      </defs>
      <circle cx="60" cy="44" r="31" fill="url(#executive-globe-fill)" stroke="#ff7651" strokeOpacity=".78" />
      <g clipPath="url(#executive-globe-clip)" fill="none" strokeLinecap="round">
        <ellipse cx="60" cy="44" rx="31" ry="12" stroke="#ff684f" strokeOpacity=".72" />
        <ellipse cx="60" cy="44" rx="31" ry="22" stroke="#e33a50" strokeOpacity=".55" />
        <ellipse cx="60" cy="44" rx="12" ry="31" stroke="#ff9a55" strokeOpacity=".65" />
        <ellipse cx="60" cy="44" rx="23" ry="31" stroke="#d72d48" strokeOpacity=".65" />
        <path d="M26 47c14-8 23 5 34-2 12-8 18 3 35-7M28 59c13-5 21 5 31 0 12-6 21 2 31-3M31 31c12 5 17-4 29 2 10 5 18-3 29 2" stroke="#ff694f" strokeOpacity=".64" />
      </g>
      <circle cx="60" cy="44" r="34" fill="none" stroke="#ff6e4f" strokeOpacity=".16" strokeDasharray="2 5" className="executiveGlobeOrbit" />
      <circle cx="84" cy="26" r="2" fill="#ffb05c" className="executiveGlobePulse" />
    </svg>
    <small>HQ · supervisão</small>
  </div>;
}
