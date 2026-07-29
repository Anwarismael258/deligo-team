"use client";

import { useMemo, useState } from "react";

const platforms = ["Todas as plataformas", "DeliGo", "Comunhão", "TaoMoz", "SARCA"];
const nav = [
  ["⌂", "Visão geral"],
  ["◇", "Plataformas"],
  ["♛", "Direcção Executiva"],
  ["♙", "Pessoas"],
  ["♧", "Recursos Humanos"],
  ["□", "Finanças"],
  ["▦", "Contabilidade"],
  ["§", "Jurídico"],
  ["⚑", "Conformidade e Risco"],
  ["⌘", "Tecnologia / IT"],
  ["▧", "Compras"],
  ["▣", "Património"],
  ["↗", "Marketing"],
  ["⌖", "Field"],
  ["◌", "Apoio ao Cliente"],
  ["＋", "Aquisição de Parceiros"],
  ["☆", "Embaixadores"],
  ["✓", "Projectos e Tarefas"],
  ["?", "Apoio Interno"],
  ["●", "Aprovações"],
  ["⌁", "BI / Análises"],
  ["▤", "Relatórios"],
  ["◎", "Registo de Auditoria"],
];

const moduleDetails: Record<string, string[]> = {
  "Plataformas": ["DeliGo", "Comunhão", "TaoMoz", "SARCA"],
  "Direcção Executiva": ["Perfil da empresa", "Sócios", "Deliberações", "Gestão corporativa"],
  "Pessoas": ["Trabalhadores", "Colaboradores externos", "Departamentos", "Roles e permissões"],
  "Recursos Humanos": ["Contratos", "Presenças", "Férias", "Payroll", "Onboarding e Offboarding"],
  "Finanças": ["Tesouraria", "Contas bancárias", "Receitas e despesas", "Orçamentos", "Distribuição de lucros"],
  "Contabilidade": ["Plano de contas", "Lançamentos", "Reconciliação", "Impostos", "Demonstrações"],
  "Jurídico": ["Contratos", "Documentos societários", "Licenças", "Políticas", "Processos"],
  "Conformidade e Risco": ["Riscos", "Controlos", "Incidentes", "Revisões", "Políticas"],
  "Tecnologia / IT": ["Sistemas e APIs", "Bases de dados", "Integrações", "Backups", "Incidentes técnicos"],
  "Compras": ["Pedidos de compra", "Aprovações", "Fornecedores", "Facturas", "Pagamentos"],
  "Património": ["Equipamentos", "Atribuições", "Manutenção", "Devoluções", "Inventário"],
  "Marketing": ["Campanhas", "Conteúdos", "Promoções", "Leads", "Análises"],
  "Field": ["Tarefas", "Visitas", "Verificações", "Localização", "Relatórios"],
  "Apoio ao Cliente": ["Tickets", "Chat", "Reclamações", "Incidentes", "Histórico"],
  "Aquisição de Parceiros": ["Leads", "Visitas", "Negociações", "Parceiros", "Objectivos"],
  "Embaixadores": ["Embaixadores", "Referências", "Campanhas", "Conversões", "Comissões"],
  "Projectos e Tarefas": ["Projectos", "Tarefas", "Objectivos", "Prazos", "Progresso"],
  "Apoio Interno": ["IT", "RH", "Finanças", "Jurídico", "Operações"],
  "Aprovações": ["Finanças", "RH", "Jurídico", "Compras", "Marketing"],
  "BI / Análises": ["Crescimento", "Receita", "Despesas", "Performance", "KPIs"],
  "Relatórios": ["Corporativos", "Financeiros", "RH", "Operações", "Auditoria"],
  "Registo de Auditoria": ["Actividade", "Logins", "Segurança", "Alterações", "Exportações"],
};

const personas = {
  anwar: {
    name: "Anwar Ismael",
    role: "Super Administrador",
    initials: "AA",
    modules: nav.map(([, label]) => label),
  },
  sara: {
    name: "Sara Ismael",
    role: "Finanças e Gestão",
    initials: "SI",
    modules: ["Visão geral", "Direcção Executiva", "Finanças", "Contabilidade", "Aprovações", "BI / Análises", "Relatórios"],
  },
  sansao: {
    name: "Sansão Chume",
    role: "Supervisor de Operações",
    initials: "SC",
    modules: ["Visão geral", "Pessoas", "Marketing", "Field", "Apoio ao Cliente", "Aquisição de Parceiros", "Embaixadores", "Projectos e Tarefas", "BI / Análises", "Relatórios"],
  },
  contabilista: {
    name: "Contabilista",
    role: "Contabilidade",
    initials: "CT",
    modules: ["Visão geral", "Finanças", "Contabilidade", "Compras", "Aprovações", "Relatórios"],
  },
  tecnologia: {
    name: "Técnico IT",
    role: "Tecnologia",
    initials: "IT",
    modules: ["Visão geral", "Plataformas", "Tecnologia / IT", "Património", "Projectos e Tarefas", "Apoio Interno", "Relatórios", "Registo de Auditoria"],
  },
} as const;

