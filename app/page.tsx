"use client";

import { useEffect, useMemo, useState, type CSSProperties } from "react";
import { Activity, BarChart3, CheckCircle2, ChartNoAxesCombined, ChevronRight, CircleHelp, ClipboardCheck, Coins, Database, FileChartColumn, Fingerprint, Handshake, Headphones, HeartHandshake, Landmark, LayoutDashboard, Megaphone, PackageCheck, PanelsTopLeft, Route, Scale, Settings, ShieldCheck, ShoppingBag, Smartphone, Sparkles, UserRound, Users, WalletCards, type LucideIcon } from "lucide-react";

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

const moduleIcons: Record<string, LucideIcon> = {
  "Visão geral": LayoutDashboard, "Plataformas": PanelsTopLeft, "Direcção Executiva": Landmark,
  "Pessoas": Users, "Recursos Humanos": UserRound, "Finanças": WalletCards, "Contabilidade": Coins,
  "Jurídico": Scale, "Conformidade e Risco": ShieldCheck, "Tecnologia / IT": Database,
  "Compras": ShoppingBag, "Património": PackageCheck, "Marketing": Megaphone, "Field": Route,
  "Apoio ao Cliente": Headphones, "Aquisição de Parceiros": Handshake, "Embaixadores": HeartHandshake,
  "Projectos e Tarefas": ClipboardCheck, "Apoio Interno": CircleHelp, "Aprovações": CheckCircle2,
  "BI / Análises": BarChart3, "Relatórios": FileChartColumn, "Registo de Auditoria": Fingerprint,
};

const platformIcons: Record<string, LucideIcon> = { DeliGo: Route, Comunhão: Users, TaoMoz: ShoppingBag, SARCA: Smartphone };

