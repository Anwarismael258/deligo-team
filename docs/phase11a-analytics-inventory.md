# Fase 11A — Inventário e Catálogo de Analytics

Data da auditoria: 23/10/2026  
Branch: `feature/hq-executive-analytics`  
Timezone: `Africa/Maputo`  
Período padrão: `last_30_days`

## Conclusão da auditoria

A Central já possui uma base comum de analytics nas Fases 1–10: `KPIGrid`, `KPICard`, `DashboardFilters`, `ChartContainer`, `AnalyticsDataTable`, estados de erro/vazio e indicadores de atualização. Os dashboards são somente leitura e reutilizam APIs protegidas por autorização de servidor.

Nesta Fase 11A não foram alterados componentes, APIs, dados, RLS/RBAC, pagamentos, PaySuite, webhooks ou migrations. Este documento é o catálogo e a matriz de lacunas para aprovação antes das fases de implementação.

## Matriz dos 17 módulos

| Área | Componente atual | API/fonte principal | Estado atual | Lacunas verificadas |
| --- | --- | --- | --- | --- |
| Visão Geral | `ExecutiveOverviewDashboard` | `/api/dashboard`, `/api/analytics/history` | KPIs, comparação, receita/GMV/operações e alertas | Utilizadores ativos comerciais, waterfall e receita líquida com reversões exigem eventos específicos |
| Plataformas | `PlatformExecutiveDashboard` | `/api/dashboard`, `/api/analytics/history` | Comparação por plataforma, KPIs e série filtrável | Funis, percentis de entrega e KPIs específicos dependem de eventos por plataforma |
| Utilizadores | `UserTeamDashboard(mode=users)` | `/api/analytics/users-team`, `global_user_platforms_v1` | Pessoas únicas, novos registos, estados, papéis e plataformas | DAU, MAU, retenção, churn e cohorts não têm evento de atividade elegível consolidado |
| Pessoas e Equipa | `UserTeamDashboard(mode=team)` | `/api/analytics/users-team`, `hq.tasks`, employees | Trabalhadores, departamentos, tarefas, estados e atrasos | Assiduidade, complexidade e produtividade individual não são inferidas |
| Finanças | `FinanceReadOnlyDashboard` | `/api/finance/reconciliation`, fontes `hq`/wallets | Receita, carteiras, custódia, qualidade e estado PaySuite | Waterfall completo e saldo PaySuite oficial continuam indisponíveis sem fonte verificável |
| Operações de Campo | `OperationsSupportDashboard(mode=field)` | `/api/analytics/operations-support`, visitas, aquisição, tarefas | Visitas, leads, parceiros, conversão e tarefas | Cobertura geográfica e tempo até ativação requerem fontes/definições adicionais |
| Apoio ao Cliente | `OperationsSupportDashboard(mode=support)` | tickets, conversas e histórico | Abertos, resolvidos, backlog, prioridade e tempos | SLA e CSAT não são apresentados sem política e respostas válidas |
| Marketing | `CommunicationAnalyticsDashboard(mode=marketing)` | `/api/analytics/communication`, campanhas/leads | Campanhas, leads, conversão e investimento quando existente | CAC/ROAS exigem despesa e receita com atribuição verificável |
| Caixa de Entrada | `CommunicationAnalyticsDashboard(mode=inbox)` | mensagens, replies e conversas | Volume, canais, estados e sem resposta | Heatmap horário e métricas P50/P90 dependem de timestamps suficientes |
| Notificações | `CommunicationAnalyticsDashboard(mode=notifications)` | `hq.notifications`/outbox | Geradas, enviadas, falhadas, pendentes e lidas | Entrega efetiva e latência só podem ser mostradas com confirmação do provedor |
| Site Institucional | `CorporateOperationsAnalyticsDashboard(mode=institutional)` | institucional/news/forms disponíveis | Conteúdos, estados e entradas registadas | Sessões, visitantes, origem e conversão não existem sem analytics de tráfego |
| Vagas e Recrutamento | `CorporateOperationsAnalyticsDashboard(mode=jobs)` | vagas e candidaturas institucionais | Vagas, candidaturas, estados e departamentos | Tempo de contratação e origem por candidato requerem timestamps completos |
| Projetos e Tarefas | `CorporateOperationsAnalyticsDashboard(mode=projects)` | `/api/analytics/corporate-operations`, projetos/tarefas | Projetos, estados, prioridades e evolução | Burndown, capacidade e tempo de ciclo dependem de início efetivo e marcos |
| Relatórios | `CorporateOperationsAnalyticsDashboard(mode=reports)` | `/api/analytics/corporate-operations`, reports | Disponibilidade, tipos, estados e evolução registada | Latência P95 e cobertura de indicadores exigem histórico de execução |
| Triunfal Microcrédito | `MicrocreditAnalyticsDashboard` | `/api/analytics/microcredit`, `loan_applications` e fontes staging | Pedidos, estados, tipos e séries; aprovado não é desembolso | PAR30, mora, recebimentos e garantias só quando as tabelas e registos existirem |
| Centro de Mapas | `OperationsMapDashboard` | `/api/map`, `/api/analytics/map`, `hq.platform_events` | Posições atuais, operações, entregas/viagens concluídas e histórico | Distância, velocidade, percurso real, duração média e produtividade GPS exigem telemetria consolidada |
| Auditoria e Compliance | módulo de auditoria existente | `/api/audit`, eventos de auditoria | Eventos e exportação autorizada existentes | Dashboard dedicado de severidade, incidentes e matriz de risco ainda não está catalogado como fonte própria |

