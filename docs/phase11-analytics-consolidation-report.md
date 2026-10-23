# Fase 11 — Consolidação Visual e Funcional de Analytics

## Objetivo

Uniformizar os dashboards existentes da Central HQ sem criar uma segunda camada de analytics, sem inventar dados e sem alterar saldos, pagamentos, permissões ou integrações.

## Auditoria dos módulos

| Módulo | Componente | Fonte/API | Estado |
| --- | --- | --- | --- |
| Visão geral | `ExecutiveOverviewDashboard` | `/api/dashboard`, `/api/analytics/history` | KPIs, comparação temporal e estado de fonte implementados |
| Plataformas | `PlatformExecutiveDashboard` | `/api/dashboard`, `/api/analytics/history` | Filtros de período e série histórica adicionados nesta fase |
| Utilizadores | `UserTeamDashboard` | `/api/analytics/users-team` | KPIs, distribuição, estados e série real |
| Pessoas/Equipa | `UserTeamDashboard` | `/api/analytics/users-team` | KPIs de equipa, departamentos, estados e tarefas |
| Finanças | `FinanceReadOnlyDashboard` | `/api/finance/reconciliation` | Somente leitura; separa receita, carteiras e reconciliação |
| Operações de Campo | `OperationsSupportDashboard` | `/api/analytics/operations-support` | KPIs, filtros, conversões e tarefas |
| Apoio ao Cliente | `OperationsSupportDashboard` | `/api/analytics/operations-support` | Tickets, prioridades, tempos e estados |
| Marketing | `CommunicationAnalyticsDashboard` | `/api/analytics/communication` | Campanhas, leads e conversões apenas quando verificáveis |
| Caixa de Entrada | `CommunicationAnalyticsDashboard` | `/api/analytics/communication` | Volume, canais, estados e pendências |
| Notificações | `CommunicationAnalyticsDashboard` | `/api/analytics/communication` | Criação, envio, falhas e leituras |
| Site/Vagas/Projetos/Relatórios | `CorporateOperationsAnalyticsDashboard` | `/api/analytics/corporate-operations` | KPIs, distribuições e séries reais |
| Microcrédito | `MicrocreditAnalyticsDashboard` | `/api/analytics/microcredit` | Pedidos e estados; aprovação não é desembolso |
| Mapa operacional | `OperationsMapDashboard` | `/api/map`, `/api/analytics/map` | Mapa atual e histórico operacional por período |

## Alterações desta fase

- Plataformas passou a reutilizar `DashboardFilters` com 7/30/90 dias e intervalo personalizado.
- Plataformas passou a consultar `/api/analytics/history` com filtro da plataforma e a apresentar evolução histórica confirmada.
- Centro de Mapas passou a aplicar o período selecionado ao histórico operacional, mantendo a leitura de posições atuais separada.
- Foram mantidas as mensagens de indisponibilidade quando não há fonte verificável.
- Nenhum valor ilustrativo foi ligado a produção.

## Regras financeiras

Receita própria, GMV, carteiras de terceiros e custódia continuam separados. O dashboard não reconstrói histórico a partir de saldos atuais e não declara reconciliação PaySuite sem evidência oficial.

## Validação

- TypeScript: PASS.
- Build Vinext: PASS.
- Testes Node: PASS — 121/121.
- Deploy/produção: não executado.
- Migrations, pagamentos, webhooks e alterações de RBAC/RLS: não executados.

## Limitações

Distância, velocidade, percurso real, tempo médio de entrega e métricas de utilização de veículos continuam indisponíveis quando a fonte não fornece telemetria histórica suficiente. Isso é apresentado como indisponível, nunca como zero.