const platformCards = [
  { name: "DeliGo", color: "#e53935", metrics: ["Utilizadores", "Pedidos", "Parceiros", "Receita"] },
  { name: "Comunhão", color: "#7c5ce5", metrics: ["Igrejas", "Membros", "Eventos", "Receita"] },
  { name: "TaoMoz", color: "#129a72", metrics: ["Utilizadores", "Empresas", "Transacções", "Receita"] },
  { name: "SARCA", color: "#e69b22", metrics: ["Utilizadores", "Operações", "Transacções", "Receita"] },
];

export default function Home() {
  const [platform, setPlatform] = useState("Todas as plataformas");
  const [active, setActive] = useState("Visão geral");
  const [menuOpen, setMenuOpen] = useState(false);
  const [commandOpen, setCommandOpen] = useState(false);
  const [persona, setPersona] = useState<keyof typeof personas>("anwar");
  const currentPersona = personas[persona];
  const visibleNav = nav.filter(([, label]) => currentPersona.modules.includes(label as never));

  const visibleCards = useMemo(
    () => platform === "Todas as plataformas" ? platformCards : platformCards.filter((item) => item.name === platform),
    [platform],
  );

  return (
    <main className="shell">
      <aside className={menuOpen ? "sidebar open" : "sidebar"}>
        <div className="brand">
          <img className="brandmark logoImage" src="/deligo-icon.png" alt="DeliGo Triunfal" />
          <div><strong>DeliGo Triunfal</strong><span>Central Web</span></div>
        </div>
        <nav>
          <p className="navLabel">ÁREAS DA EMPRESA</p>
          {visibleNav.map(([icon, label]) => (
            <button key={label} className={active === label ? "navItem active" : "navItem"} onClick={() => { setActive(label); setMenuOpen(false); }}>
              <span>{icon}</span>{label}
            </button>
          ))}
          <p className="navLabel">SISTEMA</p>
          <button className="navItem"><span>♧</span>Segurança</button>
          <button className="navItem"><span>⚙</span>Definições</button>
        </nav>
        <div className="user">
          <div className="avatar">{currentPersona.initials}</div>
          <div><strong>{currentPersona.name}</strong><span>{currentPersona.role}</span></div>
          <b>•••</b>
        </div>
      </aside>

      <section className="workspace">
        <header>
          <button className="menuButton" onClick={() => setMenuOpen(!menuOpen)}>☰</button>
          <button className="search" onClick={() => setCommandOpen(true)}>
            <span>⌕</span><span>Pesquisar em toda a Central…</span><kbd>⌘ K</kbd>
          </button>
          <div className="headerActions">
            <label className="viewAs">
              <span>Ver como</span>
              <select aria-label="Simular perfil" value={persona} onChange={(e) => {
                const next = e.target.value as keyof typeof personas;
                setPersona(next);
                setActive("Visão geral");
              }}>
                <option value="anwar">Anwar</option>
                <option value="sara">Sara</option>
                <option value="sansao">Sansão</option>
                <option value="contabilista">Contabilista</option>
                <option value="tecnologia">Técnico IT</option>
              </select>
            </label>
            <select aria-label="Plataforma actual" value={platform} onChange={(e) => setPlatform(e.target.value)}>
              {platforms.map((item) => <option key={item}>{item}</option>)}
            </select>
            <button className="iconButton" aria-label="Notifications">♢<i /></button>
            <div className="miniAvatar">{currentPersona.initials}</div>
          </div>
        </header>

        <div className="content">
          <div className="eyebrow"><span>HQ</span> / {active}</div>
          <div className="frozenBanner"><i /> Modo seguro: integrações com o backend temporariamente desligadas</div>
          <div className="titleRow">
            <div>
              <h1>{active === "Visão geral" ? "Visão geral do grupo" : active}</h1>
              <p>Gestão consolidada da DeliGo Triunfal, Lda.</p>
            </div>
            <div className="live"><i /> Central operacional</div>
          </div>
          {active !== "Visão geral" && (
            <section className="moduleContext">
              <div><span>MÓDULO</span><h2>{active}</h2><p>O conteúdo e as acções apresentados respeitam o role, a plataforma e as permissões do utilizador.</p></div>
              <div className="moduleLinks">
                {(moduleDetails[active] || ["Visão geral", "Actividade", "Relatórios", "Definições"]).map((item) => <button key={item}>{item}<b>→</b></button>)}
              </div>
            </section>
          )}

          <section className="metrics">
            {[
              ["Total de utilizadores", "0", "Nas plataformas autorizadas"],
              ["Receita corporativa", "—", "Contabilidade não ligada"],
              ["Lucro líquido", "—", "Nunca inferido do saldo bancário"],
              ["Trabalhadores activos", "3", "Liderança configurada"],
            ].map(([label, value, note], index) => (
              <article className="metric" key={label}>
                <div className={`metricIcon m${index}`}>{["♙", "↗", "⇄", "◎"][index]}</div>
                <p>{label}</p><strong>{value}</strong><span>{note}</span>
              </article>
            ))}
          </section>

          <div className="sectionHeading">
            <div><h2>Estado das plataformas</h2><p>Visão operacional por plataforma</p></div>
            <button>Ver estado do sistema →</button>
          </div>
          <section className="platformGrid">
            {visibleCards.map((card) => (
              <article className="platformCard" key={card.name}>
                <div className="platformTop">
                  <div className="platformIdentity"><i style={{ background: card.color }}>{card.name.charAt(0)}</i><div><strong>{card.name}</strong><span>A aguardar ligação</span></div></div>
                  <span className="status"><i /> Preparada</span>
                </div>
                <div className="platformMetrics">
                  {card.metrics.map((metric) => <div key={metric}><span>{metric}</span><strong>{metric === "Receita" ? "—" : "0"}</strong></div>)}
                </div>
                <button onClick={() => setPlatform(card.name)}>Abrir {card.name}<span>→</span></button>
              </article>
            ))}
          </section>

          <section className="governance">
            <div className="sectionHeading">
              <div><h2>Controlos corporativos</h2><p>Separação financeira e salvaguardas de governação</p></div>
              <span className="protected">● Área protegida</span>
            </div>
            <div className="controlGrid">
              {[
                ["Tesouraria corporativa", "—", "Apenas dinheiro da empresa", "Banco, caixa e obrigações"],
                ["Carteiras de utilizadores", "—", "Dinheiro de terceiros", "Excluído da receita e do lucro"],
                ["Contas a pagar", "—", "Obrigações pendentes", "Fornecedores, salários e impostos"],
                ["Lucro distribuível", "—", "Exige validação contabilística", "Sem levantamento automático"],
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
              <div><h2>Controlo da distribuição de lucros</h2><p>Separação de funções — nenhuma pessoa controla todo o ciclo</p></div>
              <span className="draftStatus">Sem proposta activa</span>
            </div>
            <div className="workflow">
              {[
                ["1", "Contabilidade", "Preparar resultado"],
                ["2", "Finanças", "Rever"],
                ["3", "Sócios", "Aprovar"],
                ["4", "Pagamento", "Instrução bancária"],
                ["5", "Reconciliação", "Concluir"],
              ].map(([number, title, text], index) => (
                <div className="workflowStep" key={title}>
                  <i>{number}</i><div><strong>{title}</strong><span>{text}</span></div>{index < 4 && <b>→</b>}
                </div>
              ))}
            </div>
          </section>

          <section className="lowerGrid">
            <article className="panel">
              <div className="panelTitle"><div><h2>Estrutura da empresa</h2><p>Liderança e responsabilidade operacional</p></div><button>Gerir pessoas</button></div>
              {[
                ["AA", "Anwar Abubacar Ismael", "CEO e Fundador", "SUPER ADMIN", "50% participação"],
                ["SI", "Sara Vitorino Feniosse Ismael", "Co-Fundadora · Finanças e Gestão", "FINANÇAS · GESTÃO", "50% participação"],
                ["SC", "Sansão Chume", "Supervisor de Operações", "SUPERVISOR", "Operações"],
              ].map((person, index) => (
                <div className="person" key={person[1]}>
                  <div className={`personAvatar p${index}`}>{person[0]}</div>
                  <div className="personName"><strong>{person[1]}</strong><span>{person[2]}</span></div>
                  <span className="role">{person[3]}</span><span className="ownership">{person[4]}</span>
                </div>
              ))}
            </article>
            <article className="panel activity">
              <div className="panelTitle"><div><h2>Actividade recente</h2><p>Acções auditadas em todo o grupo</p></div><button>Ver auditoria</button></div>
              <div className="empty"><div>⌁</div><strong>Ainda não existe actividade</strong><p>Os eventos aparecerão quando os serviços reais forem ligados.</p></div>
            </article>
          </section>
          <section className="departmentStrip">
            {[
              ["Contabilidade", "Plano de contas · Reconciliação · Impostos"],
              ["Recursos Humanos", "Contratos · Férias · Payroll · Ciclo de vida"],
              ["Jurídico", "Documentos societários · Conformidade · Contratos"],
              ["Colaboradores externos", "Acesso temporário · Revogação · Auditoria"],
            ].map(([title, text]) => <button key={title} onClick={() => setActive(title)}><strong>{title}</strong><span>{text}</span><b>→</b></button>)}
          </section>
          <section className="operationsSuite">
            <div className="sectionHeading">
              <div><h2>Operações corporativas</h2><p>Fluxos controlados entre departamentos</p></div>
              <button onClick={() => setActive("Aprovações")}>Abrir aprovações →</button>
            </div>
            <div className="suiteGrid">
              {[
                ["⌘", "Tecnologia / IT", "Sistemas, APIs, bases de dados, backups e incidentes técnicos", "Apenas acesso técnico"],
                ["▧", "Compras", "Pedido → aprovação → fornecedor → factura → pagamento", "Aprovação obrigatória"],
                ["▣", "Património", "Equipamentos, veículos, cartões SIM e histórico de atribuição", "0 activos ligados"],
                ["⚑", "Conformidade e Risco", "Políticas, riscos, auditorias, incidentes e revisões", "Sem incidentes abertos"],
                ["?", "Apoio Interno", "Pedidos para IT, RH, Finanças, Jurídico e Operações", "0 pedidos abertos"],
                ["✓", "Projectos e Tarefas", "Objectivos, prazos, atribuições e progresso", "0 projectos activos"],
              ].map(([icon, title, text, status]) => (
                <button className="suiteCard" key={title} onClick={() => setActive(title)}>
                  <i>{icon}</i><div><strong>{title}</strong><p>{text}</p><span>{status}</span></div><b>→</b>
                </button>
              ))}
            </div>
          </section>
          <section className="accessModel">
            <div>
              <span className="accessEyebrow">ACESSO BASEADO EM PERMISSÕES</span>
              <h2>A autoridade segue o âmbito, nunca apenas o cargo.</h2>
              <p>Administradores departamentais gerem apenas a sua área autorizada. Os acessos técnico, financeiro, jurídico e de segurança são atribuídos e auditados separadamente.</p>
            </div>
            <div className="accessLadder">
              {[
                ["01", "Super Administrador", "Excepção global"],
                ["02", "Administradores", "Limitados por módulo"],
                ["03", "Gestores de Departamento", "Âmbito departamental"],
                ["04", "Supervisores", "Âmbito operacional"],
                ["05", "Trabalhadores / Colaboradores", "Permissões atribuídas"],
                ["06", "Colaboradores Externos", "Acesso temporário"],
              ].map(([n, role, scope]) => <div key={role}><i>{n}</i><strong>{role}</strong><span>{scope}</span></div>)}
            </div>
          </section>
          <footer><span>DeliGo Triunfal HQ</span><span>Central de Gestão e Operações · Preparada para hq.deligo.co.mz</span></footer>
        </div>
      </section>

      {commandOpen && <div className="modal" onClick={() => setCommandOpen(false)}>
        <div className="command" onClick={(e) => e.stopPropagation()}>
          <input autoFocus placeholder="Pesquisar trabalhadores, plataformas, tickets…" />
          <p>ACÇÕES RÁPIDAS</p>
          {["Abrir Finanças", "Ver trabalhadores", "Abrir relatórios", "Estado do sistema"].map((item) => <button key={item} onClick={() => setCommandOpen(false)}>{item}<span>↵</span></button>)}
          <small>A pesquisa mostra apenas os resultados permitidos pelo seu role.</small>
        </div>
      </div>}
    </main>
  );
}
