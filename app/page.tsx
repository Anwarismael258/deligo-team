"use client";
/* eslint-disable react-hooks/set-state-in-effect -- route and selection resets intentionally synchronize client navigation state */

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { Activity, BarChart3, CheckCircle2, ChartNoAxesCombined, ChevronRight, CircleHelp, ClipboardCheck, Coins, Database, FileChartColumn, Fingerprint, Handshake, Headphones, HeartHandshake, Landmark, LayoutDashboard, MapPinned, Megaphone, PackageCheck, PanelsTopLeft, Route, Scale, Settings, ShieldCheck, ShoppingBag, Smartphone, Sparkles, UserRound, Users, WalletCards, type LucideIcon } from "lucide-react";
import OperationalModule from "@/components/OperationalModule";
import LiveOperationsMap, { type OperationsMapMarker } from "@/components/LiveOperationsMap";

const platforms = ["Todas as plataformas", "DeliGo", "Comunhão", "TaoMoz", "SARCA"];
const nav = [
  ["⌂", "Visão geral"],
  ["◇", "Plataformas"],
  ["⌖", "Mapa operacional"],
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
  "Visão geral": LayoutDashboard, "Plataformas": PanelsTopLeft, "Mapa operacional": MapPinned, "Direcção Executiva": Landmark,
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
  "Mapa operacional": ["Mapa ao vivo", "DeliGo", "SARCA", "TaoMoz"],
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
  "Mapa operacional": "/mapa-operacional",
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
    role: "Sócia · Diretora Financeira",
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
  marketing: { name: "Agente de Marketing", role: "Marketing", initials: "AM", modules: ["Visão geral", "Marketing", "Projectos e Tarefas", "BI / Análises", "Relatórios"] },
  field: { name: "Agente Field", role: "Field", initials: "AF", modules: ["Visão geral", "Field", "Aquisição de Parceiros", "Projectos e Tarefas", "Relatórios"] },
  support: { name: "Agente Suporte", role: "Apoio ao Cliente", initials: "AS", modules: ["Visão geral", "Apoio ao Cliente", "Projectos e Tarefas", "Relatórios"] },
  hr: { name: "Recursos Humanos", role: "Recursos Humanos", initials: "RH", modules: ["Visão geral", "Pessoas", "Recursos Humanos", "Projectos e Tarefas", "Relatórios"] },
  legal: { name: "Jurídico", role: "Jurídico", initials: "JL", modules: ["Visão geral", "Jurídico", "Conformidade e Risco", "Relatórios"] },
  operations: { name: "Operações", role: "Operações", initials: "OP", modules: ["Visão geral", "Pessoas", "Field", "Apoio ao Cliente", "Aquisição de Parceiros", "Projectos e Tarefas", "Relatórios"] },
  acquisition: { name: "Aquisição", role: "Aquisição de Parceiros", initials: "AP", modules: ["Visão geral", "Aquisição de Parceiros", "Projectos e Tarefas", "Relatórios"] },
  ambassador: { name: "Embaixador", role: "Embaixadores", initials: "EM", modules: ["Visão geral", "Embaixadores", "Relatórios"] },
  procurement: { name: "Compras", role: "Compras", initials: "CP", modules: ["Visão geral", "Compras", "Aprovações", "Relatórios"] },
  assets: { name: "Património", role: "Património e Logística", initials: "PL", modules: ["Visão geral", "Património", "Relatórios"] },
} as const;

const personaByRole = { SUPER_ADMIN: "anwar", FINANCE: "sara", SUPERVISOR: "sansao", ACCOUNTING: "contabilista", HUMAN_RESOURCES: "hr", LEGAL: "legal", OPERATIONS: "operations", TECHNOLOGY: "tecnologia", MARKETING: "marketing", FIELD: "field", CUSTOMER_SUPPORT: "support", PARTNER_ACQUISITION: "acquisition", AMBASSADOR: "ambassador", PROCUREMENT: "procurement", ASSETS_LOGISTICS: "assets" } as const;

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
  modules: {
    currency: "MZN";
    totalValue: number;
    platforms: Array<{ slug: string; name: string; value: number; people: Array<{ id: string; name: string; role: string; created_at: string }> }>;
    departments: Record<string, { total: number; active?: number; open?: number }>;
  };
  governance: {
    legalName: string;
    legalForm: string;
    reservedMatterApprovalsRequired: number;
    shareholders: Array<{ employeeId: string; displayName: string; quotaPercent: number; corporateTitle: string; isManagingPartner: boolean; isSuperAdministrator: boolean }>;
    reservedMatters: string[];
  };
};
type LiveMapMarker = OperationsMapMarker;
type LiveMapData = { checkedAt: string; markers: LiveMapMarker[] };
type ManagedEmployee = { id:string; employee_code:string; name:string; phone:string; job_title:string; department:string; department_code:string; role:string|null; requested_role:string|null; status:string; created_at:string; updated_at:string; last_login_at:string|null };
type EmployeeHistory = { id:string; employee_id:string; action:string; created_at:string };
type EmployeeAccess = { id:string; employee_id:string|null; event_type:string; occurred_at:string };
type EmployeePermission = { id:string; employee_id:string; permission_code:string; allowed:boolean };
type HrData = Record<string, Array<Record<string,unknown>>>;
type FinanceRecord = Record<string, unknown> & { id:string; platform_id?:string|null; status?:string; amount?:number; current_balance?:number; transaction_type?:string; payee?:string; description?:string; due_at?:string; created_at?:string; expected_income?:number; expected_expense?:number; spent_amount?:number };
type FinanceData = { financial_accounts:FinanceRecord[]; financial_transactions:FinanceRecord[]; budgets:FinanceRecord[]; payment_requests:FinanceRecord[]; cashflow_forecasts:FinanceRecord[]; profit_distributions:FinanceRecord[] };
type AuditRecord = { id:string; occurred_at:string; actor:string; action:string; module:string; target_type:string; target_id:string; result:string; ip_address:string|null; metadata:Record<string,unknown> };
type PlatformAdminSnapshot = { platform: string; data: Record<string, unknown>; checkedAt: string };
type PlatformSnapshot = { platform:string; data:Record<string, unknown>; checkedAt:string };
type PlatformProfile = { platform:string; id:string; profile:Record<string, unknown>|null; kyc:unknown[]; wallets:unknown[]; orders:unknown[]; disputes:unknown[]; activity:unknown[] };

const metricFor = (platform: DashboardPlatform | undefined, labels: string[]) =>
  platform?.metrics.find((metric) => labels.some((label) => metric.label.toLowerCase().includes(label)))?.value ?? 0;
const recordsFor = (snapshot: PlatformSnapshot | null, source: string) => {
  const value = snapshot?.data[source];
  return Array.isArray(value) ? value.length : 0;
};
const operationalLabel = (name: string) => ({ DeliGo: "Pedidos", "Comunhão": "Eventos", TaoMoz: "Pedidos", SARCA: "Viagens" }[name] || "Operações");
const teamLabel = (name: string) => ({ DeliGo: "Estafetas e parceiros", "Comunhão": "Igrejas", TaoMoz: "Vendedores", SARCA: "Motoristas" }[name] || "Equipa");
const teamValue = (platform: DashboardPlatform | undefined, name: string) => metricFor(platform, name === "DeliGo" ? ["estafeta", "parceiro"] : name === "Comunhão" ? ["igreja"] : name === "TaoMoz" ? ["vendedor", "empresa"] : ["motorista", "viatura"]);

