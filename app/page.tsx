"use client";

import { useMemo, useState } from "react";

const platforms = ["All Platforms", "DeliGo", "Comunhão", "TaoMoz", "SARCA"];
const nav = [
  ["⌂", "Overview"],
  ["◇", "Platforms"],
  ["♙", "People"],
  ["□", "Finance"],
  ["▦", "Accounting"],
  ["♧", "Human Resources"],
  ["§", "Legal"],
  ["↗", "Marketing"],
  ["◎", "Operations"],
  ["◌", "Support"],
  ["⌖", "Field"],
  ["＋", "Acquisition"],
  ["☆", "Ambassadors"],
  ["⌁", "Analytics"],
  ["▤", "Reports"],
];

const platformCards = [
  { name: "DeliGo", color: "#e53935", metrics: ["Users", "Orders", "Partners", "Revenue"] },
  { name: "Comunhão", color: "#7c5ce5", metrics: ["Churches", "Members", "Events", "Revenue"] },
  { name: "TaoMoz", color: "#129a72", metrics: ["Users", "Companies", "Transactions", "Revenue"] },
  { name: "SARCA", color: "#e69b22", metrics: ["Users", "Operations", "Transactions", "Revenue"] },
];

export default function Home() {
  const [platform, setPlatform] = useState("All Platforms");
  const [active, setActive] = useState("Overview");
  const [menuOpen, setMenuOpen] = useState(false);
  const [commandOpen, setCommandOpen] = useState(false);

  const visibleCards = useMemo(
    () => platform === "All Platforms" ? platformCards : platformCards.filter((item) => item.name === platform),
    [platform],
  );

  return (
    <main className="shell">
      <aside className={menuOpen ? "sidebar open" : "sidebar"}>
        <div className="brand">
          <div className="brandmark">D</div>
          <div><strong>DeliGo Triunfal</strong><span>Central Web</span></div>
        </div>
        <nav>
          <p className="navLabel">WORKSPACE</p>
          {nav.map(([icon, label]) => (
            <button key={label} className={active === label ? "navItem active" : "navItem"} onClick={() => { setActive(label); setMenuOpen(false); }}>
              <span>{icon}</span>{label}
            </button>
          ))}
          <p className="navLabel">SYSTEM</p>
          <button className="navItem"><span>♧</span>Security</button>
          <button className="navItem"><span>⚙</span>Settings</button>
        </nav>
        <div className="user">
          <div className="avatar">AA</div>
          <div><strong>Anwar Ismael</strong><span>Super Admin</span></div>
          <b>•••</b>
        </div>
      </aside>

      <section className="workspace">
        <header>
          <button className="menuButton" onClick={() => setMenuOpen(!menuOpen)}>☰</button>
          <button className="search" onClick={() => setCommandOpen(true)}>
            <span>⌕</span><span>Search anything…</span><kbd>⌘ K</kbd>
          </button>
          <div className="headerActions">
            <select aria-label="Current Platform" value={platform} onChange={(e) => setPlatform(e.target.value)}>
              {platforms.map((item) => <option key={item}>{item}</option>)}
            </select>
            <button className="iconButton" aria-label="Notifications">♢<i /></button>
            <div className="miniAvatar">AA</div>
          </div>
        </header>

        <div className="content">
          <div className="eyebrow"><span>HQ</span> / {active}</div>
          <div className="titleRow">
            <div>
              <h1>{active === "Overview" ? "Group overview" : active}</h1>
              <p>Consolidated operations across DeliGo Triunfal.</p>
            </div>
            <div className="live"><i /> Live systems</div>
          </div>

          <section className="metrics">
            {[
              ["Total users", "0", "Across accessible platforms"],
              ["Corporate revenue", "—", "Not connected to accounting"],
              ["Net profit", "—", "Never inferred from bank balance"],
              ["Active employees", "3", "Configured leadership"],
            ].map(([label, value, note], index) => (
              <article className="metric" key={label}>
                <div className={`metricIcon m${index}`}>{["♙", "↗", "⇄", "◎"][index]}</div>
                <p>{label}</p><strong>{value}</strong><span>{note}</span>
              </article>
            ))}
          </section>

          <div className="sectionHeading">
            <div><h2>Platform health</h2><p>Operational view by business platform</p></div>
            <button>View system health →</button>
          </div>
          <section className="platformGrid">
            {visibleCards.map((card) => (
              <article className="platformCard" key={card.name}>
                <div className="platformTop">
                  <div className="platformIdentity"><i style={{ background: card.color }}>{card.name.charAt(0)}</i><div><strong>{card.name}</strong><span>Awaiting connection</span></div></div>
                  <span className="status"><i /> Ready</span>
                </div>
                <div className="platformMetrics">
                  {card.metrics.map((metric) => <div key={metric}><span>{metric}</span><strong>{metric === "Revenue" ? "—" : "0"}</strong></div>)}
                </div>
                <button onClick={() => setPlatform(card.name)}>Open {card.name}<span>→</span></button>
              </article>
            ))}
          </section>

          <section className="governance">
            <div className="sectionHeading">
              <div><h2>Corporate controls</h2><p>Financial separation and governance safeguards</p></div>
              <span className="protected">● Protected workspace</span>
            </div>
            <div className="controlGrid">
              {[
                ["Corporate treasury", "—", "Company-owned cash only", "Bank, cash and obligations"],
                ["User wallets", "—", "Third-party money", "Excluded from revenue and profit"],
                ["Accounts payable", "—", "Pending obligations", "Suppliers, payroll and tax"],
                ["Distributable profit", "—", "Accounting approval required", "No automatic withdrawal"],
              ].map(([title, value, badge, note], index) => (
                <article className="controlCard" key={title}>
                  <div className={`controlGlyph c${index}`}>{["▣", "◫", "↘", "◈"][index]}</div>
                  <span>{title}</span><strong>{value}</strong><em>{badge}</em><small>{note}</small>
                </article>
              ))}
            </div>
          </section>

          <section className="workflowPanel">
            <div className="panelTitle">
              <div><h2>Profit distribution control</h2><p>Separation of duties — no single employee controls the full cycle</p></div>
              <span className="draftStatus">No active proposal</span>
            </div>
            <div className="workflow">
              {[
                ["1", "Accounting", "Prepare result"],
                ["2", "Finance", "Review"],
                ["3", "Shareholders", "Approve"],
                ["4", "Payment", "Bank instruction"],
                ["5", "Reconciliation", "Complete"],
              ].map(([number, title, text], index) => (
                <div className="workflowStep" key={title}>
                  <i>{number}</i><div><strong>{title}</strong><span>{text}</span></div>{index < 4 && <b>→</b>}
                </div>
              ))}
            </div>
          </section>

          <section className="lowerGrid">
            <article className="panel">
              <div className="panelTitle"><div><h2>Company structure</h2><p>Leadership and operational responsibility</p></div><button>Manage people</button></div>
              {[
                ["AA", "Anwar Abubacar Ismael", "CEO & Founder", "SUPER ADMIN", "50% ownership"],
                ["SI", "Sara Vitorino Feniosse Ismael", "Co-Founder · Finance & Management", "FINANCE · MANAGEMENT", "50% ownership"],
                ["SC", "Sansão Chume", "Operations Supervisor", "SUPERVISOR", "Operations"],
              ].map((person, index) => (
                <div className="person" key={person[1]}>
                  <div className={`personAvatar p${index}`}>{person[0]}</div>
                  <div className="personName"><strong>{person[1]}</strong><span>{person[2]}</span></div>
                  <span className="role">{person[3]}</span><span className="ownership">{person[4]}</span>
                </div>
              ))}
            </article>
            <article className="panel activity">
              <div className="panelTitle"><div><h2>Recent activity</h2><p>Audited actions across the group</p></div><button>View audit log</button></div>
              <div className="empty"><div>⌁</div><strong>No activity yet</strong><p>Events will appear when real services are connected.</p></div>
            </article>
          </section>
          <section className="departmentStrip">
            {[
              ["Accounting", "Chart of accounts · Reconciliation · Tax"],
              ["Human Resources", "Contracts · Leave · Payroll · Lifecycle"],
              ["Legal", "Corporate documents · Compliance · Contracts"],
              ["External collaborators", "Time-bound access · Revocation · Audit"],
            ].map(([title, text]) => <button key={title} onClick={() => setActive(title)}><strong>{title}</strong><span>{text}</span><b>→</b></button>)}
          </section>
          <footer><span>DeliGo Triunfal HQ</span><span>Central Management & Operations · Prepared for hq.deligo.co.mz</span></footer>
        </div>
      </section>

      {commandOpen && <div className="modal" onClick={() => setCommandOpen(false)}>
        <div className="command" onClick={(e) => e.stopPropagation()}>
          <input autoFocus placeholder="Search employees, platforms, tickets…" />
          <p>QUICK ACTIONS</p>
          {["Open Finance", "View employees", "Open reports", "System health"].map((item) => <button key={item} onClick={() => { setActive(item.replace("Open ", "").replace("View ", "")); setCommandOpen(false); }}>{item}<span>↵</span></button>)}
          <small>Search only returns items permitted by your role.</small>
        </div>
      </div>}
    </main>
  );
}