## Catálogo inicial de métricas

Cada métrica abaixo deve manter uma única definição. `qualityStatus` significa a qualidade da fonte, não uma estimativa.

| metricId | Nome | Fórmula | Fonte canónica | Estado |
| --- | --- | --- | --- | --- |
| `overview.revenue.confirmed` | Receita confirmada | créditos confirmados − reversões/estornos reconhecidos | eventos financeiros HQ | Parcial/verificável apenas para eventos disponíveis |
| `overview.gmv.confirmed` | GMV confirmado | soma de `gross_amount` de pagamentos confirmados | `hq.platform_financial_events` | Verificável por período |
| `overview.operations` | Operações | eventos operacionais deduplicados por origem/id | `hq.platform_events` | Verificável, não equivalente a pedidos concluídos |
| `users.registered` | Utilizadores registados | pessoas únicas no diretório autorizado | `global_user_platforms_v1` | Verificável |
| `users.active` | Utilizadores ativos | atividade elegível distinta no período | Fonte de atividade consolidada | Indisponível até definição/eventos elegíveis |
| `team.tasks.completed` | Tarefas concluídas | tarefas com estado concluído e data válida | `hq.tasks` | Verificável |
| `field.conversion` | Conversão de campo | parceiros aprovados atribuíveis ÷ leads elegíveis | aquisição/field | Verificável com limitações documentadas |
| `support.first_response_minutes` | Primeira resposta | primeiro timestamp não-cliente − abertura | tickets/conversas | Parcial |
| `marketing.conversion` | Conversão de leads | leads convertidos ÷ leads captados | marketing leads | Verificável quando os estados existem |
| `notifications.delivery_rate` | Taxa de entrega | entregas confirmadas ÷ envios elegíveis | outbox/provedor | Indisponível sem confirmação de entrega |
| `finance.corporate_revenue` | Receita corporativa | receita própria reconhecida, sem carteiras de terceiros | ledger financeiro HQ | Verificável conforme reconciliação |
| `finance.user_wallets` | Carteiras de utilizadores | saldo disponível de terceiros | fonte canónica de wallets | Verificável por snapshot; não é receita |
| `microcredit.disbursed` | Desembolsado | desembolsos confirmados | `loan_disbursements` | Indisponível se fonte/registos não existirem |
| `map.operations_active` | Operações ativas | marcadores atuais autorizados | `/api/map` | Verificável no momento da leitura |

## Filtros e períodos

Já existe um contrato comum com `Africa/Maputo`, período padrão de 30 dias, 7/30/90 dias e intervalo personalizado. Hoje/ontem, mês atual e mês anterior ainda não são aceites uniformemente por todas as APIs; não serão adicionados ao catálogo como suportados até haver um contrato comum e testes de limites.

Os períodos históricos utilizam data de ocorrência/criação conforme a definição da fonte e deduplicação por identificador de evento. Valores desconhecidos permanecem `null`/“Indisponível”; zero só representa ausência confirmada dentro de uma série suportada.

## Realtime e IA

- Realtime: existem eventos e atualização automática em domínios específicos, além de polling controlado do mapa. Ainda não existe uma subscrição única e uniforme para os 17 dashboards com recuperação, deduplicação e indicador comum.
- IA: existe infraestrutura de chat, mas não existe ainda um painel `DeliGo Intelligence` ligado exclusivamente a agregados autorizados, com fontes, período, hipóteses e auditoria de uso. Não deve ser ativado nesta auditoria.

## Segurança e riscos

- As APIs analíticas existentes exigem sessão/permissão no servidor; ocultar o menu não é considerado segurança suficiente.
- Finanças continua read-only e não deve declarar reconciliação externa PaySuite sem endpoint/documentação oficial e evidência do período.
- Dados de candidatos, tickets, BI, documentos e carteiras não devem aparecer nos gráficos agregados sem autorização específica.
- Não criar DAU/MAU, cohorts, CSAT, CAC, ROAS, PAR30, waterfall, distância ou cobertura geográfica com dados estimados.
- Auditoria de desempenho, Playwright autenticado e staging isolado permanecem etapas posteriores.

## Aprovação necessária

Após aprovação deste inventário, a sequência recomendada é:

1. 11B — consolidar visualmente os componentes e estados.
2. 11C — executivo, plataformas e finanças, apenas com as fontes confirmadas.
3. 11D–11F — completar módulos operacionais e especializados.
4. 11G — Realtime e DeliGo Intelligence, com limites e auditoria.
5. 11H — validação E2E, segurança, desempenho e staging.

Nenhuma alteração de produção ou deploy foi executada nesta Fase 11A.