export function HQApp() {
  const [platform, setPlatform] = useState("Todas as plataformas");
  const [active, setActive] = useState("Visão geral");
  const [menuOpen, setMenuOpen] = useState(false);
  const [commandOpen, setCommandOpen] = useState(false);
  const [persona, setPersona] = useState<keyof typeof personas>("anwar");
  const [accountOpen, setAccountOpen] = useState(false);
  const [subArea, setSubArea] = useState("");
  const [dashboard, setDashboard] = useState<DashboardData | null>(null);
  const [liveMap, setLiveMap] = useState<LiveMapData | null>(null);
  const [connectionError, setConnectionError] = useState("");
  const [peopleSearch, setPeopleSearch] = useState("");
  const [mapSearch, setMapSearch] = useState("");
  const [mapStatus, setMapStatus] = useState("todos");
  const [selectedMapWorker, setSelectedMapWorker] = useState<LiveMapMarker | null>(null);
  const [sessionRole, setSessionRole] = useState("");
  const [managedEmployees, setManagedEmployees] = useState<ManagedEmployee[]>([]);
  const [employeeSearch, setEmployeeSearch] = useState("");
  const [selectedEmployee, setSelectedEmployee] = useState<ManagedEmployee | null>(null);
  const [employeeHistory, setEmployeeHistory] = useState<EmployeeHistory[]>([]);
  const [employeeAccess, setEmployeeAccess] = useState<EmployeeAccess[]>([]);
  const [employeePermissions, setEmployeePermissions] = useState<EmployeePermission[]>([]);
  const [hrData, setHrData] = useState<HrData>({});
  const [showHrEventForm, setShowHrEventForm] = useState(false);
  const [hrNotice, setHrNotice] = useState("");
  const [financeData, setFinanceData] = useState<FinanceData>({ financial_accounts:[], financial_transactions:[], budgets:[], payment_requests:[], cashflow_forecasts:[], profit_distributions:[] });
  const [financeNotice, setFinanceNotice] = useState("");
  const [financeEntryKind, setFinanceEntryKind] = useState("transaction");
  const [showFinanceForm, setShowFinanceForm] = useState(false);
  const [accountingData,setAccountingData]=useState<Record<string,FinanceRecord[]>>({});
  const [accountingReports,setAccountingReports]=useState<Record<string,unknown>>({});
  const [showAccountingForm,setShowAccountingForm]=useState(false);
  const [accountingKind,setAccountingKind]=useState("invoice");
  const [accountingNotice,setAccountingNotice]=useState("");
  const [legalData,setLegalData]=useState<Record<string,FinanceRecord[]>>({});
  const [showLegalForm,setShowLegalForm]=useState(false);
  const [showLegalArchiveForm,setShowLegalArchiveForm]=useState(false);
  const [legalKind,setLegalKind]=useState("contract");
  const [legalNotice,setLegalNotice]=useState("");
  const [legalDocumentDetail,setLegalDocumentDetail]=useState<{document:Record<string,unknown>;versions:Record<string,unknown>[]} | null>(null);
  const [complianceData,setComplianceData]=useState<Record<string,FinanceRecord[]>>({});
  const [showComplianceForm,setShowComplianceForm]=useState(false);
  const [showComplianceExtraForm,setShowComplianceExtraForm]=useState(false);
  const [complianceKind,setComplianceKind]=useState("risk");
  const [complianceNotice,setComplianceNotice]=useState("");
  const [technologyData,setTechnologyData]=useState<Record<string,FinanceRecord[]>>({});
  const [showTechnologyForm,setShowTechnologyForm]=useState(false);
  const [technologyKind,setTechnologyKind]=useState("system");
  const [technologyNotice,setTechnologyNotice]=useState("");
  const [procurementData,setProcurementData]=useState<Record<string,FinanceRecord[]>>({});
  const [showProcurementForm,setShowProcurementForm]=useState(false);
  const [procurementKind,setProcurementKind]=useState("request");
  const [procurementNotice,setProcurementNotice]=useState("");
  const [marketingData,setMarketingData]=useState<Record<string,FinanceRecord[]>>({});
  const [marketingReports,setMarketingReports]=useState<Array<Record<string,unknown>>>([]);
  const [showMarketingForm,setShowMarketingForm]=useState(false);
  const [marketingKind,setMarketingKind]=useState("campaign");
  const [marketingNotice,setMarketingNotice]=useState("");
  const [fieldData,setFieldData]=useState<Record<string,FinanceRecord[]>>({});
  const [showFieldForm,setShowFieldForm]=useState(false);
  const [fieldKind,setFieldKind]=useState("visit");
  const [fieldNotice,setFieldNotice]=useState("");
  const [auditRecords, setAuditRecords] = useState<AuditRecord[]>([]);
  const [platformAdminSnapshot, setPlatformAdminSnapshot] = useState<PlatformAdminSnapshot | null>(null);
  const [platformAdminError, setPlatformAdminError] = useState("");
  const [selectedProfile, setSelectedProfile] = useState<{ platform:string; id:string; name:string } | null>(null);
  const [profileDetail, setProfileDetail] = useState<PlatformProfile | null>(null);
  const [employeeNotice, setEmployeeNotice] = useState("");
  const [showEmployeeForm, setShowEmployeeForm] = useState(false);
  const [editingEmployee, setEditingEmployee] = useState<ManagedEmployee | null>(null);
  const [platformSnapshot, setPlatformSnapshot] = useState<PlatformSnapshot | null>(null);
  const currentPersona = personas[persona];
  const isAccountScreen = ["Meu Perfil", "Definições", "Segurança"].includes(active);
  const activePresentation = modulePresentation[active];
  const visibleNav = nav.filter(([, label]) => currentPersona.modules.includes(label as never));

  useEffect(() => {
    fetch("/api/auth/session", { cache: "no-store" }).then(async (response) => {
      if (!response.ok) { window.location.replace("/login"); return; }
      const session = await response.json() as { user?: { hq_role?: keyof typeof personaByRole } };
      const sessionPersona = session.user?.hq_role && personaByRole[session.user.hq_role];
      setSessionRole(session.user?.hq_role || "");
      if (sessionPersona) setPersona(sessionPersona);
    }).catch(() => window.location.replace("/login"));
  }, []);

  useEffect(() => {
    if (!["Visão geral", "Mapa operacional"].includes(active)) return;
    let cancelled = false;
    const refreshMap = () => fetch("/api/map", { cache: "no-store" })
      .then(async (response) => { if (!response.ok) throw new Error(); return response.json() as Promise<LiveMapData>; })
      .then((data) => { if (!cancelled) setLiveMap({ checkedAt: data.checkedAt, markers: Array.isArray(data.markers) ? data.markers : [] }); })
      .catch(() => { if (!cancelled) setLiveMap(null); });
    void refreshMap();
    const interval = window.setInterval(() => void refreshMap(), 10_000);
    return () => { cancelled = true; window.clearInterval(interval); };
  }, [active]);

  useEffect(() => {
    if (!sessionRole || sessionRole === "SUPER_ADMIN") return;
    const rolePersonaKey = personaByRole[sessionRole as keyof typeof personaByRole];
    const allowedModules = rolePersonaKey ? personas[rolePersonaKey].modules as readonly string[] : [];
    const universallyAllowed = ["Meu Perfil", "DefiniÃ§Ãµes", "SeguranÃ§a"];
    if (!allowedModules.includes(active) && !universallyAllowed.includes(active)) {
      setActive("VisÃ£o geral");
      setSubArea("");
      window.history.replaceState({}, "", "/");
    }
  }, [active, sessionRole]);

  useEffect(() => {
    if (!["Pessoas","Recursos Humanos"].includes(active)) return;
    fetch("/api/employees", { cache:"no-store" }).then(async response => { if (!response.ok) throw new Error(); return response.json(); }).then(data => { setManagedEmployees(data.employees || []); setEmployeeHistory(data.history || []); setEmployeeAccess(data.access || []); setEmployeePermissions(data.permissions || []); }).catch(() => setManagedEmployees([]));
  }, [active]);

  useEffect(() => { if(active!=="Recursos Humanos")return; fetch("/api/hr",{cache:"no-store"}).then(async response=>{if(!response.ok)throw new Error();return response.json()}).then(result=>setHrData(result.data||{})).catch(()=>setHrData({})); },[active]);

  const refreshFinance = async () => { const response=await fetch("/api/finance",{cache:"no-store"}); if(!response.ok)throw new Error(); const result=await response.json(); setFinanceData(result.data); };
  useEffect(() => { if(active!=="Finanças")return; refreshFinance().catch(()=>setFinanceNotice("Não foi possível carregar os registos financeiros para este perfil.")); },[active]);
  useEffect(()=>{if(active!=="Contabilidade")return;fetch("/api/accounting",{cache:"no-store"}).then(r=>r.ok?r.json():Promise.reject()).then(r=>{setAccountingData(r.data||{});setAccountingReports(r.reports||{})}).catch(()=>{setAccountingData({});setAccountingReports({})})},[active]);
  const refreshLegal=async()=>{const r=await fetch("/api/legal",{cache:"no-store"});if(!r.ok)throw new Error();setLegalData((await r.json()).data||{})};
  useEffect(()=>{if(active!=="Jurídico")return;refreshLegal().catch(()=>setLegalData({}))},[active]);
  const refreshCompliance=async()=>{const r=await fetch("/api/compliance",{cache:"no-store"});if(!r.ok)throw new Error();setComplianceData((await r.json()).data||{})};
  useEffect(()=>{if(active!=="Conformidade e Risco")return;refreshCompliance().catch(()=>setComplianceData({}))},[active]);
  const refreshTechnology=async()=>{const r=await fetch("/api/technology",{cache:"no-store"});if(!r.ok)throw new Error();setTechnologyData((await r.json()).data||{})};
  useEffect(()=>{if(active!=="Tecnologia / IT")return;refreshTechnology().catch(()=>setTechnologyData({}))},[active]);
  const refreshProcurement=async()=>{const r=await fetch("/api/procurement",{cache:"no-store"});if(!r.ok)throw new Error();setProcurementData((await r.json()).data||{})};
  useEffect(()=>{if(active!=="Compras")return;refreshProcurement().catch(()=>setProcurementData({}))},[active]);
  const refreshMarketing=async()=>{const r=await fetch("/api/marketing",{cache:"no-store"});if(!r.ok)throw new Error();const result=await r.json();setMarketingData(result.data||{});setMarketingReports(result.reports||[])};
  useEffect(()=>{if(active!=="Marketing")return;refreshMarketing().catch(()=>{setMarketingData({});setMarketingReports([]);setMarketingNotice("Não foi possível carregar Marketing para este perfil.")})},[active]);
  const refreshField=async()=>{const r=await fetch("/api/field",{cache:"no-store"});if(!r.ok)throw new Error();setFieldData((await r.json()).data||{})};
  useEffect(()=>{if(active!=="Field")return;refreshField().catch(()=>{setFieldData({});setFieldNotice("Não foi possível carregar Field para este perfil.")})},[active]);

  useEffect(() => {
    if (active !== "Registo de Auditoria") return;
    fetch("/api/audit", { cache:"no-store" }).then(async response => { if (!response.ok) throw new Error(); return response.json(); }).then(data => setAuditRecords(data.events || [])).catch(() => setAuditRecords([]));
  }, [active]);

  const refreshEmployees = async () => { const response=await fetch("/api/employees",{cache:"no-store"}); if(response.ok){const data=await response.json();setManagedEmployees(data.employees||[]);setEmployeeHistory(data.history||[]);setEmployeeAccess(data.access||[]);setEmployeePermissions(data.permissions||[]);} };
  const createEmployee = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setEmployeeNotice("A criar cadastro…"); const form=new FormData(event.currentTarget);
    const response=await fetch("/api/employees",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({name:form.get("name"),phone:form.get("phone"),jobTitle:form.get("jobTitle"),department:form.get("department"),role:form.get("role"),activate:form.get("activate")==="on"})});
    const result=await response.json(); setEmployeeNotice(response.ok ? `Cadastro ${result.employee.status === "active" ? "activo" : "enviado para aprovação"}.` : result.error); if(response.ok){setShowEmployeeForm(false);await refreshEmployees();}
  };
  const employeeAction = async (employeeId:string, action:string) => { setEmployeeNotice("A processar…"); const response=await fetch("/api/employees",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({employeeId,action})});const result=await response.json();setEmployeeNotice(response.ok?"Conta actualizada e auditada.":result.error);if(response.ok)await refreshEmployees(); };
  const updateEmployee = async (event: FormEvent<HTMLFormElement>) => { event.preventDefault(); if (!editingEmployee) return; setEmployeeNotice("A guardar alterações…"); const form=new FormData(event.currentTarget); const response=await fetch("/api/employees",{method:"PUT",headers:{"Content-Type":"application/json"},body:JSON.stringify({employeeId:editingEmployee.id,name:form.get("name"),phone:form.get("phone"),jobTitle:form.get("jobTitle"),department:form.get("department"),role:form.get("role"),updatedAt:editingEmployee.updated_at})}); const result=await response.json(); setEmployeeNotice(response.ok?"Trabalhador actualizado e auditado.":result.error); if(response.ok){setEditingEmployee(null);await refreshEmployees();} };
  const employeeGovernanceAction = async (payload:Record<string,unknown>) => { setEmployeeNotice("A guardar controlo de acesso…"); const response=await fetch("/api/employees",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify(payload)}); const result=await response.json(); setEmployeeNotice(response.ok?"Supervisor ou permissão actualizado e auditado.":result.error); if(response.ok)await refreshEmployees(); };
  const createHrEvent = async (event:FormEvent<HTMLFormElement>) => { event.preventDefault(); const form=new FormData(event.currentTarget); setHrNotice("A guardar registo de RH…"); const response=await fetch("/api/hr",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({resource:"hr_employee_events",record:{employee_id:form.get("employeeId"),event_type:form.get("eventType"),title:form.get("title"),occurred_on:form.get("occurredOn"),status:"open"}})}); const result=await response.json(); setHrNotice(response.ok?"Registo criado com sucesso.":result.error); if(response.ok){setShowHrEventForm(false); const refreshed=await fetch("/api/hr",{cache:"no-store"});if(refreshed.ok)setHrData((await refreshed.json()).data||{});} };
  const createFinanceRecord = async (event:FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const form=new FormData(event.currentTarget); const amount=Number(form.get("amount")||0); const platform_slug=String(form.get("platform")||"");
    const configs:Record<string,{resource:string;record:Record<string,unknown>}>= {
      transaction:{resource:"financial_transactions",record:{platform_slug,transaction_type:form.get("transactionType"),classification:form.get("classification"),description:form.get("description"),amount,currency:"MZN",status:"draft",occurred_at:form.get("occurredAt")}},
      payment:{resource:"payment_requests",record:{platform_slug,payee:form.get("payee"),description:form.get("description"),amount,currency:"MZN",due_at:form.get("dueAt"),status:"pending"}},
      account:{resource:"financial_accounts",record:{platform_slug,account_type:"corporate_bank",name:form.get("name"),bank_name:form.get("bankName"),masked_account_number:form.get("maskedAccount"),currency:"MZN",opening_balance:amount,current_balance:amount,status:"active"}},
      budget:{resource:"budgets",record:{platform_slug,name:form.get("name"),amount,currency:"MZN",financial_year:Number(form.get("financialYear")),period_start:form.get("periodStart")||null,period_end:form.get("periodEnd")||null,status:"draft"}},
      forecast:{resource:"cashflow_forecasts",record:{platform_slug,period_start:form.get("periodStart"),period_end:form.get("periodEnd"),expected_income:Number(form.get("expectedIncome")||0),expected_expense:Number(form.get("expectedExpense")||0),currency:"MZN"}},
    };
    setFinanceNotice("A guardar registo financeiro…"); const config=configs[financeEntryKind]; const response=await fetch("/api/finance",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(config)}); const result=await response.json(); setFinanceNotice(response.ok?"Registo guardado e auditado.":result.error); if(response.ok){setShowFinanceForm(false); await refreshFinance();}
  };
  const paymentAction = async (paymentId:string,action:"approve"|"reject"|"mark_paid") => { setFinanceNotice("A atualizar pagamento…"); const response=await fetch("/api/finance",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({paymentId,action})});const result=await response.json();setFinanceNotice(response.ok?"Pagamento atualizado e auditado.":result.error);if(response.ok)await refreshFinance(); };
  const createAccountingRecord=async(event:FormEvent<HTMLFormElement>)=>{event.preventDefault();const f=new FormData(event.currentTarget),account=String(f.get("accountId")||"");const configs:Record<string,unknown>={invoice:{resource:"accounting_invoices",record:{invoice_number:f.get("number"),direction:f.get("direction"),counterparty:f.get("counterparty"),issued_on:f.get("issuedOn"),due_on:f.get("dueOn")||null,subtotal:Number(f.get("amount")||0),tax_amount:Number(f.get("tax")||0),status:"draft"}},tax:{resource:"tax_obligations",record:{tax_type:f.get("taxType"),period_start:f.get("start"),period_end:f.get("end"),due_on:f.get("dueOn"),taxable_amount:Number(f.get("amount")||0),tax_amount:Number(f.get("tax")||0),status:"draft"}},period:{resource:"accounting_periods",record:{name:f.get("name"),starts_on:f.get("start"),ends_on:f.get("end"),status:"open"}},reconciliation:{resource:"account_reconciliations",record:{account_id:account,statement_balance:Number(f.get("statement")||0),ledger_balance:Number(f.get("ledger")||0),status:"pending"}}};setAccountingNotice("A guardar…");const response=await fetch("/api/accounting",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(configs[accountingKind])});const result=await response.json();setAccountingNotice(response.ok?"Registo contabilístico guardado.":result.error);if(response.ok){setShowAccountingForm(false);const refreshed=await fetch("/api/accounting",{cache:"no-store"});if(refreshed.ok){const data=await refreshed.json();setAccountingData(data.data||{});setAccountingReports(data.reports||{})}}};
  const createLegalRecord=async(event:FormEvent<HTMLFormElement>)=>{event.preventDefault();const f=new FormData(event.currentTarget),base={title:f.get("title")};const configs:Record<string,unknown>={document:{resource:"documents",record:{...base,category:f.get("category"),confidentiality:f.get("confidentiality"),storage_key:f.get("reference"),mime_type:f.get("mimeType"),status:"active"}},version:{resource:"legal_document_versions",record:{document_id:f.get("documentId"),version:Number(f.get("version")),storage_key:f.get("reference"),mime_type:f.get("mimeType"),change_summary:f.get("summary")}},contract:{resource:"contracts",record:{...base,counterparty:f.get("counterparty"),status:"draft",starts_on:f.get("start")||null,expires_on:f.get("end")||null}},license:{resource:"legal_licenses",record:{name:f.get("title"),authority:f.get("authority"),license_number:f.get("number"),expires_on:f.get("end")||null,status:"active"}},permit:{resource:"legal_permits",record:{name:f.get("title"),permit_type:f.get("caseType"),authority:f.get("authority"),permit_number:f.get("number"),expires_on:f.get("end")||null,status:"active"}},case:{resource:"legal_cases",record:{...base,case_number:f.get("number"),case_type:f.get("caseType"),counterparty:f.get("counterparty"),risk_level:f.get("risk"),next_deadline:f.get("deadline")||null,status:"open"}},consultation:{resource:"legal_consultations",record:{subject:f.get("title"),requester:f.get("counterparty"),counsel:f.get("authority"),summary:f.get("summary"),due_at:f.get("deadline")||null,status:"open"}},policy:{resource:"corporate_policies",record:{...base,category:f.get("category"),review_due_on:f.get("end")||null,status:"draft"}},obligation:{resource:"legal_obligations",record:{...base,obligation_type:f.get("caseType"),authority:f.get("authority"),due_on:f.get("end")||null,status:"pending"}}};setLegalNotice("A guardar…");const r=await fetch("/api/legal",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(configs[legalKind])});const result=await r.json();setLegalNotice(r.ok?"Registo jurídico guardado.":result.error);if(r.ok){setShowLegalForm(false);await refreshLegal()}};
  const inspectLegalDocument=async(id:string)=>{const r=await fetch(`/api/legal/documents/${id}`,{cache:"no-store"});const result=await r.json();if(r.ok)setLegalDocumentDetail(result);else setLegalNotice(result.error)};
  const createComplianceRecord=async(event:FormEvent<HTMLFormElement>)=>{event.preventDefault();const f=new FormData(event.currentTarget);const configs:Record<string,unknown>={
    risk:{resource:"compliance_risks",record:{title:f.get("title"),category:f.get("category"),description:f.get("description"),likelihood:Number(f.get("likelihood")),impact:Number(f.get("impact")),mitigation_plan:f.get("plan"),target_date:f.get("due"),evidence_reference:f.get("evidence")||f.get("plan"),status:"identified"}},
    control:{resource:"compliance_controls",record:{title:f.get("title"),control_type:f.get("controlType"),frequency:f.get("frequency"),effectiveness:"untested",next_test_on:f.get("due")||null,evidence_reference:f.get("evidence")||null}},
    incident:{resource:"compliance_incidents",record:{title:f.get("title"),incident_type:f.get("category"),severity:f.get("severity"),description:f.get("description"),occurred_at:f.get("occurredAt"),corrective_action:f.get("plan"),status:"open"}},
    review:{resource:"compliance_reviews",record:{title:f.get("title"),review_type:f.get("category"),scope:f.get("description"),due_on:f.get("due")||null,status:"planned"}},
    evidence:{resource:"compliance_risk_evidence",record:{risk_id:f.get("riskId"),evidence_type:f.get("category"),title:f.get("title"),reference:f.get("evidence")}},
    check:{resource:"compliance_checks",record:{title:f.get("title"),check_type:f.get("category"),scope:f.get("description"),scheduled_on:f.get("due"),evidence_reference:f.get("evidence")||null,status:"planned"}},
    continuity:{resource:"business_continuity_plans",record:{title:f.get("title"),critical_process:f.get("category"),recovery_objective:f.get("description"),recovery_time_hours:Number(f.get("recoveryHours")),next_test_on:f.get("due")||null,evidence_reference:f.get("evidence")||null,status:"draft"}},
  };setComplianceNotice("A guardar…");const r=await fetch("/api/compliance",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(configs[complianceKind])});const result=await r.json();setComplianceNotice(r.ok?"Registo de conformidade guardado.":result.error);if(r.ok){setShowComplianceForm(false);await refreshCompliance()}};
  const createTechnologyRecord=async(event:FormEvent<HTMLFormElement>)=>{event.preventDefault();const f=new FormData(event.currentTarget),title=f.get("title");const configs:Record<string,unknown>={system:{resource:"technology_systems",record:{name:title,system_type:f.get("type"),environment:f.get("environment"),base_url:f.get("endpoint")||null,status:"operational"}},integration:{resource:"technology_integrations",record:{name:title,provider:f.get("provider"),integration_type:f.get("type"),health_endpoint:f.get("endpoint")||null,secret_reference:f.get("secretReference")||null,status:"pending"}},incident:{resource:"technology_incidents",record:{title,severity:f.get("severity"),description:f.get("description"),started_at:f.get("startedAt"),status:"open"}},backup:{resource:"technology_backups",record:{backup_type:f.get("type"),storage_reference:f.get("secretReference"),started_at:f.get("startedAt"),retention_until:f.get("due")||null,status:"running"}},change:{resource:"technology_changes",record:{title,change_type:f.get("type"),risk_level:f.get("risk"),scheduled_at:f.get("startedAt")||null,rollback_plan:f.get("description"),status:"planned"}}};setTechnologyNotice("A guardar…");const r=await fetch("/api/technology",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(configs[technologyKind])});const result=await r.json();setTechnologyNotice(r.ok?"Registo técnico guardado.":result.error);if(r.ok){setShowTechnologyForm(false);await refreshTechnology()}};
  const createProcurementRecord=async(event:FormEvent<HTMLFormElement>)=>{event.preventDefault();const f=new FormData(event.currentTarget),qty=Number(f.get("quantity")||1),price=Number(f.get("price")||0);const configs:Record<string,unknown>={request:{resource:"purchase_request",record:{department_id:f.get("departmentId"),budget_id:f.get("budgetId")||null,justification:f.get("justification"),estimated_amount:qty*price,currency:"MZN"},items:[{description:f.get("item"),quantity:qty,unit:f.get("unit")||"un",estimated_unit_price:price}]},supplier:{resource:"suppliers",record:{name:f.get("supplierName"),tax_number:f.get("taxNumber"),email:f.get("email"),status:"active"}},quote:{resource:"supplier_quotes",record:{purchase_request_id:f.get("purchaseRequestId"),supplier_id:f.get("supplierId"),quote_reference:f.get("reference"),total_amount:Number(f.get("amount")),valid_until:f.get("due")||null,document_reference:f.get("documentReference")||null}},order:{resource:"purchase_orders",record:{purchase_request_id:f.get("purchaseRequestId"),supplier_id:f.get("supplierId"),total_amount:Number(f.get("amount")),expected_on:f.get("due")||null,status:"issued"}},receipt:{resource:"goods_receipts",record:{purchase_order_id:f.get("orderId"),received_at:f.get("receivedAt"),status:"accepted",notes:f.get("justification"),document_reference:f.get("documentReference")||null}},invoice:{resource:"procurement_invoices",record:{purchase_order_id:f.get("orderId"),goods_receipt_id:f.get("receiptId"),invoice_number:f.get("reference"),amount:Number(f.get("amount")),issued_on:f.get("issuedOn"),due_on:f.get("due"),document_reference:f.get("documentReference")||null,payee:f.get("supplierName")}}};setProcurementNotice("A processar etapa…");const r=await fetch("/api/procurement",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(configs[procurementKind])});const result=await r.json();setProcurementNotice(r.ok?"Etapa guardada no histórico.":result.error);if(r.ok){setShowProcurementForm(false);await refreshProcurement()}};
  const procurementAction=async(action:string,purchaseRequestId:string,quoteId?:string)=>{setProcurementNotice("A validar etapa…");const r=await fetch("/api/procurement",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({action,purchaseRequestId,quoteId})});const result=await r.json();setProcurementNotice(r.ok?"Compra atualizada.":result.error);if(r.ok)await refreshProcurement()};
  const createMarketingRecord=async(event:FormEvent<HTMLFormElement>)=>{event.preventDefault();const f=new FormData(event.currentTarget),campaignId=f.get("campaignId"),platform_slug=f.get("platform")||null;const configs:Record<string,unknown>={campaign:{resource:"campaign",platforms:f.getAll("platforms"),record:{title:f.get("title"),objective:f.get("objective"),target_audience:{description:f.get("audience")},budget_amount:Number(f.get("budget")||0),currency:"MZN",starts_at:f.get("start")||null,ends_at:f.get("end")||null}},channel:{resource:"channel",record:{campaign_id:campaignId,channel:f.get("channel"),account_reference:f.get("reference")||null,status:"planned"}},content:{resource:"content",record:{campaign_id:campaignId,platform_slug,title:f.get("title"),content_type:f.get("contentType"),scheduled_at:f.get("scheduledAt"),status:"scheduled"}},promotion:{resource:"promotion",record:{campaign_id:campaignId,platform_slug,code:f.get("code"),discount_type:f.get("discountType"),discount_value:Number(f.get("discount")||0),starts_at:f.get("start")||null,ends_at:f.get("end")||null,status:"draft"}},creative:{resource:"creative",record:{campaign_id:campaignId,title:f.get("title"),creative_type:f.get("contentType"),storage_reference:f.get("reference"),status:"draft"}},lead:{resource:"lead",record:{campaign_id:campaignId,platform_slug,external_reference:f.get("reference")||null,source_channel:f.get("channel"),status:f.get("leadStatus")}},metric:{resource:"metric",record:{campaign_id:campaignId,platform_slug,metric_date:f.get("metricDate"),impressions:Number(f.get("impressions")||0),clicks:Number(f.get("clicks")||0),leads:Number(f.get("leads")||0),conversions:Number(f.get("conversions")||0),spend:Number(f.get("spend")||0)}}};setMarketingNotice("A guardar no backend…");const r=await fetch("/api/marketing",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(configs[marketingKind])});const result=await r.json();setMarketingNotice(r.ok?"Registo de marketing guardado e auditado.":result.error);if(r.ok){setShowMarketingForm(false);await refreshMarketing()}};
  const marketingAction=async(campaignId:string,action:string)=>{setMarketingNotice("A validar aprovação e estado…");const r=await fetch("/api/marketing",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({campaignId,action})});const result=await r.json();setMarketingNotice(r.ok?"Campanha atualizada com sucesso.":result.error);if(r.ok)await refreshMarketing()};
  const createFieldRecord=async(event:FormEvent<HTMLFormElement>)=>{event.preventDefault();const f=new FormData(event.currentTarget),visitId=f.get("visitId");const configs:Record<string,unknown>={visit:{resource:"visit",record:{platform_slug:f.get("platform"),worker_id:f.get("workerId"),subject:f.get("subject"),visit_type:f.get("visitType"),priority:f.get("priority"),address:f.get("address"),planned_at:f.get("plannedAt"),location_authorized:f.get("locationAuthorized")==="on",latitude:f.get("latitude")?Number(f.get("latitude")):null,longitude:f.get("longitude")?Number(f.get("longitude")):null,evidence_required:f.get("evidenceRequired")==="on"}},checklist:{resource:"checklist",record:{visit_id:visitId,title:f.get("title"),is_required:f.get("required")==="on",status:f.get("checkStatus"),notes:f.get("notes")||null}},evidence:{resource:"evidence",record:{visit_id:visitId,evidence_type:f.get("evidenceType"),storage_reference:f.get("reference"),latitude:f.get("latitude")?Number(f.get("latitude")):null,longitude:f.get("longitude")?Number(f.get("longitude")):null}},report:{resource:"report",record:{visit_id:visitId,summary:f.get("summary"),outcome:f.get("outcome"),follow_up_required:f.get("followUp")==="on",follow_up_due:f.get("followUpDue")||null}}};setFieldNotice("A guardar operação Field…");const r=await fetch("/api/field",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(configs[fieldKind])});const result=await r.json();setFieldNotice(r.ok?"Operação Field guardada e auditada.":result.error);if(r.ok){setShowFieldForm(false);await refreshField()}};
  const fieldAction=async(visitId:string,action:string)=>{setFieldNotice("A validar a missão…");const r=await fetch("/api/field",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({visitId,action})});const result=await r.json();setFieldNotice(r.ok?"Missão atualizada.":result.error);if(r.ok)await refreshField()};
  const exportAudit = () => { const anchor=document.createElement("a"); anchor.href="/api/audit/export"; anchor.download="deligo-auditoria.csv"; document.body.appendChild(anchor); anchor.click(); anchor.remove(); };

  useEffect(() => {
    const syncRoute = () => {
      const platformMatch = window.location.pathname.match(/^\/plataformas\/(deligo|comunhao|sarca|taomoz)$/);
      const nextModule = platformMatch ? "Plataformas" : moduleByRoute[window.location.pathname] || "Visão geral";
      setActive(nextModule);
      if (platformMatch) setPlatform(({ deligo: "DeliGo", comunhao: "Comunhão", sarca: "SARCA", taomoz: "TaoMoz" } as const)[platformMatch[1] as "deligo" | "comunhao" | "sarca" | "taomoz"]);
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

  useEffect(() => {
    const slug = platform === "Todas as plataformas" ? "" : platformSlug(platform);
    if (!slug || active !== "Plataformas") { setPlatformAdminSnapshot(null); setPlatformAdminError(""); return; }
    setPlatformAdminError("");
    fetch(`/api/platforms/${slug}`, { cache: "no-store" }).then(async response => { const result = await response.json(); if (!response.ok) throw new Error(result.error || "Falha ao sincronizar a plataforma."); return result as PlatformAdminSnapshot; }).then(result => setPlatformAdminSnapshot(result)).catch(error => setPlatformAdminError(error instanceof Error ? error.message : "Falha ao sincronizar a plataforma."));
  }, [active, platform]);

  const platformAction = async (action: string, decision: "approve" | "reject" | "correction", id: string, reason = "") => {
    const slug = platformSlug(platform);
    const response = await fetch(`/api/platforms/${slug}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action, decision, id, reason }) });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "Acção não concluída.");
    const refreshed = await fetch(`/api/platforms/${slug}`, { cache: "no-store" });
    if (refreshed.ok) setPlatformAdminSnapshot(await refreshed.json() as PlatformAdminSnapshot);
    setPlatformAdminError("Decisão concluída e auditada.");
  };

  useEffect(() => {
    if (!selectedProfile) { setProfileDetail(null); return; }
    fetch(`/api/platforms/${selectedProfile.platform}/${encodeURIComponent(selectedProfile.id)}`, { cache: "no-store" })
      .then(async response => { const result = await response.json(); if (!response.ok) throw new Error(result.error || "Falha ao abrir o perfil."); return result as PlatformProfile; })
      .then(setProfileDetail).catch(() => setProfileDetail(null));
  }, [selectedProfile]);


  useEffect(() => {
    if (active !== "Plataformas" || platform === "Todas as plataformas") { setPlatformSnapshot(null); return; }
    const slug = ({ DeliGo: "deligo", "ComunhÃ£o": "comunhao", SARCA: "sarca", TaoMoz: "taomoz" } as Record<string, string>)[platform];
    if (!slug) return;
    fetch(`/api/platforms/${slug}`, { cache: "no-store" }).then(async response => { if (!response.ok) throw new Error(); return response.json() as Promise<PlatformSnapshot>; }).then(setPlatformSnapshot).catch(() => setPlatformSnapshot(null));
  }, [active, platform]);

  const navigate = (label: string) => {
    setActive(label);
    setSubArea(moduleDetails[label]?.[0] || "");
    setMenuOpen(false);
    window.history.pushState({}, "", routeByModule[label] || "/");
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const visibleCards = useMemo(
    () => {
      const cards = dashboard?.platforms.map((item) => ({
        ...item,
        color: platformCards.find((card) => card.name === item.name)?.color || "#667085",
      })) || [];
      return platform === "Todas as plataformas" ? cards : cards.filter((item) => item.name === platform);
    },
    [dashboard?.platforms, platform],
  );
  const totalUsers = dashboard?.platforms.reduce((sum, item) => {
    const users = item.metrics.find((metric) => ["users", "members", "buyers", "passengers"].includes(metric.key));
    return sum + (users?.value || 0);
  }, 0) || 0;
  const selectedPlatformModule = dashboard?.modules.platforms.find((item) => item.name === platform);
  const selectedPlatformStatus = dashboard?.platforms.find((item) => item.name === platform);
  const platformDirectory = (dashboard?.platforms || []).map((item) => ({
    ...item,
    value: dashboard?.modules.platforms.find((module) => module.name === item.name)?.value || 0,
  }));
  const shownPeople = (selectedPlatformModule?.people || []).filter((person) => person.name.toLocaleLowerCase("pt").includes(peopleSearch.toLocaleLowerCase("pt")));
  const money = (value: number) => new Intl.NumberFormat("pt-MZ", { style: "currency", currency: "MZN", maximumFractionDigits: 2 }).format(value || 0);
  const selectedFinancialPlatforms = dashboard?.modules.platforms.filter((item) => platform === "Todas as plataformas" || item.name === platform) || [];
  const selectedOperationalValue = selectedFinancialPlatforms.reduce((sum, item) => sum + item.value, 0);
  const connectedPlatforms = dashboard?.platforms.filter((item) => item.connected).length || 0;
  const operationalItems = [
    { label: "Suporte", value: dashboard?.operations.supportCases || 0, note: "casos registados", action: "Apoio ao Cliente" },
    { label: "Field", value: dashboard?.operations.fieldVisits || 0, note: "visitas registadas", action: "Field" },
    { label: "Marketing", value: dashboard?.operations.campaigns || 0, note: "campanhas registadas", action: "Marketing" },
    { label: "Auditoria", value: dashboard?.operations.auditEvents || 0, note: "eventos no histórico", action: "Registo de Auditoria" },
  ];
  const mapMarkers = (liveMap?.markers || []).filter((marker) => platform === "Todas as plataformas" || marker.platform === platform);
  const filteredMapMarkers = mapMarkers.filter((marker) => (mapStatus === "todos" || marker.status === mapStatus) && `${marker.workerName || ""} ${marker.workerId || marker.id}`.toLocaleLowerCase("pt").includes(mapSearch.toLocaleLowerCase("pt")));
  const shownEmployees = managedEmployees.filter((employee) => `${employee.name} ${employee.employee_code} ${employee.department} ${employee.job_title}`.toLocaleLowerCase("pt").includes(employeeSearch.toLocaleLowerCase("pt")));
  const financePlatformIds:Record<string,string>={DeliGo:"20000000-0000-0000-0000-000000000001",Comunhão:"20000000-0000-0000-0000-000000000002",TaoMoz:"20000000-0000-0000-0000-000000000003",SARCA:"20000000-0000-0000-0000-000000000004"};
  const financeFilter=(rows:FinanceRecord[])=>platform==="Todas as plataformas"?rows:rows.filter(row=>row.platform_id===financePlatformIds[platform]);
  const financeAccounts=financeFilter(financeData.financial_accounts); const financeTransactions=financeFilter(financeData.financial_transactions); const financePayments=financeFilter(financeData.payment_requests); const financeBudgets=financeFilter(financeData.budgets); const financeForecasts=financeFilter(financeData.cashflow_forecasts);
  const treasuryBalance=financeAccounts.reduce((sum,row)=>sum+Number(row.current_balance||0),0); const recognizedIncome=financeTransactions.filter(row=>row.transaction_type==="income"&&["posted","reconciled"].includes(row.status||"")).reduce((sum,row)=>sum+Number(row.amount||0),0); const recognizedExpense=financeTransactions.filter(row=>row.transaction_type==="expense"&&["posted","reconciled"].includes(row.status||"")).reduce((sum,row)=>sum+Number(row.amount||0),0); const pendingPayments=financePayments.filter(row=>["pending","approved"].includes(row.status||"")); const pendingPaymentTotal=pendingPayments.reduce((sum,row)=>sum+Number(row.amount||0),0); const paidTotal=financePayments.filter(row=>row.status==="paid").reduce((sum,row)=>sum+Number(row.amount||0),0); const budgetTotal=financeBudgets.reduce((sum,row)=>sum+Number(row.amount||0),0); const forecastNet=financeForecasts.reduce((sum,row)=>sum+Number(row.expected_income||0)-Number(row.expected_expense||0),0);

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
            {sessionRole === "SUPER_ADMIN" && <label className="viewAs">
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
                <option value="marketing">Marketing</option>
                <option value="field">Field</option>
                <option value="support">Suporte</option>
                <option value="hr">Recursos Humanos</option>
                <option value="legal">Jurídico</option>
                <option value="operations">Operações</option>
                <option value="acquisition">Aquisição</option>
                <option value="ambassador">Embaixador</option>
                <option value="procurement">Compras</option>
                <option value="assets">Património</option>
              </select>
            </label>}
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
              <div className="accountMenuGroup"><button className="logout" onClick={async () => { await fetch("/api/auth/logout", { method: "POST" }); window.location.assign("/login"); }}><span>↪</span>Terminar sessão</button></div>
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
          {active === "Plataformas" && (
            <section className="platformDirectory" aria-label="Plataformas do grupo">
              <div className="platformDirectoryHead"><div><span>PORTFÓLIO DIGITAL</span><h2>Quatro plataformas, operações separadas</h2><p>Abra uma plataforma para ver apenas os seus utilizadores, operações, integrações, equipa e incidentes.</p></div><b>{connectedPlatforms}/4 ligadas</b></div>
              <div className="platformDirectoryGrid">
                {platformDirectory.map((item) => {
                  const users = metricFor(item, ["utilizador", "membro", "comprador", "passageiro"]);
                  const operations = metricFor(item, ["pedido", "evento", "viagem", "serviço", "operaç"]);
                  return <button className={`platformDirectoryCard ${platform === item.name ? "selected" : ""}`} key={item.slug} onClick={() => { setPlatform(item.name); setSubArea("Resumo"); }}>
                    <div><i style={{ background: platformCards.find((card) => card.name === item.name)?.color || "#555" }}>{item.name.slice(0, 2).toUpperCase()}</i><span className={item.connected ? "connectedPill" : "warningPill"}>{item.connected ? "Ligada" : "A verificar"}</span></div>
                    <h3>{item.name}</h3><p>{operationalLabel(item.name)} e dados próprios no backend central.</p>
                    <dl><div><dt>Utilizadores</dt><dd>{users}</dd></div><div><dt>{operationalLabel(item.name)}</dt><dd>{operations}</dd></div><div><dt>Volume observado</dt><dd>{money(item.value)}</dd></div></dl>
                    <strong>Abrir painel da plataforma <ChevronRight aria-hidden="true" /></strong>
                  </button>;
                })}
              </div>
            </section>
          )}
          {active === "Plataformas" && selectedPlatformModule && (
            <section className="platformModule">
              <div className="platformModuleHero">
                <div><span>MÓDULO DA PLATAFORMA</span><h2>{selectedPlatformModule.name}</h2><p>Painel administrativo adaptado ao HQ, com dados agregados do schema dedicado.</p></div>
                <div className="platformValue"><span>Valor total processado</span><strong>{money(selectedPlatformModule.value)}</strong><small>Volume operacional · não representa lucro</small></div>
              </div>
              <div className="platformControlGrid">
                <article><span>Estado</span><strong className={selectedPlatformStatus?.connected ? "connectedPill" : "warningPill"}>{selectedPlatformStatus?.connected ? "Operacional" : "A verificar"}</strong><small>Ligação ao backend específico</small></article>
                <article><span>Utilizadores</span><strong>{metricFor(selectedPlatformStatus, ["utilizador", "membro", "comprador", "passageiro"])}</strong><small>Registos da plataforma</small></article>
                <article><span>{operationalLabel(selectedPlatformModule.name)}</span><strong>{metricFor(selectedPlatformStatus, ["pedido", "evento", "viagem", "serviço", "operaç"])}</strong><small>Operações realizadas</small></article>
                <article><span>Incidentes</span><strong>{recordsFor(platformSnapshot, "support") + recordsFor(platformSnapshot, "disputes")}</strong><small>Suporte e disputas registadas</small></article>
                <article><span>Integrações</span><strong>{Object.values(platformSnapshot?.data || {}).filter(Array.isArray).length}</strong><small>Fontes ligadas ao HQ</small></article>
                <article><span>{teamLabel(selectedPlatformModule.name)}</span><strong>{teamValue(selectedPlatformStatus, selectedPlatformModule.name)}</strong><small>Equipa ou rede operacional</small></article>
              </div>
              <div className="moduleToolbar">
                <div className="moduleTabs"><button className="active">Resumo</button><button>Utilizadores</button><button>Operações</button><button>Financeiro</button><button>Auditoria</button></div>
                <input value={peopleSearch} onChange={(event) => setPeopleSearch(event.target.value)} placeholder={`Pesquisar pessoas em ${selectedPlatformModule.name}…`} aria-label="Pesquisar utilizadores" />
              </div>
              {platformSnapshot && <div className="peoplePanel"><div className="peoplePanelHead"><div><h3>Estado administrativo ligado</h3><p>Dados reais do backend dedicado de {selectedPlatformModule.name}.</p></div><b>{Object.values(platformSnapshot.data).filter(Array.isArray).length} fontes</b></div><div className="peopleTable"><div className="peopleRow peopleHeader"><span>Fonte</span><span>Registos</span><span>Estado</span><span>Actualização</span></div>{Object.entries(platformSnapshot.data).map(([source, value]) => <div className="peopleRow" key={source}><span className="personIdentity"><i>{source.slice(0, 2).toUpperCase()}</i><strong>{source.replaceAll("_", " ")}</strong></span><span>{Array.isArray(value) ? value.length : "—"}</span><span className="connectedPill">Backend real</span><span>{new Date(platformSnapshot.checkedAt).toLocaleTimeString("pt-MZ", { hour: "2-digit", minute: "2-digit" })}</span></div>)}</div></div>}
              <div className="peoplePanel">
                <div className="peoplePanelHead"><div><h3>Utilizadores recentes</h3><p>Nomes reais disponíveis no backend central.</p></div><b>{shownPeople.length} resultados</b></div>
                <div className="peopleTable">
                  <div className="peopleRow peopleHeader"><span>Utilizador</span><span>Função</span><span>Registo</span><span>Estado</span></div>
                  {shownPeople.map((person) => <button className="peopleRow" key={person.id}><span className="personIdentity"><i>{person.name.split(" ").slice(0,2).map((part) => part[0]).join("")}</i><strong>{person.name}</strong></span><span className="rolePill">{person.role.replaceAll("_", " ")}</span><span>{new Date(person.created_at).toLocaleDateString("pt-MZ")}</span><span className="connectedPill">Activo</span></button>)}
                  {!shownPeople.length && <div className="peopleEmpty">Nenhum utilizador corresponde à pesquisa.</div>}
                </div>
              </div>
              {platformAdminError && <div className="operationalNotice">{platformAdminError}</div>}
              {platformAdminSnapshot && <><button className="profileQuickOpen" onClick={() => { const first = Object.values(platformAdminSnapshot.data).find(value => Array.isArray(value) && value.length) as Record<string,unknown>[] | undefined; const row = first?.[0]; if (row) { const id = String(row.id || row.user_id || row.profile_id || "0"); setSelectedProfile({ platform: platformSlug(platform), id, name: String(row.full_name || row.name || row.church_name || row.store_name || id) }); } }}>Abrir primeiro perfil com saldo e galeria</button><PlatformAdminPanel snapshot={platformAdminSnapshot} platform={platform} onAction={platformAction} onOpenProfile={(id, name) => setSelectedProfile({ platform: platformSlug(platform), id, name })} /></>}
            </section>
          )}
          {active === "Finanças" && (
            <section className="financeWorkspace">
              <div className="financeHero">
                <div><span>SALDO DE TESOURARIA CORPORATIVA</span><strong>{money(treasuryBalance)}</strong><small>{platform} · soma das contas corporativas registadas no HQ.</small></div>
                <div className="financeGuard"><ShieldCheck aria-hidden="true" /><div><b>Separação financeira activa</b><span>Carteiras de utilizadores não são tratadas como dinheiro da empresa.</span></div></div>
              </div>
              <div className="financeKpis">
                {[ ["Receitas reconhecidas",recognizedIncome,"lançamentos publicados"], ["Despesas reconhecidas",recognizedExpense,"lançamentos publicados"], ["Pagamentos pendentes",pendingPaymentTotal,`${pendingPayments.length} pedidos`], ["Pagamentos realizados",paidTotal,"registos pagos"], ["Orçamento",budgetTotal,"período seleccionado"], ["Previsão líquida",forecastNet,"entradas menos saídas"] ].map(([label,value,note])=><article key={String(label)}><span>{label}</span><strong>{money(Number(value))}</strong><small>{note}</small></article>)}
              </div>
              <div className="financeToolbar"><div><h2>Controlo financeiro</h2><p>Contas, movimentos, pagamentos, orçamentos e previsões consolidados ou por plataforma.</p></div><button className="primaryAction" onClick={()=>setShowFinanceForm(!showFinanceForm)}>{showFinanceForm?"Fechar":"Novo registo"}</button></div>
              {showFinanceForm&&<form className="financeEntryForm" onSubmit={createFinanceRecord}>
                <label><span>Tipo de registo</span><select value={financeEntryKind} onChange={event=>setFinanceEntryKind(event.target.value)}>{[["transaction","Entrada ou saída"],["payment","Pagamento pendente"],["account","Conta bancária"],["budget","Orçamento"],["forecast","Previsão financeira"]].map(([value,label])=><option value={value} key={value}>{label}</option>)}</select></label>
                <label><span>Plataforma</span><select name="platform"><option value="">Consolidado / empresa</option><option value="deligo">DeliGo</option><option value="comunhao">Comunhão</option><option value="taomoz">TaoMoz</option><option value="sarca">SARCA</option></select></label>
                {financeEntryKind==="transaction"&&<><label><span>Movimento</span><select name="transactionType"><option value="income">Entrada / receita</option><option value="expense">Saída / despesa</option><option value="transfer">Transferência interna</option></select></label><label><span>Classificação</span><input name="classification" required/></label><label><span>Descrição</span><input name="description" required/></label><label><span>Valor (MZN)</span><input name="amount" type="number" min="0.01" step="0.01" required/></label><label><span>Data</span><input name="occurredAt" type="datetime-local" required/></label></>}
                {financeEntryKind==="payment"&&<><label><span>Beneficiário</span><input name="payee" required/></label><label><span>Descrição</span><input name="description" required/></label><label><span>Valor (MZN)</span><input name="amount" type="number" min="0.01" step="0.01" required/></label><label><span>Vencimento</span><input name="dueAt" type="datetime-local"/></label></>}
                {financeEntryKind==="account"&&<><label><span>Nome da conta</span><input name="name" required/></label><label><span>Banco</span><input name="bankName" required/></label><label><span>Número mascarado</span><input name="maskedAccount" placeholder="**** 1234" required/></label><label><span>Saldo inicial (MZN)</span><input name="amount" type="number" step="0.01" required/></label></>}
                {financeEntryKind==="budget"&&<><label><span>Nome do orçamento</span><input name="name" required/></label><label><span>Valor (MZN)</span><input name="amount" type="number" min="0" step="0.01" required/></label><label><span>Ano financeiro</span><input name="financialYear" type="number" defaultValue={new Date().getFullYear()} required/></label><label><span>Início</span><input name="periodStart" type="date"/></label><label><span>Fim</span><input name="periodEnd" type="date"/></label></>}
                {financeEntryKind==="forecast"&&<><label><span>Entradas previstas</span><input name="expectedIncome" type="number" min="0" step="0.01" required/></label><label><span>Saídas previstas</span><input name="expectedExpense" type="number" min="0" step="0.01" required/></label><label><span>Início</span><input name="periodStart" type="date" required/></label><label><span>Fim</span><input name="periodEnd" type="date" required/></label></>}
                <button className="primaryAction" type="submit">Guardar e auditar</button>
              </form>}
              <div className="financeColumns">
                <article className="financePanel"><div className="panelTitle"><div><h2>Contas e saldos</h2><p>{financeAccounts.length} contas no contexto actual</p></div></div>{financeAccounts.slice(0,8).map(account=><div className="financeLine" key={account.id}><div><strong>{String(account.name||"Conta corporativa")}</strong><span>{String(account.bank_name||"Caixa")} · {String(account.masked_account_number||"sem número exposto")}</span></div><b>{money(Number(account.current_balance||0))}</b></div>)}{!financeAccounts.length&&<div className="peopleEmpty">Sem contas corporativas registadas.</div>}</article>
                <article className="financePanel"><div className="panelTitle"><div><h2>Aprovação de despesas</h2><p>Solicitante e aprovador devem ser pessoas distintas</p></div></div>{pendingPayments.slice(0,8).map(payment=><div className="financePayment" key={payment.id}><div><strong>{payment.payee||"Beneficiário"}</strong><span>{payment.description||"Pagamento"} · {money(Number(payment.amount||0))}</span></div><b>{payment.status}</b><div><button onClick={()=>void paymentAction(payment.id,"approve")} disabled={payment.status!=="pending"}>Aprovar</button><button onClick={()=>void paymentAction(payment.id,"reject")}>Rejeitar</button><button onClick={()=>void paymentAction(payment.id,"mark_paid")} disabled={payment.status!=="approved"}>Marcar pago</button></div></div>)}{!pendingPayments.length&&<div className="peopleEmpty">Sem pagamentos pendentes.</div>}</article>
              </div>
              <div className="financialBreakdown"><article><span>Volume operacional observado</span><strong>{money(selectedOperationalValue)}</strong><small>Não é receita contabilística</small></article>{selectedFinancialPlatforms.map(item=><article key={item.slug}><span>{item.name}</span><strong>{money(item.value)}</strong><small>Volume bruto observado</small></article>)}</div>
              {financeNotice&&<div className="operationalNotice">{financeNotice}</div>}
              <div className="safeNotice"><b>Controlo protegido</b><span>O HQ regista e aprova; “marcar pago” não movimenta dinheiro no banco nem executa Vodacom/Movitel. Distribuição de lucros continua sujeita à governação societária.</span></div>
            </section>
          )}
          {active === "Contabilidade"&&<section className="accountingWorkspace">
            <div className="accountingHero"><div><span>MOTOR CONTABILÍSTICO</span><h2>Diário, razão e demonstrações</h2><p>Operações financeiras contabilizáveis alimentam automaticamente lançamentos equilibrados e idempotentes.</p></div><div><button onClick={()=>setShowAccountingForm(!showAccountingForm)}>Novo registo</button><button onClick={()=>window.location.assign("/api/accounting/export")}>Exportar CSV</button></div></div>
            {showAccountingForm&&<form className="financeEntryForm" onSubmit={createAccountingRecord}><label><span>Tipo</span><select value={accountingKind} onChange={e=>setAccountingKind(e.target.value)}><option value="invoice">Fatura / conta</option><option value="tax">Imposto</option><option value="period">Período contabilístico</option><option value="reconciliation">Reconciliação bancária</option></select></label>{accountingKind==="invoice"&&<><label><span>Número</span><input name="number" required/></label><label><span>Natureza</span><select name="direction"><option value="payable">Conta a pagar</option><option value="receivable">Conta a receber</option></select></label><label><span>Contraparte</span><input name="counterparty" required/></label><label><span>Emissão</span><input name="issuedOn" type="date" required/></label><label><span>Vencimento</span><input name="dueOn" type="date"/></label><label><span>Subtotal</span><input name="amount" type="number" min="0" step=".01" required/></label><label><span>Imposto</span><input name="tax" type="number" min="0" step=".01" defaultValue="0"/></label></>}{accountingKind==="tax"&&<><label><span>Tipo de imposto</span><input name="taxType" required/></label><label><span>Início</span><input name="start" type="date" required/></label><label><span>Fim</span><input name="end" type="date" required/></label><label><span>Vencimento</span><input name="dueOn" type="date" required/></label><label><span>Base tributável</span><input name="amount" type="number" min="0" step=".01" required/></label><label><span>Imposto</span><input name="tax" type="number" min="0" step=".01" required/></label></>}{accountingKind==="period"&&<><label><span>Nome</span><input name="name" required/></label><label><span>Início</span><input name="start" type="date" required/></label><label><span>Fim</span><input name="end" type="date" required/></label></>}{accountingKind==="reconciliation"&&<><label><span>Conta</span><select name="accountId" required>{(accountingData.chart_of_accounts||[]).map(a=><option value={a.id} key={a.id}>{String(a.code)} · {String(a.name)}</option>)}</select></label><label><span>Saldo extrato</span><input name="statement" type="number" step=".01" required/></label><label><span>Saldo razão</span><input name="ledger" type="number" step=".01" required/></label></>}<button className="primaryAction" type="submit">Guardar</button></form>}
            <div className="financeKpis">{[["Plano de contas",accountingData.chart_of_accounts?.length||0],["Diário",accountingData.journal_entries?.length||0],["Contas a pagar",(accountingData.accounting_invoices||[]).filter(i=>i.direction==="payable"&&i.status!=="paid").length],["Contas a receber",(accountingData.accounting_invoices||[]).filter(i=>i.direction==="receivable"&&i.status!=="paid").length],["Faturas",accountingData.accounting_invoices?.length||0],["Impostos",accountingData.tax_obligations?.length||0]].map(([l,v])=><article key={String(l)}><span>{l}</span><strong>{v}</strong><small>registos protegidos</small></article>)}</div>
            <div className="accountingStatements">{[["Receitas",accountingReports.revenue],["Despesas",accountingReports.expense],["Resultado líquido",accountingReports.netIncome],["Ativos",accountingReports.assets],["Passivos",accountingReports.liabilities],["Capital próprio",accountingReports.equity],["Fluxo de caixa",accountingReports.cashflow]].map(([l,v])=><article key={String(l)}><span>{l}</span><strong>{money(Number(v||0))}</strong></article>)}</div>
            <div className="accountingGrid"><article><h3>Plano de contas e balancete</h3>{((accountingReports.trialBalance as Array<Record<string,unknown>>)||accountingData.chart_of_accounts||[]).map(a=><div className="accountingRow" key={String(a.code||a.id)}><b>{String(a.code)}</b><span>{String(a.name)}</span><em>{a.balance===undefined?String(a.account_class):money(Number(a.balance))}</em></div>)}</article><article><h3>Diário contabilístico</h3>{(accountingData.journal_entries||[]).slice(0,10).map(e=><div className="accountingRow" key={e.id}><b>#{String(e.entry_number||"—")}</b><span>{String(e.description)}<small>{String(e.entry_date||"")}</small></span><em>{String(e.status)}</em></div>)}{!accountingData.journal_entries?.length&&<div className="peopleEmpty">Sem lançamentos contabilísticos.</div>}</article></div>
            <div className="accountingGrid"><article><h3>Reconciliação bancária</h3><div className="accountingRule"><CheckCircle2/><span>{accountingData.account_reconciliations?.length||0} reconciliações · dupla validação activa</span></div></article><article><h3>Períodos e impostos</h3><div className="accountingRule"><CheckCircle2/><span>{accountingData.accounting_periods?.length||0} períodos · {accountingData.tax_obligations?.length||0} obrigações fiscais</span></div></article></div>
            <div className="safeNotice"><b>Integridade contabilística</b><span>Pagamentos marcados como pagos e movimentos publicados/reconciliados geram diário e razão automaticamente. Operações em rascunho não alteram demonstrações; impostos não são submetidos automaticamente.</span></div>
            {accountingNotice&&<div className="operationalNotice">{accountingNotice}</div>}
          </section>}
          {active === "Jurídico"&&<section className="legalWorkspace"><div className="legalHero"><div><span>GOVERNAÇÃO JURÍDICA</span><h2>Arquivo, processos e prazos legais</h2><p>Informação jurídica restrita, organizada por entidade e plataforma.</p></div><button onClick={()=>setShowLegalForm(!showLegalForm)}>Novo registo</button></div><div className="financeKpis">{[["Contratos",legalData.contracts?.length||0],["Documentos",legalData.documents?.length||0],["Licenças",legalData.legal_licenses?.length||0],["Processos",legalData.legal_cases?.length||0],["Políticas",legalData.corporate_policies?.length||0],["Obrigações",legalData.legal_obligations?.length||0]].map(([l,v])=><article key={String(l)}><span>{l}</span><strong>{v}</strong><small>registos protegidos</small></article>)}</div>{showLegalForm&&<form className="financeEntryForm" onSubmit={createLegalRecord}><label><span>Tipo</span><select value={legalKind} onChange={e=>setLegalKind(e.target.value)}><option value="contract">Contrato</option><option value="license">Licença</option><option value="case">Processo</option><option value="policy">Política</option><option value="obligation">Obrigação legal</option></select></label><label><span>Título</span><input name="title" required/></label>{["contract","case"].includes(legalKind)&&<label><span>Contraparte</span><input name="counterparty"/></label>}{["license","case"].includes(legalKind)&&<label><span>Número</span><input name="number"/></label>}{["license","obligation"].includes(legalKind)&&<label><span>Autoridade</span><input name="authority"/></label>}{legalKind==="case"&&<><label><span>Tipo de processo</span><input name="caseType" required/></label><label><span>Risco</span><select name="risk"><option value="low">Baixo</option><option value="medium">Médio</option><option value="high">Alto</option><option value="critical">Crítico</option></select></label><label><span>Próximo prazo</span><input name="deadline" type="datetime-local"/></label></>}{legalKind==="policy"&&<label><span>Categoria</span><input name="category" required/></label>}{legalKind==="obligation"&&<label><span>Tipo de obrigação</span><input name="caseType" required/></label>}{legalKind==="contract"&&<label><span>Início</span><input name="start" type="date"/></label>}<label><span>{legalKind==="contract"?"Fim / renovação":"Prazo / revisão"}</span><input name="end" type="date"/></label><button className="primaryAction">Guardar</button></form>}<div className="legalGrid"><article><h3>Processos e prazos</h3>{(legalData.legal_cases||[]).slice(0,8).map(item=><div className="legalRow" key={item.id}><div><strong>{String(item.title)}</strong><span>{String(item.case_number||"Sem número")} · {String(item.counterparty||"Sem contraparte")}</span></div><b>{String(item.risk_level)}</b><em>{item.next_deadline?new Date(String(item.next_deadline)).toLocaleDateString("pt-MZ"):"Sem prazo"}</em></div>)}{!legalData.legal_cases?.length&&<div className="peopleEmpty">Sem processos ativos.</div>}</article><article><h3>Licenças e obrigações</h3>{[...(legalData.legal_licenses||[]),...(legalData.legal_obligations||[])].slice(0,8).map(item=><div className="legalRow" key={item.id}><div><strong>{String(item.name||item.title)}</strong><span>{String(item.authority||"Entidade interna")}</span></div><b>{String(item.status)}</b><em>{String(item.expires_on||item.due_on||"Sem prazo")}</em></div>)}{!(legalData.legal_licenses?.length||legalData.legal_obligations?.length)&&<div className="peopleEmpty">Sem licenças ou obrigações registadas.</div>}</article></div>{legalNotice&&<div className="operationalNotice">{legalNotice}</div>}<div className="safeNotice"><b>Confidencialidade jurídica</b><span>Documentos, contratos e processos são carregados apenas para Jurídico e Super Admin; outros perfis recebem somente indicadores autorizados.</span></div></section>}
          {active==="Jurídico"&&<section className="legalArchiveControls"><div className="legalArchiveHead"><div><span>ARQUIVO LEGAL CONTROLADO</span><h2>Documentos, versões e consultas</h2><p>Caminhos internos dos ficheiros não são enviados na listagem geral.</p></div><div>{[["document","Novo documento"],["version","Nova versão"],["permit","Novo alvará"],["consultation","Nova consulta"]].map(([kind,label])=><button key={kind} onClick={()=>{setLegalKind(kind);setShowLegalArchiveForm(true)}}>{label}</button>)}</div></div><div className="financeKpis">{[["Alvarás",legalData.legal_permits?.length||0],["Consultas",legalData.legal_consultations?.length||0],["Versões",legalData.legal_document_versions?.length||0],["Consultas registadas",legalData.legal_document_access_log?.length||0]].map(([l,v])=><article key={String(l)}><span>{l}</span><strong>{v}</strong><small>controlo jurídico</small></article>)}</div>{showLegalArchiveForm&&<form className="financeEntryForm" onSubmit={createLegalRecord}>{legalKind!=="version"&&<label><span>Título</span><input name="title" required/></label>}{legalKind==="document"&&<><label><span>Categoria</span><select name="category">{["documento_societario","estatuto","ata","procuracao","politica_interna","termos_condicoes"].map(v=><option value={v} key={v}>{v.replaceAll("_"," ")}</option>)}</select></label><label><span>Confidencialidade</span><select name="confidentiality"><option value="internal">Interno</option><option value="confidential">Confidencial</option><option value="restricted">Restrito</option></select></label><label><span>Referência segura</span><input name="reference" required/></label><label><span>Tipo MIME</span><input name="mimeType" placeholder="application/pdf"/></label></>}{legalKind==="version"&&<><label><span>Documento</span><select name="documentId" required>{(legalData.documents||[]).map(d=><option value={d.id} key={d.id}>{String(d.title)}</option>)}</select></label><label><span>Número da versão</span><input name="version" type="number" min="2" required/></label><label><span>Referência segura</span><input name="reference" required/></label><label><span>Tipo MIME</span><input name="mimeType"/></label><label><span>Resumo da alteração</span><input name="summary" required/></label></>}{legalKind==="permit"&&<><label><span>Tipo de alvará</span><input name="caseType" required/></label><label><span>Autoridade</span><input name="authority"/></label><label><span>Número</span><input name="number"/></label><label><span>Validade</span><input name="end" type="date"/></label></>}{legalKind==="consultation"&&<><label><span>Solicitante</span><input name="counterparty"/></label><label><span>Advogado</span><input name="authority"/></label><label><span>Resumo</span><input name="summary"/></label><label><span>Prazo</span><input name="deadline" type="datetime-local"/></label></>}<button type="button" onClick={()=>setShowLegalArchiveForm(false)}>Cancelar</button><button className="primaryAction">Guardar</button></form>}<div className="legalDocumentList">{(legalData.documents||[]).map(d=><button key={d.id} onClick={()=>void inspectLegalDocument(d.id)}><div><strong>{String(d.title)}</strong><span>{String(d.category).replaceAll("_"," ")} · {String(d.confidentiality)}</span></div><b>Consultar · v{String(d.version)}</b></button>)}{!legalData.documents?.length&&<div className="peopleEmpty">Sem documentos registados.</div>}</div>{legalDocumentDetail&&<div className="legalDocumentDetail"><div><span>CONSULTA REGISTADA</span><h3>{String(legalDocumentDetail.document.title)}</h3><p>{String(legalDocumentDetail.document.category)} · {String(legalDocumentDetail.document.confidentiality)}</p></div><div>{legalDocumentDetail.versions.map(v=><span key={String(v.id)}>Versão {String(v.version)} · {String(v.change_summary||"Sem resumo")}</span>)}</div><button onClick={()=>setLegalDocumentDetail(null)}>Fechar</button></div>}</section>}
          {active==="Conformidade e Risco"&&<section className="complianceWorkspace"><div className="complianceHero"><div><span>CONTROLO E PREVENÇÃO</span><h2>Matriz de riscos e conformidade</h2><p>Riscos, controlos, incidentes e revisões com responsável e prazo.</p></div><button onClick={()=>setShowComplianceForm(!showComplianceForm)}>Novo registo</button></div><div className="financeKpis">{[["Riscos",complianceData.compliance_risks?.length||0],["Riscos críticos",(complianceData.compliance_risks||[]).filter(r=>Number(r.risk_score)>=15&&r.status!=="closed").length],["Controlos",complianceData.compliance_controls?.length||0],["Incidentes abertos",(complianceData.compliance_incidents||[]).filter(i=>!["resolved","closed"].includes(String(i.status))).length],["Revisões",complianceData.compliance_reviews?.length||0],["Obrigações",complianceData.legal_obligations?.length||0]].map(([l,v])=><article key={String(l)}><span>{l}</span><strong>{v}</strong><small>monitorização ativa</small></article>)}</div>{showComplianceForm&&<form className="financeEntryForm" onSubmit={createComplianceRecord}><label><span>Tipo</span><select value={complianceKind} onChange={e=>setComplianceKind(e.target.value)}><option value="risk">Risco</option><option value="control">Controlo</option><option value="incident">Incidente</option><option value="review">Revisão</option></select></label><label><span>Título</span><input name="title" required/></label>{complianceKind!=="control"&&<label><span>Categoria / tipo</span><input name="category" required/></label>}{complianceKind==="control"&&<><label><span>Tipo de controlo</span><select name="controlType"><option value="preventive">Preventivo</option><option value="detective">Detetivo</option><option value="corrective">Corretivo</option></select></label><label><span>Frequência</span><input name="frequency"/></label></>}{complianceKind==="risk"&&<><label><span>Probabilidade (1–5)</span><input name="likelihood" type="number" min="1" max="5" required/></label><label><span>Impacto (1–5)</span><input name="impact" type="number" min="1" max="5" required/></label></>}{complianceKind==="incident"&&<><label><span>Severidade</span><select name="severity"><option value="low">Baixa</option><option value="medium">Média</option><option value="high">Alta</option><option value="critical">Crítica</option></select></label><label><span>Ocorrência</span><input name="occurredAt" type="datetime-local" required/></label></>}{complianceKind!=="control"&&<label><span>Descrição / âmbito</span><input name="description"/></label>}{["risk","incident"].includes(complianceKind)&&<label><span>Mitigação / ação corretiva</span><input name="plan"/></label>}<label><span>Prazo / próximo teste</span><input name="due" type="date"/></label><button className="primaryAction">Guardar</button></form>}<div className="riskMatrix"><article><h3>Matriz de risco</h3><div>{(complianceData.compliance_risks||[]).sort((a,b)=>Number(b.risk_score)-Number(a.risk_score)).slice(0,10).map(r=><div className="riskRow" key={r.id}><i className={Number(r.risk_score)>=15?"critical":Number(r.risk_score)>=8?"high":"low"}>{String(r.risk_score)}</i><div><strong>{String(r.title)}</strong><span>{String(r.category)} · {String(r.status)}</span></div><b>{String(r.target_date||"Sem prazo")}</b></div>)}{!complianceData.compliance_risks?.length&&<div className="peopleEmpty">Sem riscos registados.</div>}</div></article><article><h3>Incidentes e revisões</h3>{[...(complianceData.compliance_incidents||[]),...(complianceData.compliance_reviews||[])].slice(0,10).map(i=><div className="riskRow" key={i.id}><i className={String(i.severity)==="critical"?"critical":"low"}>!</i><div><strong>{String(i.title)}</strong><span>{String(i.severity||i.review_type||"revisão")} · {String(i.status)}</span></div><b>{String(i.due_on||i.occurred_at||"")}</b></div>)}</article></div>{complianceNotice&&<div className="operationalNotice">{complianceNotice}</div>}<div className="safeNotice"><b>Governança de risco</b><span>A pontuação é calculada automaticamente por probabilidade × impacto. Encerrar riscos ou incidentes exige evidência e revisão do responsável.</span></div></section>}
          {active==="Conformidade e Risco"&&<section className="complianceExtended"><div className="legalArchiveHead"><div><span>CONTINUIDADE E EVIDÊNCIA</span><h2>Verificações, alertas e medidas adotadas</h2><p>Cada risco novo exige prazo, responsável e referência de evidência.</p></div><div>{[["risk","Novo risco completo"],["evidence","Adicionar evidência"],["check","Verificação interna"],["continuity","Plano de continuidade"]].map(([kind,label])=><button key={kind} onClick={()=>{setComplianceKind(kind);setShowComplianceExtraForm(true)}}>{label}</button>)}</div></div><div className="financeKpis">{[["Evidências",complianceData.compliance_risk_evidence?.length||0],["Verificações",complianceData.compliance_checks?.length||0],["Alertas abertos",(complianceData.compliance_alerts||[]).filter(a=>a.status==="open").length],["Planos de continuidade",complianceData.business_continuity_plans?.length||0],["Medidas históricas",complianceData.compliance_measure_history?.length||0]].map(([l,v])=><article key={String(l)}><span>{l}</span><strong>{v}</strong><small>rastreabilidade</small></article>)}</div>{showComplianceExtraForm&&<form className="financeEntryForm" onSubmit={createComplianceRecord}><label><span>Título</span><input name="title" required/></label>{complianceKind==="evidence"&&<label><span>Risco</span><select name="riskId" required>{(complianceData.compliance_risks||[]).map(r=><option value={r.id} key={r.id}>{String(r.title)}</option>)}</select></label>}<label><span>{complianceKind==="continuity"?"Processo crítico":"Categoria / tipo"}</span><input name="category" required/></label>{complianceKind==="risk"&&<><label><span>Descrição</span><input name="description"/></label><label><span>Probabilidade (1–5)</span><input name="likelihood" type="number" min="1" max="5" required/></label><label><span>Impacto (1–5)</span><input name="impact" type="number" min="1" max="5" required/></label><label><span>Plano de mitigação</span><input name="plan" required/></label></>}{["check","continuity"].includes(complianceKind)&&<label><span>{complianceKind==="continuity"?"Objetivo de recuperação":"Âmbito"}</span><input name="description" required/></label>}{complianceKind==="continuity"&&<label><span>Tempo de recuperação (horas)</span><input name="recoveryHours" type="number" min="1" required/></label>}<label><span>Referência de evidência</span><input name="evidence" required/></label>{complianceKind!=="evidence"&&<label><span>Prazo / próximo teste</span><input name="due" type="date" required/></label>}<button type="button" onClick={()=>setShowComplianceExtraForm(false)}>Cancelar</button><button className="primaryAction">Guardar</button></form>}<div className="riskMatrix"><article><h3>Alertas de incumprimento</h3>{(complianceData.compliance_alerts||[]).slice(0,8).map(a=><div className="riskRow" key={a.id}><i className={String(a.severity)==="critical"?"critical":"high"}>!</i><div><strong>{String(a.title)}</strong><span>{String(a.alert_type)} · {String(a.status)}</span></div><b>{String(a.due_at||"")}</b></div>)}{!complianceData.compliance_alerts?.length&&<div className="peopleEmpty">Sem alertas ativos.</div>}</article><article><h3>Histórico de medidas</h3>{(complianceData.compliance_measure_history||[]).slice(0,8).map(m=><div className="riskRow" key={m.id}><i className="low">✓</i><div><strong>{String(m.description)}</strong><span>{String(m.measure_type)}</span></div><b>{String(m.created_at||"")}</b></div>)}{!complianceData.compliance_measure_history?.length&&<div className="peopleEmpty">Sem medidas históricas.</div>}</article></div></section>}
          {active==="Tecnologia / IT"&&<section className="technologyWorkspace"><div className="technologyHero"><div><span>CENTRO DE TECNOLOGIA</span><h2>Sistemas, integrações e continuidade técnica</h2><p>Estado operacional do ecossistema DeliGo, Comunhão, TaoMoz, SARCA e HQ.</p></div><button onClick={()=>setShowTechnologyForm(!showTechnologyForm)}>Novo registo</button></div><div className="financeKpis">{[["Sistemas",technologyData.technology_systems?.length||0],["Operacionais",(technologyData.technology_systems||[]).filter(s=>s.status==="operational").length],["Integrações",technologyData.technology_integrations?.length||0],["Incidentes abertos",(technologyData.technology_incidents||[]).filter(i=>!["resolved","closed"].includes(String(i.status))).length],["Backups concluídos",(technologyData.technology_backups||[]).filter(b=>b.status==="succeeded").length],["Alterações planeadas",(technologyData.technology_changes||[]).filter(c=>c.status==="planned").length]].map(([l,v])=><article key={String(l)}><span>{l}</span><strong>{v}</strong><small>monitorização técnica</small></article>)}</div>{showTechnologyForm&&<form className="financeEntryForm" onSubmit={createTechnologyRecord}><label><span>Tipo de registo</span><select value={technologyKind} onChange={e=>setTechnologyKind(e.target.value)}><option value="system">Sistema / base de dados</option><option value="integration">API / integração</option><option value="incident">Incidente</option><option value="backup">Backup</option><option value="change">Alteração técnica</option></select></label>{technologyKind!=="backup"&&<label><span>Nome / título</span><input name="title" required/></label>}{["system","integration","backup","change"].includes(technologyKind)&&<label><span>Tipo</span><input name="type" required/></label>}{technologyKind==="system"&&<><label><span>Ambiente</span><select name="environment"><option value="production">Produção</option><option value="staging">Staging</option><option value="development">Desenvolvimento</option><option value="external">Externo</option></select></label><label><span>URL base</span><input name="endpoint" type="url"/></label></>}{technologyKind==="integration"&&<><label><span>Fornecedor</span><input name="provider" required/></label><label><span>Endpoint de saúde</span><input name="endpoint" type="url"/></label><label><span>Referência do segredo</span><input name="secretReference" placeholder="vault://…"/></label></>}{technologyKind==="incident"&&<><label><span>Severidade</span><select name="severity"><option value="sev4">SEV4</option><option value="sev3">SEV3</option><option value="sev2">SEV2</option><option value="sev1">SEV1</option></select></label><label><span>Início</span><input name="startedAt" type="datetime-local" required/></label><label><span>Descrição</span><input name="description"/></label></>}{technologyKind==="backup"&&<><label><span>Referência segura</span><input name="secretReference" required/></label><label><span>Início</span><input name="startedAt" type="datetime-local" required/></label><label><span>Retenção</span><input name="due" type="date"/></label></>}{technologyKind==="change"&&<><label><span>Risco</span><select name="risk"><option value="low">Baixo</option><option value="medium">Médio</option><option value="high">Alto</option><option value="critical">Crítico</option></select></label><label><span>Agendamento</span><input name="startedAt" type="datetime-local"/></label><label><span>Plano de rollback</span><input name="description" required/></label></>}<button className="primaryAction">Guardar</button></form>}<div className="technologyGrid"><article><h3>Sistemas e integrações</h3>{[...(technologyData.technology_systems||[]),...(technologyData.technology_integrations||[])].slice(0,10).map(s=><div className="technologyRow" key={s.id}><i className={s.status==="operational"||s.status==="active"?"ok":"warn"}/><div><strong>{String(s.name)}</strong><span>{String(s.system_type||s.provider||s.integration_type)} · {String(s.environment||"")}</span></div><b>{String(s.status)}</b></div>)}{!(technologyData.technology_systems?.length||technologyData.technology_integrations?.length)&&<div className="peopleEmpty">Sem sistemas registados.</div>}</article><article><h3>Incidentes e mudanças</h3>{[...(technologyData.technology_incidents||[]),...(technologyData.technology_changes||[])].slice(0,10).map(i=><div className="technologyRow" key={i.id}><i className={String(i.severity)==="sev1"||String(i.risk_level)==="critical"?"down":"warn"}/><div><strong>{String(i.title)}</strong><span>{String(i.severity||i.change_type)} · {String(i.started_at||i.scheduled_at||"")}</span></div><b>{String(i.status)}</b></div>)}</article></div>{technologyNotice&&<div className="operationalNotice">{technologyNotice}</div>}<div className="safeNotice"><b>Segurança de credenciais</b><span>O HQ aceita apenas referências de cofre. Chaves, tokens e private keys nunca são devolvidos pela API nem apresentados nesta tela.</span></div></section>}
          {active==="Compras"&&<section className="procurementWorkspace"><div className="procurementHero"><div><span>CICLO DE AQUISIÇÃO</span><h2>Pedido → aprovação → fornecedor → encomenda → receção → fatura → pagamento</h2><p>Cada etapa é validada no servidor e preservada no histórico.</p></div><button onClick={()=>setShowProcurementForm(!showProcurementForm)}>Nova etapa</button></div><div className="procurementFlow">{[["1","Pedido"],["2","Aprovação"],["3","Fornecedor"],["4","Encomenda"],["5","Receção"],["6","Fatura"],["7","Pagamento"]].map(([n,l])=><div key={n}><b>{n}</b><span>{l}</span></div>)}</div><div className="financeKpis">{[["Pedidos",procurementData.purchase_requests?.length||0],["Aguardam aprovação",(procurementData.purchase_requests||[]).filter(r=>r.status==="pending_approval").length],["Fornecedores",procurementData.suppliers?.length||0],["Cotações",procurementData.supplier_quotes?.length||0],["Ordens",procurementData.purchase_orders?.length||0],["Pagamentos pendentes",(procurementData.procurement_invoices||[]).filter(i=>i.status==="pending_payment").length]].map(([l,v])=><article key={String(l)}><span>{l}</span><strong>{v}</strong><small>processo controlado</small></article>)}</div>{showProcurementForm&&<form className="financeEntryForm" onSubmit={createProcurementRecord}><label><span>Etapa</span><select value={procurementKind} onChange={e=>setProcurementKind(e.target.value)}><option value="request">Pedido de compra</option><option value="supplier">Fornecedor</option><option value="quote">Cotação</option><option value="order">Ordem de compra</option><option value="receipt">Receção</option><option value="invoice">Fatura</option></select></label>{procurementKind==="request"&&<><label><span>Departamento</span><select name="departmentId" required>{(procurementData.departments||[]).map(d=><option value={d.id} key={d.id}>{String(d.name)}</option>)}</select></label><label><span>Orçamento</span><select name="budgetId"><option value="">Sem orçamento associado</option>{(procurementData.budgets||[]).map(b=><option value={b.id} key={b.id}>{String(b.name||b.financial_year)} · {money(Number(b.amount||0)-Number(b.spent_amount||0))} disponível</option>)}</select></label><label><span>Justificação</span><input name="justification" required/></label><label><span>Produto ou serviço</span><input name="item" required/></label><label><span>Quantidade</span><input name="quantity" type="number" min=".01" step=".01" required/></label><label><span>Unidade</span><input name="unit" defaultValue="un" required/></label><label><span>Preço estimado</span><input name="price" type="number" min=".01" step=".01" required/></label></>}{procurementKind==="supplier"&&<><label><span>Fornecedor</span><input name="supplierName" required/></label><label><span>NUIT</span><input name="taxNumber"/></label><label><span>Email</span><input name="email" type="email"/></label></>}{["quote","order"].includes(procurementKind)&&<><label><span>Pedido aprovado</span><select name="purchaseRequestId" required>{(procurementData.purchase_requests||[]).filter(r=>["approved","sourcing"].includes(String(r.status))).map(r=><option value={r.id} key={r.id}>PR-{String(r.request_number)} · {String(r.justification)}</option>)}</select></label><label><span>Fornecedor</span><select name="supplierId" required>{(procurementData.suppliers||[]).filter(s=>s.status==="active").map(s=><option value={s.id} key={s.id}>{String(s.name)}</option>)}</select></label><label><span>Valor</span><input name="amount" type="number" min=".01" step=".01" required/></label><label><span>Validade / entrega</span><input name="due" type="date"/></label>{procurementKind==="quote"&&<><label><span>Referência</span><input name="reference"/></label><label><span>Documento</span><input name="documentReference"/></label></>}</>}{procurementKind==="receipt"&&<><label><span>Ordem</span><select name="orderId" required>{(procurementData.purchase_orders||[]).filter(o=>o.status==="issued").map(o=><option value={o.id} key={o.id}>PO-{String(o.order_number)}</option>)}</select></label><label><span>Recebido em</span><input name="receivedAt" type="datetime-local" required/></label><label><span>Notas</span><input name="justification"/></label><label><span>Comprovativo</span><input name="documentReference"/></label></>}{procurementKind==="invoice"&&<><label><span>Ordem</span><select name="orderId" required>{(procurementData.purchase_orders||[]).filter(o=>o.status==="received").map(o=><option value={o.id} key={o.id}>PO-{String(o.order_number)}</option>)}</select></label><label><span>Receção</span><select name="receiptId" required>{(procurementData.goods_receipts||[]).filter(r=>r.status==="accepted").map(r=><option value={r.id} key={r.id}>{new Date(String(r.received_at)).toLocaleDateString("pt-MZ")}</option>)}</select></label><label><span>Número da fatura</span><input name="reference" required/></label><label><span>Fornecedor / beneficiário</span><input name="supplierName" required/></label><label><span>Valor</span><input name="amount" type="number" min=".01" step=".01" required/></label><label><span>Emissão</span><input name="issuedOn" type="date" required/></label><label><span>Vencimento</span><input name="due" type="date" required/></label><label><span>Documento</span><input name="documentReference"/></label></>}<button className="primaryAction">Guardar etapa</button></form>}<div className="procurementList">{(procurementData.purchase_requests||[]).map(r=><article key={r.id}><div><strong>PR-{String(r.request_number)} · {String(r.justification)}</strong><span>{money(Number(r.estimated_amount))} · {String(r.status)}</span></div><div>{r.status==="pending_approval"&&["SUPER_ADMIN","FINANCE"].includes(sessionRole)&&<button onClick={()=>void procurementAction("approve",r.id)}>Aprovar</button>}{r.status==="approved"&&(procurementData.supplier_quotes||[]).filter(q=>q.purchase_request_id===r.id).map(q=><button key={q.id} onClick={()=>void procurementAction("select_quote",r.id,q.id)}>Selecionar cotação {money(Number(q.total_amount))}</button>)}</div></article>)}{!procurementData.purchase_requests?.length&&<div className="peopleEmpty">Sem pedidos de compra.</div>}</div>{procurementNotice&&<div className="operationalNotice">{procurementNotice}</div>}<div className="safeNotice"><b>Bloqueio de sequência ativo</b><span>O servidor rejeita ordens sem aprovação e cotação selecionada, receções sem ordem emitida e faturas sem receção aceite. O pagamento segue a aprovação financeira.</span></div></section>}
          {active === "Direcção Executiva" && dashboard?.governance && (
            <section className="governanceWorkspace">
              <div className="companyRecord"><div><span>ENTIDADE JURÍDICA</span><h2>{dashboard.governance.legalName}</h2><p>Sociedade por quotas · governação corporativa separada das permissões técnicas.</p></div><b>50 / 50</b></div>
              <div className="shareholderGrid">{dashboard.governance.shareholders.map((shareholder) => <article key={shareholder.employeeId}><div className="shareholderTop"><i>{shareholder.displayName.split(" ").slice(0,2).map((part) => part[0]).join("")}</i><span>{shareholder.quotaPercent}%</span></div><h3>{shareholder.displayName}</h3><p>{shareholder.corporateTitle}</p><div className="shareholderFlags"><span>{shareholder.isManagingPartner ? "Gerente executivo" : "Gestão financeira"}</span><span>{shareholder.isSuperAdministrator ? "Super Administrador" : "Sem acesso global"}</span></div></article>)}</div>
              <div className="reservedPanel"><div className="panelTitle"><div><h2>Matérias reservadas</h2><p>Exigem aprovação distinta dos dois sócios</p></div><span className="protected">{dashboard.governance.reservedMatterApprovalsRequired} aprovações</span></div><div className="reservedGrid">{dashboard.governance.reservedMatters.map((matter) => <div key={matter}><CheckCircle2 aria-hidden="true" /><span>{matter.replaceAll("_", " ")}</span><b>Ambos</b></div>)}</div></div>
            </section>
          )}
          {["Pessoas","Recursos Humanos"].includes(active) && (
            <section className="employeeAdmin">
              <div className="employeeAdminHead"><div><span>GESTÃO DE TRABALHADORES</span><h2>{managedEmployees.length} cadastros</h2><p>RH prepara o cadastro; o Super Admin aprova acessos e gere contas protegidas.</p></div><button className="primaryAction" onClick={()=>setShowEmployeeForm(!showEmployeeForm)}>Novo trabalhador</button></div>
              <div className="employeeSummary">{[
                ["Activos",managedEmployees.filter(e=>e.status==="active").length], ["Convidados",managedEmployees.filter(e=>e.status==="invited").length], ["Suspensos",managedEmployees.filter(e=>e.status==="suspended").length], ["Arquivados",managedEmployees.filter(e=>e.status==="offboarded").length],
              ].map(([label,value])=><div key={label}><span>{label}</span><strong>{value}</strong></div>)}</div>
              {showEmployeeForm && <form className="employeeForm" onSubmit={createEmployee}>
                <label><span>Nome completo</span><input name="name" required /></label><label><span>Telefone</span><input name="phone" placeholder="84 999 0020" required /></label><label><span>Cargo</span><input name="jobTitle" required /></label>
                <label><span>Departamento</span><select name="department" required>{[["ACCOUNTING","Contabilidade"],["HR","Recursos Humanos"],["LEGAL","Jurídico"],["OPERATIONS","Operações"],["MARKETING","Marketing"],["FIELD","Field"],["SUPPORT","Suporte"],["ACQUISITION","Aquisição"],["AMBASSADORS","Embaixadores"],["PROCUREMENT","Compras"],["ASSETS","Património"]].map(([v,l])=><option value={v} key={v}>{l}</option>)}</select></label>
                <label><span>Role único</span><select name="role" required>{["ACCOUNTING","HUMAN_RESOURCES","LEGAL","OPERATIONS","CUSTOMER_SUPPORT","MARKETING","FIELD","PARTNER_ACQUISITION","AMBASSADOR","PROCUREMENT","ASSETS_LOGISTICS"].map(role=><option key={role}>{role}</option>)}</select></label>
                {sessionRole==="SUPER_ADMIN"&&<label className="activateCheck"><input name="activate" type="checkbox"/><span>Activar imediatamente</span></label>}<button className="primaryAction" type="submit">Guardar cadastro</button>
              </form>}
              {editingEmployee && <form className="employeeForm" onSubmit={updateEmployee}>
                <label><span>Nome completo</span><input name="name" defaultValue={editingEmployee.name} required /></label><label><span>Telefone</span><input name="phone" defaultValue={editingEmployee.phone} required /></label><label><span>Cargo</span><input name="jobTitle" defaultValue={editingEmployee.job_title} required /></label>
                <label><span>Departamento</span><select name="department" defaultValue={editingEmployee.department_code} required>{[["ACCOUNTING","Contabilidade"],["HR","Recursos Humanos"],["LEGAL","Jurídico"],["OPERATIONS","Operações"],["MARKETING","Marketing"],["FIELD","Field"],["SUPPORT","Suporte"],["ACQUISITION","Aquisição"],["AMBASSADORS","Embaixadores"],["PROCUREMENT","Compras"],["ASSETS","Património"]].map(([v,l])=><option value={v} key={v}>{l}</option>)}</select></label>
                <label><span>Role único</span><select name="role" defaultValue={editingEmployee.role||editingEmployee.requested_role||"OPERATIONS"} required>{["ACCOUNTING","HUMAN_RESOURCES","LEGAL","OPERATIONS","CUSTOMER_SUPPORT","MARKETING","FIELD","PARTNER_ACQUISITION","AMBASSADOR","PROCUREMENT","ASSETS_LOGISTICS"].map(role=><option key={role}>{role}</option>)}</select></label>
                <button type="button" onClick={()=>setEditingEmployee(null)}>Cancelar</button><button className="primaryAction" type="submit">Guardar alterações</button>
              </form>}
              {employeeNotice&&<div className="safeNotice"><b>Estado</b><span>{employeeNotice}</span></div>}
              <div className="employeeTable"><div className="employeeAdminRow employeeAdminHeader"><span>Trabalhador</span><span>Role</span><span>Estado</span><span>Acções</span></div>{managedEmployees.map(employee=><div className="employeeAdminRow" key={employee.id}><div><strong>{employee.name}</strong><small>{employee.employee_code} · {employee.phone} · {employee.department}</small></div><span>{employee.role||employee.requested_role||"Pendente"}</span><b className={`employeeStatus ${employee.status}`}>{employee.status}</b><div className="employeeActions"><button onClick={()=>{setEditingEmployee(employee);setShowEmployeeForm(false)}}>Editar</button>{sessionRole==="SUPER_ADMIN"&&employee.employee_code!=="DG-0001"&&<>{employee.status==="invited"&&<button onClick={()=>employeeAction(employee.id,"activate")}>Activar</button>}{employee.status==="active"&&<button onClick={()=>employeeAction(employee.id,"suspend")}>Suspender</button>}{employee.status==="suspended"&&<button onClick={()=>employeeAction(employee.id,"reactivate")}>Reactivar</button>}{employee.status!=="offboarded"&&<button onClick={()=>{if(window.confirm(`Arquivar ${employee.name}? O acesso será revogado.`))void employeeAction(employee.id,"archive")}}>Arquivar</button>}</>}</div></div>)}</div>
            </section>
          )}
          {active === "Pessoas" && <section className="peopleInspector"><div className="peopleSearchBar"><input value={employeeSearch} onChange={event=>setEmployeeSearch(event.target.value)} placeholder="Pesquisar por nome, identificação, cargo ou departamento"/><b>{shownEmployees.length} resultados</b></div><div className="peopleInspectorGrid">{shownEmployees.map(employee=><button key={employee.id} onClick={()=>setSelectedEmployee(employee)}><strong>{employee.name}</strong><span>{employee.employee_code} · {employee.job_title}</span><small>{employee.department} · {employee.status}</small></button>)}</div>{selectedEmployee&&<div className="employeeDetail"><div className="employeeDetailHead"><div><span>PERFIL PROFISSIONAL</span><h3>{selectedEmployee.name}</h3><p>{selectedEmployee.employee_code} · {selectedEmployee.job_title} · {selectedEmployee.department}</p></div><button onClick={()=>setSelectedEmployee(null)}>Fechar</button></div><div className="employeeDetailGrid"><article><span>Estado</span><strong>{selectedEmployee.status}</strong></article><article><span>Função</span><strong>{selectedEmployee.role||selectedEmployee.requested_role||"Pendente"}</strong></article><article><span>Último acesso</span><strong>{selectedEmployee.last_login_at?new Date(selectedEmployee.last_login_at).toLocaleString("pt-MZ"):"Sem acesso"}</strong></article><article><span>Permissões específicas</span><strong>{employeePermissions.filter(item=>item.employee_id===selectedEmployee.id).length}</strong></article></div><div className="employeeTimeline"><h4>Histórico e acessos</h4>{employeeHistory.filter(item=>item.employee_id===selectedEmployee.id).slice(0,5).map(item=><p key={item.id}><b>{item.action.replaceAll("_"," ")}</b><span>{new Date(item.created_at).toLocaleString("pt-MZ")}</span></p>)}{employeeAccess.filter(item=>item.employee_id===selectedEmployee.id).slice(0,5).map(item=><p key={item.id}><b>{item.event_type.replaceAll("_"," ")}</b><span>{new Date(item.occurred_at).toLocaleString("pt-MZ")}</span></p>)}{!employeeHistory.some(item=>item.employee_id===selectedEmployee.id)&&!employeeAccess.some(item=>item.employee_id===selectedEmployee.id)&&<div className="peopleEmpty">Sem alterações ou acessos registados.</div>}</div></div>}</section>}
          {active === "Pessoas"&&selectedEmployee&&sessionRole==="SUPER_ADMIN"&&<section className="peopleAccessControls"><h3>Supervisor e permissões individuais</h3><label><span>Supervisor directo</span><select defaultValue="" onChange={event=>void employeeGovernanceAction({employeeId:selectedEmployee.id,action:"set_supervisor",supervisorId:event.target.value||null})}><option value="">Sem supervisor</option>{managedEmployees.filter(item=>item.id!==selectedEmployee.id&&item.status==="active").map(item=><option value={item.id} key={item.id}>{item.name} · {item.job_title}</option>)}</select></label><div>{["people.view","people.manage","operations.view","reports.view"].map(code=>{const current=employeePermissions.find(item=>item.employee_id===selectedEmployee.id&&item.permission_code===code)?.allowed;return <button className={current?"active":""} key={code} onClick={()=>void employeeGovernanceAction({employeeId:selectedEmployee.id,action:"set_permission",permissionCode:code,allowed:!current})}>{current?"✓ ":""}{code.replaceAll("."," · ")}</button>})}</div><small>Cada alteração é guardada no histórico do colaborador.</small></section>}
          {active === "Recursos Humanos"&&<section className="hrLifecycle"><div className="hrLifecycleHead"><div><span>CICLO DE VIDA DO COLABORADOR</span><h2>Operações de Recursos Humanos</h2><p>Dados pessoais e salariais visíveis apenas para RH e Super Admin.</p></div><b>Área restrita</b></div><div className="hrLifecycleGrid">{[["Admissões e contratos","hr_contracts"],["Documentos pessoais","hr_documents"],["Presenças, faltas e atrasos","hr_attendance"],["Férias e licenças","hr_leave_requests"],["Processamento salarial","hr_payroll_records"],["Benefícios, avaliações e formação","hr_employee_events"]].map(([label,key])=><article key={key}><span>{label}</span><strong>{(hrData[key]||[]).length}</strong><small>registos protegidos</small></article>)}</div><div className="hrProcessGrid">{["Admissão e onboarding","Horários e turnos","Férias e licenças","Payroll e benefícios","Avaliação de desempenho","Formação","Processos disciplinares","Promoções e transferências","Saída e desligamento"].map(item=><button key={item} onClick={()=>setSubArea(item)} className={subArea===item?"active":""}>{item}<ChevronRight aria-hidden="true"/></button>)}</div><div className="safeNotice"><b>Proteção activa</b><span>Documentos pessoais, contratos e valores salariais nunca são enviados a perfis operacionais.</span></div></section>}
          {active==="Recursos Humanos"&&<section className="hrEventActions"><button className="hrCreateButton" onClick={()=>setShowHrEventForm(!showHrEventForm)}>Novo registo de ciclo laboral</button>{showHrEventForm&&<form className="hrEventForm" onSubmit={createHrEvent}><label><span>Colaborador</span><select name="employeeId" required><option value="">Seleccionar</option>{managedEmployees.filter(item=>item.status!=="offboarded").map(item=><option value={item.id} key={item.id}>{item.name} · {item.employee_code}</option>)}</select></label><label><span>Tipo</span><select name="eventType" required>{[["admission","Admissão"],["benefit","Benefício"],["performance_review","Avaliação"],["training","Formação"],["disciplinary","Processo disciplinar"],["promotion","Promoção"],["transfer","Transferência"],["separation","Desligamento"]].map(([value,label])=><option value={value} key={value}>{label}</option>)}</select></label><label><span>Título</span><input name="title" required minLength={3}/></label><label><span>Data</span><input name="occurredOn" type="date" required/></label><button type="submit">Guardar registo</button></form>}{hrNotice&&<div className="operationalNotice">{hrNotice}</div>}</section>}
          {active === "Registo de Auditoria" && (
            <section className="auditWorkspace"><div className="employeeAdminHead"><div><span>REGISTO IMUTÁVEL</span><h2>Auditoria e histórico</h2><p>Criação, aprovação, suspensão, arquivo e operações sensíveis.</p></div><div><button onClick={exportAudit}>Exportar CSV</button><b>{auditRecords.length} eventos</b></div></div><div className="auditTable"><div className="auditRow auditHeader"><span>Data</span><span>Actor</span><span>Acção</span><span>Resultado</span></div>{auditRecords.map(event=><div className="auditRow" key={event.id}><span>{new Date(event.occurred_at).toLocaleString("pt-MZ")}</span><strong>{event.actor}</strong><span>{event.action.replaceAll("_"," ")}</span><b>{event.result}</b></div>)}{!auditRecords.length&&<div className="peopleEmpty">Sem eventos disponíveis para este perfil.</div>}</div></section>
          )}
          {active === "Marketing" && <section className="marketingWorkspace">
            <div className="marketingHero"><div><span>CENTRO DE CAMPANHAS</span><h2>Marketing, comunicação e crescimento</h2><p>Planeamento, aprovação, publicação e resultados reais por plataforma.</p></div><button onClick={()=>setShowMarketingForm(!showMarketingForm)}>Novo registo</button></div>
            <div className="financeKpis">{[
              ["Campanhas",marketingData.marketing_campaigns?.length||0],
              ["Em aprovação",(marketingData.marketing_campaigns||[]).filter(c=>c.status==="pending_approval").length],
              ["Publicadas",(marketingData.marketing_campaigns||[]).filter(c=>c.status==="published").length],
              ["Conteúdos",marketingData.marketing_content_calendar?.length||0],
              ["Leads",marketingReports.reduce((n,r)=>n+Number(r.leads||0),0)],
              ["Conversões",marketingReports.reduce((n,r)=>n+Number(r.conversions||0),0)]
            ].map(([label,value])=><article key={String(label)}><span>{label}</span><strong>{value}</strong><small>dados do backend</small></article>)}</div>
            {showMarketingForm&&<form className="financeEntryForm marketingForm" onSubmit={createMarketingRecord}>
              <label><span>Tipo de registo</span><select value={marketingKind} onChange={e=>setMarketingKind(e.target.value)}><option value="campaign">Campanha</option><option value="content">Conteúdo / calendário</option><option value="promotion">Promoção</option><option value="channel">Canal</option><option value="creative">Material criativo</option><option value="lead">Lead</option><option value="metric">Resultado / desempenho</option></select></label>
              {marketingKind!=="campaign"&&<label><span>Campanha</span><select name="campaignId" required><option value="">Selecionar</option>{(marketingData.marketing_campaigns||[]).map(c=><option value={c.id} key={c.id}>{String(c.title)} · {String(c.status).replaceAll("_"," ")}</option>)}</select></label>}
              {marketingKind==="campaign"&&<><label><span>Nome da campanha</span><input name="title" required/></label><label><span>Objetivo</span><input name="objective" required/></label><label><span>Público-alvo</span><input name="audience" required/></label><label><span>Orçamento (MZN)</span><input name="budget" type="number" min="0" step=".01" required/></label><label><span>Início</span><input name="start" type="datetime-local"/></label><label><span>Fim</span><input name="end" type="datetime-local"/></label><label className="marketingPlatforms"><span>Plataformas</span><select name="platforms" multiple required size={4}><option value="deligo">DeliGo</option><option value="comunhao">Comunhão</option><option value="taomoz">TaoMoz</option><option value="sarca">SARCA</option></select><small>Use Ctrl para selecionar várias.</small></label></>}
              {["content","promotion","lead","metric"].includes(marketingKind)&&<label><span>Plataforma</span><select name="platform" required><option value="deligo">DeliGo</option><option value="comunhao">Comunhão</option><option value="taomoz">TaoMoz</option><option value="sarca">SARCA</option></select></label>}
              {marketingKind==="channel"&&<><label><span>Canal</span><select name="channel"><option value="social">Redes sociais</option><option value="email">Email</option><option value="push">Push</option><option value="sms">SMS</option><option value="web">Web</option><option value="in_app">In-app</option><option value="field">Field</option><option value="partner">Parceiros</option></select></label><label><span>Conta / referência</span><input name="reference"/></label></>}
              {marketingKind==="content"&&<><label><span>Título do conteúdo</span><input name="title" required/></label><label><span>Tipo</span><input name="contentType" placeholder="post, vídeo, email…" required/></label><label><span>Publicação prevista</span><input name="scheduledAt" type="datetime-local" required/></label></>}
              {marketingKind==="promotion"&&<><label><span>Código</span><input name="code" required/></label><label><span>Tipo</span><select name="discountType"><option value="percentage">Percentagem</option><option value="fixed">Valor fixo</option><option value="free_delivery">Entrega grátis</option></select></label><label><span>Desconto</span><input name="discount" type="number" min="0" step=".01" required/></label><label><span>Início</span><input name="start" type="datetime-local"/></label><label><span>Fim</span><input name="end" type="datetime-local"/></label></>}
              {marketingKind==="creative"&&<><label><span>Nome do material</span><input name="title" required/></label><label><span>Tipo</span><input name="contentType" placeholder="banner, vídeo, copy…" required/></label><label><span>Referência segura do ficheiro</span><input name="reference" required/></label></>}
              {marketingKind==="lead"&&<><label><span>Referência do lead</span><input name="reference"/></label><label><span>Canal de origem</span><input name="channel" required/></label><label><span>Estado</span><select name="leadStatus"><option value="new">Novo</option><option value="qualified">Qualificado</option><option value="converted">Convertido</option><option value="lost">Perdido</option></select></label></>}
              {marketingKind==="metric"&&<><label><span>Data</span><input name="metricDate" type="date" required/></label><label><span>Impressões</span><input name="impressions" type="number" min="0" required/></label><label><span>Cliques</span><input name="clicks" type="number" min="0" required/></label><label><span>Leads</span><input name="leads" type="number" min="0" required/></label><label><span>Conversões</span><input name="conversions" type="number" min="0" required/></label><label><span>Investimento (MZN)</span><input name="spend" type="number" min="0" step=".01" required/></label></>}
              <button className="primaryAction">Guardar</button>
            </form>}
            {marketingNotice&&<div className="operationalNotice">{marketingNotice}</div>}
            <div className="marketingGrid">
              <div className="marketingCampaigns"><div className="panelTitle"><div><h2>Campanhas</h2><p>Fluxo controlado do rascunho ao arquivo</p></div></div>{(marketingData.marketing_campaigns||[]).map(c=><article key={c.id}><div><span className={`marketingStatus ${String(c.status)}`}>{String(c.status).replaceAll("_"," ")}</span><strong>{String(c.title)}</strong><small>{String(c.objective||"Sem objetivo descrito")} · {money(Number(c.budget_amount||0))}</small></div><div>{c.status==="draft"&&<button onClick={()=>void marketingAction(c.id,"submit")}>Enviar para aprovação</button>}{c.status==="pending_approval"&&sessionRole==="SUPER_ADMIN"&&<button onClick={()=>void marketingAction(c.id,"approve")}>Aprovar</button>}{["approved","paused"].includes(String(c.status))&&<button onClick={()=>void marketingAction(c.id,"publish")}>Publicar</button>}{c.status==="published"&&<button onClick={()=>void marketingAction(c.id,"pause")}>Pausar</button>}{["published","paused"].includes(String(c.status))&&<button onClick={()=>void marketingAction(c.id,"complete")}>Concluir</button>}{["draft","paused","completed","rejected"].includes(String(c.status))&&<button onClick={()=>void marketingAction(c.id,"archive")}>Arquivar</button>}</div></article>)}{!marketingData.marketing_campaigns?.length&&<div className="peopleEmpty">Sem campanhas criadas.</div>}</div>
              <div className="marketingCalendar"><div className="panelTitle"><div><h2>Calendário de conteúdos</h2><p>Publicações planeadas</p></div></div>{(marketingData.marketing_content_calendar||[]).slice(0,8).map(item=><article key={item.id}><b>{new Date(String(item.scheduled_at)).toLocaleDateString("pt-MZ",{day:"2-digit",month:"short"})}</b><div><strong>{String(item.title)}</strong><span>{String(item.content_type)} · {String(item.status)}</span></div></article>)}{!marketingData.marketing_content_calendar?.length&&<div className="peopleEmpty">Sem conteúdos agendados.</div>}</div>
            </div>
            <div className="marketingResults"><div className="panelTitle"><div><h2>Resultados por plataforma</h2><p>Valores registados, sem estimativas simuladas</p></div></div><div className="marketingResultRow marketingResultHead"><span>Plataforma</span><span>Impressões</span><span>Cliques</span><span>Leads</span><span>Conversões</span><span>Investimento</span></div>{marketingReports.map(r=><div className="marketingResultRow" key={String(r.platform_id)}><strong>{String(r.platform)}</strong><span>{Number(r.impressions).toLocaleString("pt-MZ")}</span><span>{Number(r.clicks).toLocaleString("pt-MZ")}</span><span>{Number(r.leads).toLocaleString("pt-MZ")}</span><span>{Number(r.conversions).toLocaleString("pt-MZ")}</span><span>{money(Number(r.spend))}</span></div>)}</div>
            <div className="marketingResources"><article><span>Promoções</span><strong>{marketingData.marketing_promotions?.length||0}</strong></article><article><span>Canais</span><strong>{marketingData.marketing_channels?.length||0}</strong></article><article><span>Materiais criativos</span><strong>{marketingData.marketing_creatives?.length||0}</strong></article><article><span>Eventos no histórico</span><strong>{marketingData.marketing_history?.length||0}</strong></article></div>
            <div className="safeNotice"><b>Aprovação obrigatória ativa</b><span>O backend bloqueia a publicação sem pedido aprovado. O criador não pode aprovar a própria campanha e todas as transições ficam no histórico.</span></div>
          </section>}
          {active === "Field" && <section className="fieldWorkspace">
            <div className="fieldHero"><div><span>OPERAÇÕES NO TERRENO</span><h2>Missões, visitas e verificações Field</h2><p>Atribuição, execução, evidências e relatório final num único fluxo.</p></div><button onClick={()=>setShowFieldForm(!showFieldForm)}>Nova operação</button></div>
            <div className="financeKpis">{[["Missões",fieldData.field_visits?.length||0],["Planeadas",(fieldData.field_visits||[]).filter(v=>["planned","assigned"].includes(String(v.status))).length],["Em curso",(fieldData.field_visits||[]).filter(v=>v.status==="in_progress").length],["Bloqueadas",(fieldData.field_visits||[]).filter(v=>v.status==="blocked").length],["Concluídas",(fieldData.field_visits||[]).filter(v=>v.status==="completed").length],["Evidências",fieldData.field_evidence?.length||0]].map(([label,value])=><article key={String(label)}><span>{label}</span><strong>{value}</strong><small>backend Field</small></article>)}</div>
            {showFieldForm&&<form className="financeEntryForm" onSubmit={createFieldRecord}><label><span>Operação</span><select value={fieldKind} onChange={e=>setFieldKind(e.target.value)}><option value="visit">Nova missão</option><option value="checklist">Verificação / checklist</option><option value="evidence">Evidência</option><option value="report">Relatório final</option></select></label>{fieldKind!=="visit"&&<label><span>Missão</span><select name="visitId" required><option value="">Selecionar</option>{(fieldData.field_visits||[]).filter(v=>!["completed","cancelled"].includes(String(v.status))).map(v=><option value={v.id} key={v.id}>{String(v.subject)} · {String(v.status)}</option>)}</select></label>}{fieldKind==="visit"&&<><label><span>Plataforma</span><select name="platform" required><option value="deligo">DeliGo</option><option value="comunhao">Comunhão</option><option value="taomoz">TaoMoz</option><option value="sarca">SARCA</option></select></label><label><span>Trabalhador</span><select name="workerId" required><option value="">Selecionar</option>{(fieldData.employees||[]).filter(e=>e.status==="active").map(e=><option value={e.id} key={e.id}>{String(e.name)} · {String(e.employee_code)}</option>)}</select></label><label><span>Missão / assunto</span><input name="subject" required/></label><label><span>Tipo</span><select name="visitType"><option value="operational">Operacional</option><option value="verification">Verificação</option><option value="onboarding">Onboarding</option><option value="inspection">Inspeção</option><option value="support">Apoio</option></select></label><label><span>Prioridade</span><select name="priority"><option value="normal">Normal</option><option value="high">Alta</option><option value="urgent">Urgente</option><option value="low">Baixa</option></select></label><label><span>Morada</span><input name="address" required/></label><label><span>Data prevista</span><input name="plannedAt" type="datetime-local" required/></label><label><span>Latitude autorizada</span><input name="latitude" type="number" step=".000001"/></label><label><span>Longitude autorizada</span><input name="longitude" type="number" step=".000001"/></label><label className="fieldCheck"><input name="locationAuthorized" type="checkbox"/><span>Localização autorizada</span></label><label className="fieldCheck"><input name="evidenceRequired" type="checkbox"/><span>Exigir evidência</span></label></>}{fieldKind==="checklist"&&<><label><span>Verificação</span><input name="title" required/></label><label><span>Resultado</span><select name="checkStatus"><option value="pending">Pendente</option><option value="passed">Conforme</option><option value="failed">Não conforme</option><option value="not_applicable">Não aplicável</option></select></label><label><span>Notas</span><input name="notes"/></label><label className="fieldCheck"><input name="required" type="checkbox" defaultChecked/><span>Obrigatória</span></label></>}{fieldKind==="evidence"&&<><label><span>Tipo de evidência</span><select name="evidenceType"><option value="photo">Fotografia</option><option value="document">Documento</option><option value="signature">Assinatura</option><option value="audio">Áudio</option><option value="note">Nota</option></select></label><label><span>Referência segura</span><input name="reference" required/></label><label><span>Latitude</span><input name="latitude" type="number" step=".000001"/></label><label><span>Longitude</span><input name="longitude" type="number" step=".000001"/></label></>}{fieldKind==="report"&&<><label><span>Resumo</span><input name="summary" required/></label><label><span>Resultado</span><select name="outcome"><option value="successful">Bem-sucedida</option><option value="partial">Parcial</option><option value="failed">Falhou</option><option value="rescheduled">Reagendada</option></select></label><label className="fieldCheck"><input name="followUp" type="checkbox"/><span>Exige seguimento</span></label><label><span>Próximo seguimento</span><input name="followUpDue" type="datetime-local"/></label></>}<button className="primaryAction">Guardar</button></form>}
            {fieldNotice&&<div className="operationalNotice">{fieldNotice}</div>}
            <div className="fieldMissionList"><div className="panelTitle"><div><h2>Missões Field</h2><p>Conclusão bloqueada sem checklist, relatório e evidência quando exigida</p></div></div>{(fieldData.field_visits||[]).map(v=>{const worker=(fieldData.employees||[]).find(e=>e.id===v.worker_id),platformName=(fieldData.platforms||[]).find(p=>p.id===v.platform_id)?.name;return <article key={v.id}><div className="fieldMissionIdentity"><i className={String(v.status)}/><div><strong>{String(v.subject)}</strong><span>{String(platformName||"Plataforma")} · {String(worker?.name||"Trabalhador")} · {String(v.visit_type)}</span><small>{v.planned_at?new Date(String(v.planned_at)).toLocaleString("pt-MZ"):"Sem data"} · {v.location_authorized?"localização autorizada":"sem localização"}</small></div></div><b>{String(v.status).replaceAll("_"," ")}</b><div className="fieldActions">{v.status==="planned"&&<button onClick={()=>void fieldAction(v.id,"assign")}>Atribuir</button>}{["planned","assigned"].includes(String(v.status))&&<button onClick={()=>void fieldAction(v.id,"start")}>Iniciar</button>}{v.status==="in_progress"&&<><button onClick={()=>void fieldAction(v.id,"block")}>Bloquear</button><button onClick={()=>void fieldAction(v.id,"complete")}>Concluir</button></>}{v.status==="blocked"&&<button onClick={()=>void fieldAction(v.id,"resume")}>Retomar</button>}{!["completed","cancelled"].includes(String(v.status))&&<button onClick={()=>void fieldAction(v.id,"cancel")}>Cancelar</button>}</div></article>})}{!fieldData.field_visits?.length&&<div className="peopleEmpty">Sem missões Field registadas.</div>}</div>
            <div className="fieldDetailGrid"><article><h3>Verificações</h3>{(fieldData.field_checklists||[]).slice(0,8).map(i=><p key={i.id}><strong>{String(i.title)}</strong><span>{String(i.status).replaceAll("_"," ")}</span></p>)}{!fieldData.field_checklists?.length&&<div className="peopleEmpty">Sem verificações.</div>}</article><article><h3>Relatórios e seguimento</h3>{(fieldData.field_reports||[]).slice(0,8).map(r=><p key={r.id}><strong>{String(r.summary)}</strong><span>{String(r.outcome)}{r.follow_up_required?" · seguimento necessário":""}</span></p>)}{!fieldData.field_reports?.length&&<div className="peopleEmpty">Sem relatórios.</div>}</article></div>
            <div className="safeNotice"><b>Privacidade de localização</b><span>Coordenadas só são guardadas quando a autorização de localização está marcada. Trabalhadores sem autorização não entram neste fluxo nem no mapa operacional.</span></div>
          </section>}
          {active === "Apoio ao Cliente" && <OperationalModule module="support" />}
          {active === "Mapa operacional" && <section className="fullMapWorkspace">
            <div className="fullMapHead"><div><span>TRACKING OPERACIONAL</span><h2>Mapa em tempo real</h2><p>Escolha a plataforma para ver apenas os profissionais que estão online e a enviar GPS.</p></div><div className="mapFilter" role="group" aria-label="Filtrar plataforma do mapa">{["Todas as plataformas", "DeliGo", "SARCA", "TaoMoz"].map((item) => <button key={item} className={platform === item ? "active" : ""} onClick={() => setPlatform(item)}>{item === "Todas as plataformas" ? "Todas" : item}</button>)}</div></div>
            <div className="mapLegend"><span><i className="deligo" />DeliGo · Estafetas</span><span><i className="sarca" />SARCA · Motoristas</span><span><i className="taomoz" />TaoMoz · Couriers</span><b>{mapMarkers.length} ao vivo</b></div>
            <div className="mapControlBar"><input value={mapSearch} onChange={(event) => setMapSearch(event.target.value)} placeholder="Pesquisar trabalhador ou identificação" aria-label="Pesquisar trabalhador no mapa" /><div className="mapFilter" role="group" aria-label="Filtrar estado">{[["todos","Todos"],["disponivel","Disponível"],["ocupado","Ocupado"],["em_servico","Em serviço"],["offline","Offline"]].map(([value,label]) => <button key={value} className={mapStatus === value ? "active" : ""} onClick={() => setMapStatus(value)}>{label}</button>)}</div></div>
            <div className="fullOperationsMap"><LiveOperationsMap markers={filteredMapMarkers} /></div>
            <div className="mapWorkerList">{filteredMapMarkers.map((marker) => <button key={marker.id} onClick={() => setSelectedMapWorker(marker)}><strong>{marker.workerName || marker.role}</strong><span>{marker.platform} · {marker.role} · {marker.status?.replaceAll("_", " ") || "disponível"}</span><small>Atualizado {new Date(marker.updatedAt).toLocaleTimeString("pt-MZ", { hour:"2-digit", minute:"2-digit" })}</small></button>)}{!filteredMapMarkers.length && <div className="peopleEmpty">Sem trabalhadores autorizados com localização recente para este filtro.</div>}</div>
            {selectedMapWorker && <div className="mapWorkerDetail"><div><span>TRABALHADOR AUTORIZADO</span><h3>{selectedMapWorker.workerName || selectedMapWorker.role}</h3><p>{selectedMapWorker.platform} · {selectedMapWorker.role} · {selectedMapWorker.status?.replaceAll("_", " ") || "disponível"}</p></div><div><small>Última localização</small><strong>{new Date(selectedMapWorker.updatedAt).toLocaleString("pt-MZ")}</strong><small>{selectedMapWorker.service ? `Serviço: ${selectedMapWorker.service}` : "Sem serviço activo identificado"}</small></div><button onClick={() => setSelectedMapWorker(null)}>Fechar</button></div>}
            <p className="mapPrivacyNote">As posições são atualizadas a cada 10 segundos e desaparecem se deixarem de ser recebidas durante cinco minutos.</p>
          </section>}
          {active !== "Visão geral" && active !== "Mapa operacional" && active !== "Plataformas" && active !== "Finanças" && active !== "Contabilidade" && active !== "Jurídico" && active !== "Conformidade e Risco" && active !== "Tecnologia / IT" && active !== "Compras" && active !== "Direcção Executiva" && active !== "Pessoas" && active !== "Recursos Humanos" && active !== "Registo de Auditoria" && active !== "Marketing" && active !== "Field" && active !== "Apoio ao Cliente" && !isAccountScreen && (
            <section className="moduleWorkspace">
              <div className="workspaceHead">
                <div><span>ESPAÇO OPERACIONAL</span><h2>{active}{subArea ? ` · ${subArea}` : ""}</h2></div>
                <span className="integrationBadge">INTEGRAÇÃO PENDENTE</span>
              </div>
              <div className="workspaceTable">
                <div className="tableHeader"><span>Área prevista</span><span>Estado</span><span>Fonte</span><span>Permissão</span></div>
                {(moduleDetails[active] || []).map((item) => (
                  <button className={`tableRow ${subArea === item ? "selected" : ""}`} onClick={() => setSubArea(item)} key={item}><strong>{item}</strong><span>Ainda não disponível</span><b>—</b><code>{active.toLowerCase()}.view</code></button>
                ))}
              </div>
              <div className="safeNotice"><b>Módulo não publicado</b><span>Esta área ainda não tem fonte aprovada e, por isso, não exibe métricas, gráficos, exportações nem acções simuladas.</span></div>
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
              ["Valor total processado", money(dashboard?.modules.totalValue || 0), "Soma operacional das quatro plataformas"],
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

          <section className="missionControl">
            <div className="missionControlHead">
              <div><span>CENTRAL DE OPERAÇÕES</span><h2>O que precisa de atenção agora</h2><p>Leitura consolidada do backend central, sem simular estados que ainda não foram integrados.</p></div>
              <button onClick={() => navigate("Tecnologia / IT")}>Ver saúde técnica <ChevronRight aria-hidden="true" /></button>
            </div>
            <div className="missionControlGrid">
              <article className="connectionCard">
                <div className="connectionPulse"><Activity aria-hidden="true" /></div>
                <div><span>PLATAFORMAS LIGADAS</span><strong>{connectedPlatforms}/{dashboard?.platforms.length || 4}</strong><p>{connectedPlatforms === (dashboard?.platforms.length || 4) ? "Todas as fontes disponíveis estão a responder." : "Há uma ou mais fontes que precisam de verificação."}</p></div>
                <button onClick={() => navigate("Plataformas")}>Abrir plataformas</button>
              </article>
              <div className="operationalQueue">
                {operationalItems.map((item) => <button key={item.label} onClick={() => navigate(item.action)}><div><span>{item.label}</span><small>{item.note}</small></div><strong>{item.value}</strong><ChevronRight aria-hidden="true" /></button>)}
              </div>
              <article className="liveMapCard">
                <LiveOperationsMap markers={mapMarkers} />
                <div className="liveMapCopy"><span>MAPA OPERACIONAL · {mapMarkers.length} AO VIVO</span><strong>Tracking em tempo real</strong><p>{mapMarkers.length ? "Posições recentes de estafetas, motoristas e couriers. Actualiza a cada 10 segundos." : "Sem posições recentes para o filtro actual."}</p><button onClick={() => navigate("Mapa operacional")}>Abrir mapa completo</button></div>
              </article>
            </div>
          </section>

          <section className="insightGrid">
            <article className="chartPanel">
              <div className="panelTitle"><div><h2>Desempenho do grupo</h2><p>Receita, operações e crescimento consolidados</p></div><div className="chartLegend"><span><i /> Receita</span><span><i /> Operações</span></div></div>
              <div className="groupRealChart">{(dashboard?.modules.platforms || []).map(item => { const maximum = Math.max(...(dashboard?.modules.platforms || []).map(platform => platform.value), 1); return <div className="groupBar" key={item.slug}><div><strong>{item.name}</strong><span>{money(item.value)}</span></div><i><b style={{width:`${Math.max((item.value/maximum)*100,item.value>0?3:0)}%`}} /></i><small>Volume operacional observado</small></div>; })}{!dashboard?.modules.platforms.length && <div className="peopleEmpty">A aguardar indicadores do backend.</div>}</div>
              <div className="emptyChart legacyChart">
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
                <button onClick={() => { setPlatform(card.name); navigate("Plataformas"); window.history.replaceState({}, "", `/plataformas/${card.slug}`); }}>Abrir {card.name}<span><ChevronRight aria-hidden="true" /></span></button>
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
                ["SI", "Sara Vitorino Feniosse Ismael", "Sócia · Diretora Financeira", "FINANÇAS", "50% participação"],
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
      {selectedProfile && <PlatformProfileModal selected={selectedProfile} detail={profileDetail} onClose={() => setSelectedProfile(null)} />}
    </main>
  );
}

function platformSlug(platform: string) { return platform.includes("Comun") ? "comunhao" : platform === "DeliGo" ? "deligo" : platform === "SARCA" ? "sarca" : "taomoz"; }

function PlatformAdminPanel({ snapshot, platform, onAction, onOpenProfile }: { snapshot: PlatformAdminSnapshot; platform: string; onAction: (action: string, decision: "approve" | "reject" | "correction", id: string, reason?: string) => Promise<void>; onOpenProfile: (id:string, name:string) => void }) {
  const entries = Object.entries(snapshot.data);
  const records = entries.flatMap(([collection, value]) => Array.isArray(value) ? value.slice(0, 20).map(item => ({ collection, row: item as Record<string, unknown> })) : []);
  const reviewable = platform === "DeliGo" || platform === "TaoMoz" || platform.includes("Comun") || platform === "SARCA";
  const actionFor = (decision: "approve" | "reject") => platform.includes("Comun") ? "review_application" : platform === "SARCA" ? "review_driver" : platform === "TaoMoz" ? "review_kyc" : decision;
  const decide = async (decision: "approve" | "reject", id: string, name: string) => {
    const reason = decision === "reject" ? window.prompt(`Motivo da rejeição de ${name}:`) : "";
    if (decision === "reject" && !reason?.trim()) return;
    if (!window.confirm(`${decision === "approve" ? "Aprovar" : "Rejeitar"} ${name}? Esta decisão será auditada.`)) return;
    try { await onAction(actionFor(decision), decision, id, reason || ""); }
    catch (error) { window.alert(error instanceof Error ? error.message : "Não foi possível concluir a decisão."); }
  };
  return <div className="platformAdminPanel"><div className="platformAdminHead"><div><span>ADMINISTRAÇÃO REAL</span><h3>{platform} · operações</h3><p>Dados sincronizados do backend da plataforma e ações protegidas pelo HQ.</p></div><b>{new Date(snapshot.checkedAt).toLocaleTimeString("pt-MZ", { hour: "2-digit", minute: "2-digit" })}</b></div><div className="platformAdminStats">{entries.map(([key, value]) => <article key={key}><span>{key.replaceAll("_", " ")}</span><strong>{Array.isArray(value) ? value.length : "Ligado"}</strong></article>)}</div>{reviewable && records.length > 0 && <div className="platformAdminQueue"><div className="platformAdminQueueTitle"><h4>Fila de administração</h4><span>{records.length} registos</span></div>{records.map(({ collection, row }, index) => { const id = String(row.id || row.user_id || row.profile_id || index); const name = String(row.full_name || row.name || row.church_name || row.store_name || row.order_number || id); const status = String(row.status || row.kyc_status || row.moderation_status || row.account_status || "—"); return <div className="platformAdminRow" key={`${collection}-${id}`}><button className="profileLink" onClick={() => onOpenProfile(id, name)}><strong>{name}</strong><small>{collection} · {status}</small></button>{(status === "pending" || status === "submitted" || status === "under_review") && <div className="platformAdminActions"><button onClick={() => void decide("approve", id, name)}>Aprovar</button><button className="danger" onClick={() => void decide("reject", id, name)}>Rejeitar</button></div>}</div>; })}</div>}</div>;
}

function PlatformProfileModal({ selected, detail, onClose }: { selected:{platform:string;id:string;name:string}; detail:PlatformProfile|null; onClose:()=>void }) {
  const profile = detail?.profile || {};
  const media = (detail?.kyc || []).flatMap(item => { const row = (item || {}) as Record<string,unknown>; return Object.entries(row).filter(([key, item]) => ["photo_url","image_url","document_url","file_url","selfie_url","document_front_path","document_back_path","selfie_path","proof_url"].includes(key) && typeof item === "string").map(([key, item]) => ({ key, url:item as string })); });
  return <div className="kycGalleryBackdrop" onClick={onClose}><div className="profileModal" onClick={event => event.stopPropagation()}><div className="kycGalleryHead"><div><span>PERFIL · {selected.platform.toUpperCase()}</span><h3>{selected.name}</h3><p>{String(profile.phone || "—")} · {String(profile.account_status || profile.kyc_status || "—")} · ID {selected.id}</p></div><button onClick={onClose}>Fechar</button></div><div className="profileSummary"><article><span>Saldo</span><strong>{detail?.wallets.length ? detail.wallets.map(item => String((item as Record<string,unknown>).balance || 0)).join(" · ") : "—"}</strong></article><article><span>Operações</span><strong>{detail?.orders.length || 0}</strong></article><article><span>Disputas</span><strong>{detail?.disputes.length || 0}</strong></article><article><span>Actividade</span><strong>{detail?.activity.length || 0}</strong></article></div>{!detail && <div className="peopleEmpty">A carregar perfil, saldo e histórico…</div>}{detail && <><h4 className="profileSectionTitle">Galeria KYC</h4>{media.length ? <div className="kycGalleryGrid">{media.map(item => <a href={item.url} target="_blank" rel="noreferrer" key={`${item.key}-${item.url}`}><img src={item.url} alt={item.key} /><strong>{item.key.replaceAll("_", " ")}</strong></a>)}</div> : <div className="peopleEmpty">Nenhuma fotografia KYC disponível.</div>}<h4 className="profileSectionTitle">Histórico recente</h4><div className="profileHistory">{[...(detail.orders || []), ...(detail.disputes || [])].slice(0, 12).map((item, index) => { const row = item as Record<string,unknown>; return <div key={String(row.id || index)}><strong>{String(row.order_number || row.type || row.status || "Operação")}</strong><span>{String(row.created_at || row.updated_at || "—")}</span></div>; })}</div></>}</div></div>;
}

export default function Home() {
  return <HQApp />;
}
