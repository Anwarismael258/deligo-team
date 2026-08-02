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
                <div><span>VOLUME OPERACIONAL OBSERVADO</span><strong>{money(selectedOperationalValue)}</strong><small>{platform} · valor processado no staging, não representa receita, tesouraria ou lucro.</small></div>
                <div className="financeGuard"><ShieldCheck aria-hidden="true" /><div><b>Separação financeira activa</b><span>Carteiras de utilizadores não são tratadas como dinheiro da empresa.</span></div></div>
              </div>
              <div className="financialBreakdown">
                {selectedFinancialPlatforms.map((item) => <article key={item.slug}><span>{item.name}</span><strong>{money(item.value)}</strong><small>Volume operacional</small></article>)}
                {!selectedFinancialPlatforms.length && <div className="peopleEmpty">Sem valores financeiros disponíveis para este contexto.</div>}
              </div>
              <div className="financeColumns">
                <article className="financePanel"><div className="panelTitle"><div><h2>Posição financeira</h2><p>Somente fontes confirmadas pelo backend</p></div></div>{[
                  ["Tesouraria corporativa", "—", "Fonte ainda não ligada"], ["Receitas reconhecidas", "—", "Contabilidade ainda não ligada"], ["Despesas", "—", "Contabilidade ainda não ligada"], ["Lucro líquido", "—", "Exige fecho contabilístico"],
                ].map(([label,value,note]) => <div className="financeLine" key={label}><div><strong>{label}</strong><span>{note}</span></div><b>{value}</b></div>)}</article>
                <article className="financePanel"><div className="panelTitle"><div><h2>Aprovações protegidas</h2><p>Decisões financeiras e societárias</p></div></div>{[
                  ["Distribuição de lucros", "2 sócios"], ["Dívida material", "2 sócios"], ["Venda de património material", "2 sócios"], ["Alteração de quotas", "2 sócios"],
                ].map(([label,rule]) => <div className="financeLine" key={label}><div><strong>{label}</strong><span>Sem proposta activa</span></div><em>{rule}</em></div>)}</article>
              </div>
              <div className="safeNotice"><b>Escrita protegida</b><span>Consulta real disponível. Criar, aprovar, pagar e reconciliar permanecem bloqueados até a autenticação corporativa validar cada actor no servidor.</span></div>
            </section>
          )}
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
          {active === "Registo de Auditoria" && (
            <section className="auditWorkspace"><div className="employeeAdminHead"><div><span>REGISTO IMUTÁVEL</span><h2>Auditoria e histórico</h2><p>Criação, aprovação, suspensão, arquivo e operações sensíveis.</p></div><div><button onClick={exportAudit}>Exportar CSV</button><b>{auditRecords.length} eventos</b></div></div><div className="auditTable"><div className="auditRow auditHeader"><span>Data</span><span>Actor</span><span>Acção</span><span>Resultado</span></div>{auditRecords.map(event=><div className="auditRow" key={event.id}><span>{new Date(event.occurred_at).toLocaleString("pt-MZ")}</span><strong>{event.actor}</strong><span>{event.action.replaceAll("_"," ")}</span><b>{event.result}</b></div>)}{!auditRecords.length&&<div className="peopleEmpty">Sem eventos disponíveis para este perfil.</div>}</div></section>
          )}
          {active === "Marketing" && <OperationalModule module="marketing" />}
          {active === "Field" && <OperationalModule module="field" />}
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
          {active !== "Visão geral" && active !== "Mapa operacional" && active !== "Plataformas" && active !== "Finanças" && active !== "Direcção Executiva" && active !== "Pessoas" && active !== "Recursos Humanos" && active !== "Registo de Auditoria" && active !== "Marketing" && active !== "Field" && active !== "Apoio ao Cliente" && !isAccountScreen && (
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