const moduleDetails: Record<string, string[]> = {
  "Meu Perfil": ["Dados pessoais", "Perfil profissional", "Organização", "Permissões"],
  "Definições": ["Geral", "Aparência", "Dashboard", "Notificações"],
  "Segurança": ["Autenticação", "2FA", "Dispositivos e sessões", "Alertas de segurança"],
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

const modulePresentation: Record<string, { description: string; action: string; primary: string; secondary: string; visual: string; status: string; color: string }> = {
  "Plataformas": { description: "Gere o portefólio digital e o estado operacional de cada produto do grupo.", action: "Adicionar plataforma", primary: "Plataformas", secondary: "Integrações", visual: "Disponibilidade por plataforma", status: "Adapters das plataformas", color: "#e53935" },
  "Direcção Executiva": { description: "Centraliza decisões societárias, deliberações e acompanhamento estratégico.", action: "Nova deliberação", primary: "Deliberações", secondary: "Decisões pendentes", visual: "Execução estratégica", status: "Governação corporativa", color: "#a47722" },
  "Pessoas": { description: "Mantém a estrutura organizacional, identidades internas e âmbitos de acesso.", action: "Novo trabalhador", primary: "Pessoas", secondary: "Acessos pendentes", visual: "Distribuição organizacional", status: "Directório corporativo", color: "#466bba" },
  "Recursos Humanos": { description: "Acompanha contratos, assiduidade, férias e todo o ciclo do trabalhador.", action: "Iniciar onboarding", primary: "Trabalhadores", secondary: "Pedidos de RH", visual: "Ciclo de pessoas", status: "Serviços de RH", color: "#9b5a8d" },
  "Finanças": { description: "Controla tesouraria, orçamento, receitas e despesas com segregação de funções.", action: "Novo lançamento", primary: "Movimentos", secondary: "Aprovações financeiras", visual: "Fluxo financeiro", status: "Serviços financeiros", color: "#258260" },
  "Contabilidade": { description: "Organiza lançamentos, reconciliações, impostos e demonstrações contabilísticas.", action: "Novo lançamento", primary: "Lançamentos", secondary: "Reconciliações", visual: "Fecho contabilístico", status: "Motor contabilístico", color: "#4c73a8" },
  "Jurídico": { description: "Protege contratos, licenças, documentos societários e obrigações legais.", action: "Novo processo", primary: "Processos", secondary: "Prazos legais", visual: "Exposição jurídica", status: "Arquivo jurídico", color: "#7559b7" },
  "Conformidade e Risco": { description: "Regista riscos, controlos, incidentes e revisões periódicas.", action: "Registar risco", primary: "Riscos", secondary: "Revisões pendentes", visual: "Mapa de risco", status: "Controlos de conformidade", color: "#c17836" },
  "Tecnologia / IT": { description: "Supervisiona sistemas, APIs, bases de dados, backups e incidentes técnicos.", action: "Abrir incidente", primary: "Sistemas", secondary: "Incidentes técnicos", visual: "Saúde tecnológica", status: "Monitorização técnica", color: "#3e70b8" },
  "Compras": { description: "Executa o ciclo controlado do pedido de compra até à factura e pagamento.", action: "Novo pedido", primary: "Pedidos de compra", secondary: "Aprovações pendentes", visual: "Ciclo de aquisição", status: "Fluxo de compras", color: "#b77931" },
  "Património": { description: "Controla equipamentos, veículos, cartões SIM, atribuições e devoluções.", action: "Registar activo", primary: "Activos", secondary: "Devoluções pendentes", visual: "Estado do património", status: "Inventário corporativo", color: "#667085" },
  "Marketing": { description: "Planeia campanhas, conteúdos, promoções, leads e desempenho de comunicação.", action: "Nova campanha", primary: "Campanhas", secondary: "Conteúdos pendentes", visual: "Desempenho de campanhas", status: "Canais de marketing", color: "#d14f6f" },
  "Field": { description: "Coordena equipas no terreno, visitas, verificações e relatórios operacionais.", action: "Nova missão", primary: "Missões Field", secondary: "Visitas pendentes", visual: "Execução no terreno", status: "Operações Field", color: "#2b8a7b" },
  "Apoio ao Cliente": { description: "Centraliza tickets, reclamações, conversas e histórico de atendimento.", action: "Novo ticket", primary: "Tickets", secondary: "Por responder", visual: "Qualidade do atendimento", status: "Canais de suporte", color: "#4b7bec" },
  "Aquisição de Parceiros": { description: "Gere leads comerciais, visitas, negociações e conversão de parceiros.", action: "Novo lead", primary: "Leads", secondary: "Negociações", visual: "Funil de aquisição", status: "Pipeline de parceiros", color: "#8c63b8" },
  "Embaixadores": { description: "Acompanha embaixadores, referências, conversões e comissões.", action: "Novo embaixador", primary: "Embaixadores", secondary: "Comissões pendentes", visual: "Conversão por referência", status: "Programa de embaixadores", color: "#d18b22" },
  "Projectos e Tarefas": { description: "Organiza objectivos, responsáveis, prazos, dependências e progresso.", action: "Novo projecto", primary: "Projectos", secondary: "Tarefas em atraso", visual: "Progresso dos projectos", status: "Gestão de trabalho", color: "#5f66c9" },
  "Apoio Interno": { description: "Recebe pedidos internos dirigidos a IT, RH, Finanças, Jurídico e Operações.", action: "Abrir pedido", primary: "Pedidos internos", secondary: "Por atender", visual: "Tempo de resolução", status: "Filas internas", color: "#487b78" },
  "Aprovações": { description: "Reúne somente decisões que o utilizador actual tem permissão para aprovar.", action: "Rever pendências", primary: "Aprovações", secondary: "A vencer", visual: "Fluxo de decisão", status: "Motor de aprovações", color: "#c05b4f" },
  "BI / Análises": { description: "Consolida KPIs, crescimento e desempenho autorizado de todo o grupo.", action: "Criar análise", primary: "Indicadores", secondary: "Relatórios agendados", visual: "Evolução dos KPIs", status: "Camada analítica", color: "#6c5bb5" },
  "Relatórios": { description: "Produz relatórios corporativos, financeiros, operacionais e de auditoria.", action: "Gerar relatório", primary: "Relatórios", secondary: "Agendados", visual: "Produção de relatórios", status: "Serviço documental", color: "#537493" },
  "Registo de Auditoria": { description: "Consulta eventos imutáveis de acesso, segurança e alterações críticas.", action: "Exportar auditoria", primary: "Eventos", secondary: "Alertas críticos", visual: "Actividade auditada", status: "Trilho de auditoria", color: "#555b66" },
};

const routeByModule: Record<string, string> = {
  "Visão geral": "/",
  "Meu Perfil": "/perfil",
  "Definições": "/definicoes",
  "Segurança": "/seguranca",
  "Plataformas": "/plataformas",
  "Direcção Executiva": "/executivo",
  "Pessoas": "/pessoas",
  "Recursos Humanos": "/recursos-humanos",
  "Finanças": "/financas",
  "Contabilidade": "/contabilidade",
  "Jurídico": "/juridico",
  "Conformidade e Risco": "/conformidade-risco",
  "Tecnologia / IT": "/tecnologia",
  "Compras": "/compras",
  "Património": "/patrimonio",
  "Marketing": "/marketing",
  "Field": "/field",
  "Apoio ao Cliente": "/apoio-cliente",
  "Aquisição de Parceiros": "/aquisicao-parceiros",
  "Embaixadores": "/embaixadores",
  "Projectos e Tarefas": "/projectos-tarefas",
  "Apoio Interno": "/apoio-interno",
  "Aprovações": "/aprovacoes",
  "BI / Análises": "/analises",
  "Relatórios": "/relatorios",
  "Registo de Auditoria": "/auditoria",
};

const moduleByRoute = Object.fromEntries(Object.entries(routeByModule).map(([module, route]) => [route, module]));

const workspaceRows: Record<string, string[][]> = {
  "Meu Perfil": [
    ["Identidade corporativa", "Configurada localmente", "DG-0001", "profile.view"],
    ["Dados pessoais", "Protegidos", "—", "profile.personal.view"],
    ["Perfil profissional", "Activo", "2026", "profile.professional.view"],
    ["Permissões atribuídas", "Simulação local", "Por role", "profile.permissions.view"],
  ],
  "Definições": [
    ["Idioma", "Português", "PT", "settings.locale.manage"],
    ["Fuso horário", "África/Joanesburgo", "UTC+2", "settings.timezone.manage"],
    ["Tema", "Claro", "Sistema", "settings.appearance.manage"],
    ["Página inicial", "Visão geral", "/", "settings.home.manage"],
  ],
  "Segurança": [
    ["Password", "Alteração bloqueada", "—", "security.password.manage"],
    ["Autenticação de dois factores", "Não verificado", "—", "security.2fa.manage"],
    ["Dispositivos autorizados", "Backend desligado", "—", "security.sessions.view"],
    ["Códigos de recuperação", "Não gerados", "—", "security.recovery.manage"],
  ],
  "Aprovações": [
    ["Finanças", "Revisão financeira", "0", "finance.approve"],
    ["Recursos Humanos", "Contratos e payroll", "0", "hr.approve"],
    ["Jurídico", "Contratos e deliberações", "0", "legal.approve"],
    ["Compras", "Pedidos de aquisição", "0", "procurement.approve"],
    ["Marketing", "Publicação de campanhas", "0", "marketing.publish"],
  ],
  "Tecnologia / IT": [
    ["APIs centrais", "Integração bloqueada", "Preparado", "technology.integrations.view"],
    ["Bases de dados", "Sem ligação activa", "Protegido", "technology.database.view"],
    ["Backups", "Não verificado", "—", "technology.backups.view"],
    ["Incidentes técnicos", "Nenhum dado ligado", "0", "technology.incidents.view"],
  ],
  "Compras": [
    ["Pedido de compra", "Rascunho", "0", "procurement.request.create"],
    ["Aprovação", "Pendente", "0", "procurement.approve"],
    ["Fornecedor", "Não ligado", "0", "procurement.suppliers.view"],
    ["Factura e pagamento", "Segregação obrigatória", "—", "procurement.invoice.view"],
  ],
  "Património": [
    ["Equipamentos", "Não ligados", "0", "assets.view"],
    ["Atribuídos", "Sem fonte de dados", "0", "assets.assign"],
    ["Devoluções pendentes", "Sem fonte de dados", "0", "assets.return"],
    ["Manutenção", "Sem fonte de dados", "0", "assets.maintenance"],
  ],
  "Registo de Auditoria": [
    ["Acessos", "Backend desligado", "—", "audit.login.view"],
    ["Alterações de permissões", "Backend desligado", "—", "audit.security.view"],
    ["Operações financeiras", "Backend desligado", "—", "audit.finance.view"],
    ["Impersonation", "Apenas simulação local", "Local", "audit.impersonation.view"],
  ],
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

type DashboardMetric = { key: string; label: string; value: number };
type DashboardPlatform = {
  slug: "deligo" | "comunhao" | "taomoz" | "sarca";
  name: string;
  connected: boolean;
  metrics: DashboardMetric[];
};
type DashboardData = {
  environment: string;
  checkedAt: string;
  platforms: DashboardPlatform[];
  operations: { supportCases: number; campaigns: number; fieldVisits: number; auditEvents: number };
};

export function HQApp() {
  const [platform, setPlatform] = useState("Todas as plataformas");
  const [active, setActive] = useState("Visão geral");
  const [menuOpen, setMenuOpen] = useState(false);
  const [commandOpen, setCommandOpen] = useState(false);
  const [persona, setPersona] = useState<keyof typeof personas>("anwar");
  const [accountOpen, setAccountOpen] = useState(false);
  const [subArea, setSubArea] = useState("");
  const [dashboard, setDashboard] = useState<DashboardData | null>(null);
  const [connectionError, setConnectionError] = useState("");
  const currentPersona = personas[persona];
  const isAccountScreen = ["Meu Perfil", "Definições", "Segurança"].includes(active);
  const activePresentation = modulePresentation[active];
  const visibleNav = nav.filter(([, label]) => currentPersona.modules.includes(label as never));

  useEffect(() => {
    const syncRoute = () => {
      const nextModule = moduleByRoute[window.location.pathname] || "Visão geral";
      setActive(nextModule);
      setSubArea(moduleDetails[nextModule]?.[0] || "");
    };
    syncRoute();
    window.addEventListener("popstate", syncRoute);
    return () => window.removeEventListener("popstate", syncRoute);
  }, []);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/dashboard", { cache: "no-store" })
      .then(async (response) => {
        if (!response.ok) throw new Error((await response.json()).error || "Falha de ligação");
        return response.json() as Promise<DashboardData>;
      })
      .then((data) => { if (!cancelled) setDashboard(data); })
      .catch((error: Error) => { if (!cancelled) setConnectionError(error.message); });
    return () => { cancelled = true; };
  }, []);

  const navigate = (label: string) => {
    setActive(label);
    setSubArea(moduleDetails[label]?.[0] || "");
    setMenuOpen(false);
    window.history.pushState({}, "", routeByModule[label] || "/");
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const liveCards = dashboard?.platforms.map((item) => ({
    ...item,
    color: platformCards.find((card) => card.name === item.name)?.color || "#667085",
  })) || [];
  const visibleCards = useMemo(
    () => platform === "Todas as plataformas" ? liveCards : liveCards.filter((item) => item.name === platform),
    [platform, liveCards],
  );
  const totalUsers = dashboard?.platforms.reduce((sum, item) => {
    const users = item.metrics.find((metric) => ["users", "members", "buyers", "passengers"].includes(metric.key));
    return sum + (users?.value || 0);
  }, 0) || 0;

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
            <button key={label} className={active === label ? "navItem active" : "navItem"} onClick={() => navigate(label)}>
              <span>{(() => { const Icon = moduleIcons[label]; return Icon ? <Icon aria-hidden="true" /> : icon; })()}</span>{label}
            </button>
          ))}
          <p className="navLabel">SISTEMA</p>
          <button className={active === "Segurança" ? "navItem active" : "navItem"} onClick={() => navigate("Segurança")}><span><ShieldCheck aria-hidden="true" /></span>Segurança</button>
          <button className={active === "Definições" ? "navItem active" : "navItem"} onClick={() => navigate("Definições")}><span><Settings aria-hidden="true" /></span>Definições</button>
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
            <button className="accountTrigger" onClick={() => setAccountOpen(!accountOpen)} aria-label="Abrir menu da conta">
              <div className="miniAvatar">{currentPersona.initials}</div>
              <div><strong>{currentPersona.name}</strong><span>{currentPersona.role}</span></div><b>⌄</b>
            </button>
            {accountOpen && <div className="accountMenu">
              <div className="accountMenuHead"><div className="avatar">{currentPersona.initials}</div><div><strong>{currentPersona.name}</strong><span>{currentPersona.role}</span><small>DeliGo Triunfal, Lda.</small></div></div>
              <div className="accountMenuGroup">
                <button onClick={() => { navigate("Meu Perfil"); setAccountOpen(false); }}><span>♙</span>Meu Perfil</button>
                <button onClick={() => { navigate("Definições"); setAccountOpen(false); }}><span>⚙</span>Definições</button>
                <button onClick={() => { navigate("Segurança"); setAccountOpen(false); }}><span>♧</span>Segurança</button>
                <button onClick={() => { navigate("Registo de Auditoria"); setAccountOpen(false); }}><span>▤</span>Minha Actividade</button>
              </div>
              {persona === "anwar" && <div className="accountMenuGroup"><p>ADMINISTRAÇÃO</p>
                <button onClick={() => { navigate("Pessoas"); setAccountOpen(false); }}><span>♙</span>Trabalhadores</button>
                <button onClick={() => { navigate("Pessoas"); setAccountOpen(false); }}><span>⌘</span>Roles e Permissões</button>
                <button onClick={() => { navigate("Registo de Auditoria"); setAccountOpen(false); }}><span>◎</span>Audit Log</button>
              </div>}
              <div className="accountMenuGroup"><button disabled className="logout"><span>↪</span>Terminar sessão</button></div>
            </div>}
          </div>
        </header>

        <div className="content">
          <div className="eyebrow"><span>HQ</span> / {active}</div>
          <div className="frozenBanner"><i /> {dashboard ? `Dados reais ligados a ${dashboard.environment} · actualizados ${new Date(dashboard.checkedAt).toLocaleTimeString("pt-MZ", { hour: "2-digit", minute: "2-digit" })}` : connectionError || "A ligar ao backend Deligo Staging…"}</div>
          <div className="titleRow">
            <div>
              <h1>{active === "Visão geral" ? "Visão geral do grupo" : active}</h1>
              <p>{active === "Visão geral" ? "Gestão consolidada da DeliGo Triunfal, Lda." : `Área dedicada a ${active}, sem conteúdos de outros departamentos.`}</p>
            </div>
            <div className="live"><i /> Central operacional</div>
          </div>
          {active !== "Visão geral" && !isAccountScreen && (
            <section className="moduleContext">
              <div><span>MÓDULO</span><h2>{active}</h2><p>{activePresentation?.description || "O conteúdo e as acções apresentados respeitam o role, a plataforma e as permissões do utilizador."}</p></div>
              <div className="moduleLinks">
                {(moduleDetails[active] || ["Visão geral", "Actividade", "Relatórios", "Definições"]).map((item) => <button className={subArea === item ? "active" : ""} onClick={() => setSubArea(item)} key={item}>{item}<b>→</b></button>)}
              </div>
            </section>
          )}
          {active !== "Visão geral" && !isAccountScreen && (
            <section className="moduleWorkspace">
              <div className="workspaceHead">
                <div><span>ESPAÇO OPERACIONAL</span><h2>{active}{subArea ? ` · ${subArea}` : ""}</h2></div>
                <div><button>Exportar</button><button className="primaryAction" disabled>{activePresentation?.action || "Nova acção"}</button></div>
              </div>
              <div className="workspaceStats">
                <div><span>{activePresentation?.primary || moduleDetails[active]?.[0] || "Registos"}</span><strong>0</strong><small>Fonte desta área não ligada</small></div>
                <div><span>{activePresentation?.secondary || moduleDetails[active]?.[1] || "Pendentes"}</span><strong>0</strong><small>Sem dados reais desta área</small></div>
                <div><span>Estado</span><strong className="textStatus">Preparado</strong><small>Adapter bloqueado</small></div>
                <div><span>Última sincronização</span><strong className="textStatus">—</strong><small>Nunca executada</small></div>
              </div>
              <div className="moduleVisualRow">
                <div className="moduleDonut" style={{"--module-color": activePresentation?.color || "#e65351"} as CSSProperties}><div><strong>0%</strong><span>Dados ligados</span></div></div>
                <div className="moduleBars" style={{"--module-color": activePresentation?.color || "#e65351"} as CSSProperties}>{[42,68,54,82,61,74,48,70].map((height,index) => <i key={index} style={{height:`${height}%`}} />)}<span>{activePresentation?.visual || active} · sem valores reais</span></div>
                <div className="modulePulse" style={{"--module-color": activePresentation?.color || "#39a475"} as CSSProperties}><span>{activePresentation?.status || "ESTADO DO ADAPTER"}</span><strong><i /> Preparado</strong><small>Ligação bloqueada por segurança</small></div>
              </div>
              <div className="workspaceTable">
                <div className="tableHeader"><span>Área</span><span>Estado</span><span>Valor</span><span>Permissão</span></div>
                {(workspaceRows[active] || (moduleDetails[active] || []).map((item) => [item, "Preparado", "0", `${active.toLowerCase()}.view`])).map((row) => (
                  <button className={`tableRow ${subArea === row[0] ? "selected" : ""}`} onClick={() => setSubArea(row[0])} key={row[0]}><strong>{row[0]}</strong><span>{row[1]}</span><b>{row[2]}</b><code>{row[3]}</code></button>
                ))}
              </div>
              <div className="safeNotice"><b>Modo de preparação</b><span>As acções de criação, aprovação e alteração permanecem desactivadas até existir staging aprovado e uma sessão validada pelo backend.</span></div>
            </section>
          )}
          {active === "Meu Perfil" && <section className="accountDetailGrid">
            <article className="profileCard">
              <div className="profileHero"><div className="profileAvatar">{currentPersona.initials}</div><div><h2>{currentPersona.name}</h2><p>{currentPersona.role}</p><span>● Activo</span></div></div>
              <div className="profileFields">
                <div><span>ID do trabalhador</span><strong>{persona === "anwar" ? "DG-0001" : "A atribuir"}</strong></div>
                <div><span>Departamento</span><strong>{currentPersona.role}</strong></div>
                <div><span>Organização</span><strong>DeliGo Triunfal, Lda.</strong></div>
                <div><span>Data de entrada</span><strong>2026</strong></div>
                <div><span>Gestor directo</span><strong>{persona === "anwar" ? "—" : "A configurar"}</strong></div>
                <div><span>Local de trabalho</span><strong>Moçambique</strong></div>
              </div>
            </article>
            <article className="permissionCard"><h2>Âmbito de acesso</h2><p>Permissões simuladas a partir do perfil seleccionado.</p><div>{currentPersona.modules.map((item) => <span key={item}>✓ {item}</span>)}</div></article>
          </section>}
          {active === "Definições" && <section className="settingsGrid">
            {[
              ["Preferências gerais", ["Idioma: Português", "Fuso horário: UTC+2", "Formato de data: DD/MM/AAAA", "Densidade: Confortável"]],
              ["Notificações corporativas", ["Avisos da empresa", "Segurança", "Tarefas atribuídas", "Menções e mensagens"]],
              ["Preferências do dashboard", ["Página inicial: Visão geral", "Plataforma: Todas", "Período padrão: 30 dias", "Widgets: por permissão"]],
            ].map(([title, items]) => <article className="settingsCard" key={title as string}><h2>{title}</h2>{(items as string[]).map((item) => <label key={item}><span>{item}</span><input type="checkbox" defaultChecked disabled /></label>)}</article>)}
          </section>}
          {active === "Segurança" && <section className="securityGrid">
            <article className="securityCard"><div className="securityIcon">◉</div><div><h2>Autenticação de dois factores</h2><p>Protecção reforçada para contas corporativas e cargos críticos.</p><span className="warningBadge">Estado não verificado</span></div><button disabled>Configurar 2FA</button></article>
            <article className="securityCard"><div className="securityIcon">▣</div><div><h2>Password corporativa</h2><p>Alteração segura, recuperação e códigos de emergência.</p><span>Última alteração: —</span></div><button disabled>Alterar password</button></article>
            <article className="sessionsCard"><div className="panelTitle"><div><h2>Dispositivos e sessões</h2><p>As sessões reais aparecerão quando a autenticação central for ligada.</p></div><button disabled>Terminar outras sessões</button></div>
              <div className="sessionRow"><i>▤</i><div><strong>Este navegador</strong><span>Windows · Sessão local de demonstração</span></div><b>Dispositivo actual</b></div>
              <div className="sessionRow disabledSession"><i>▯</i><div><strong>Outros dispositivos</strong><span>Nenhuma fonte de sessões ligada</span></div><b>—</b></div>
            </article>
            <article className="sessionsCard"><div className="panelTitle"><div><h2>Alertas de segurança</h2><p>Login, password, dispositivos, 2FA e permissões.</p></div></div><div className="empty compactEmpty"><div>♧</div><strong>Sem alertas disponíveis</strong><p>O backend de auditoria está desligado.</p></div></article>
          </section>}

          {active === "Visão geral" && <>
          <section className="metrics">
            {[
              ["Total de utilizadores", String(totalUsers), "Nas quatro plataformas"],
              ["Receita corporativa", "—", "Contabilidade não ligada"],
              ["Lucro líquido", "—", "Nunca inferido do saldo bancário"],
              ["Operações transversais", String((dashboard?.operations.supportCases || 0) + (dashboard?.operations.campaigns || 0) + (dashboard?.operations.fieldVisits || 0)), "Suporte, marketing e field"],
            ].map(([label, value, note], index) => (
              <article className="metric" key={label}>
                <div className={`metricIcon m${index}`}>{[Users, ChartNoAxesCombined, Coins, Activity].map((Icon, iconIndex) => iconIndex === index ? <Icon key={iconIndex} aria-hidden="true" /> : null)}</div>
                <p>{label}</p><strong>{value}</strong><span>{note}</span>
                <div className={`miniTrend trend${index}`}><i /><i /><i /><i /><i /><i /></div>
              </article>
            ))}
          </section>

          <section className="insightGrid">
            <article className="chartPanel">
              <div className="panelTitle"><div><h2>Desempenho do grupo</h2><p>Receita, operações e crescimento consolidados</p></div><div className="chartLegend"><span><i /> Receita</span><span><i /> Operações</span></div></div>
              <div className="emptyChart">
                <div className="chartAxis"><span>100%</span><span>75%</span><span>50%</span><span>25%</span><span>0</span></div>
                <div className="chartCanvas"><div className="chartGlow" /><div className="chartZeroLine" />{["Jan","Fev","Mar","Abr","Mai","Jun","Jul"].map((m) => <span key={m}>{m}</span>)}</div>
                <div className="chartMessage"><i>⌁</i><strong>Pronto para dados reais</strong><span>O gráfico será preenchido pelo adapter analítico.</span></div>
              </div>
            </article>
            <article className="readinessPanel">
              <div className="panelTitle"><div><h2>Preparação das integrações</h2><p>Estado da camada de ligação</p></div><span className="readinessScore">4/4</span></div>
              {(dashboard?.platforms || []).map((item) => { const color = platformCards.find((card) => card.name === item.name)?.color || "#667085"; const Icon = platformIcons[item.name] || Sparkles; return <div className="readinessRow" key={item.slug}><i style={{background: color}}><Icon aria-hidden="true" /></i><div><strong>{item.name}</strong><span>{item.metrics.length} indicadores reais</span></div><b>Ligado</b></div>; })}
              <div className="readinessNote"><i /> Leitura segura e agregada do ambiente de staging.</div>
            </article>
          </section>

          <div className="sectionHeading">
            <div><h2>Estado das plataformas</h2><p>Visão operacional por plataforma</p></div>
            <button>Ver estado do sistema →</button>
          </div>
          <section className="platformGrid">
            {visibleCards.map((card) => (
              <article className="platformCard" key={card.name}>
                <div className="platformAccent" style={{ background: card.color }} />
                <div className="platformTop">
                  <div className="platformIdentity"><i style={{ background: card.color }}>{(() => { const Icon = platformIcons[card.name] || Sparkles; return <Icon aria-hidden="true" />; })()}</i><div><strong>{card.name}</strong><span>Deligo Staging</span></div></div>
                  <span className="status"><i /> Ligada</span>
                </div>
                <div className="platformMetrics">
                  {card.metrics.map((metric) => <div key={metric.key}><span>{metric.label}</span><strong>{Number(metric.value).toLocaleString("pt-MZ")}</strong></div>)}
                </div>
                <button onClick={() => setPlatform(card.name)}>Abrir {card.name}<span><ChevronRight aria-hidden="true" /></span></button>
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
            ].map(([title, text]) => <button key={title} onClick={() => navigate(title)}><strong>{title}</strong><span>{text}</span><b>→</b></button>)}
          </section>
          <section className="operationsSuite">
            <div className="sectionHeading">
              <div><h2>Operações corporativas</h2><p>Fluxos controlados entre departamentos</p></div>
              <button onClick={() => navigate("Aprovações")}>Abrir aprovações →</button>
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
                <button className="suiteCard" key={title} onClick={() => navigate(title)}>
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
          </>}
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

export default function Home() {
  return <HQApp />;
}
