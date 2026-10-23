# Fase 11 — Matriz final de analytics nas funcionalidades existentes

Escopo aplicado: analytics integrado nas áreas já existentes. Não foram criados menus, páginas operacionais, migrations, fluxos financeiros ou sistemas independentes.

| Área | Função existente | KPIs / gráficos | Fonte real | Realtime / atualização | Estado |
| --- | --- | --- | --- | --- | --- |
| Visão Geral | dashboard executivo | receita, GMV, operações, plataformas, custódia, alertas; séries e comparação | `/api/dashboard`, `/api/analytics/history`, Command Center | polling/cursor existente; revalidação autorizada | Implementada com restrições |
| Plataformas | portefólio e detalhe da plataforma | receita, GMV, operações, carteiras; distribuição e evolução | `/api/dashboard`, `/api/analytics/history` | atualização do dashboard existente | Implementada com restrições |
| Utilizadores | diretório de utilizadores | total, novos, ativos quando verificáveis, suspensos, pendentes; plataforma, papel e série | `/api/analytics/users-team`, `global_user_platforms_v1` | atualização existente | Implementada com restrições |
| Pessoas/Equipa | equipa e tarefas | trabalhadores, ativos, tarefas criadas/concluídas/atrasadas; departamentos e estados | `/api/analytics/users-team`, `hq.tasks` | eventos/polling existente | Implementada com restrições |
| Finanças | consolidação/reconciliação | receita, carteiras, custódia, pendências, qualidade; fontes e reconciliação | `/api/finance/reconciliation` e ledger existente | após fontes autorizadas; não inventa PaySuite | Implementada com restrições |
| Operações de Campo | visitas, parceiros e KYC | agentes, visitas, leads, conversão, parceiros, tarefas; série e distribuição | `/api/analytics/operations-support`, Field/Aquisição | revalidação pelo feed existente | Implementada com restrições |
| Apoio ao Cliente | tickets/conversas | abertos, resolvidos, pendentes, críticos, tempos; estado, prioridade e série | `/api/analytics/operations-support`, tickets/histórico | revalidação pelo feed existente | Implementada com restrições |
| Marketing | campanhas e leads | campanhas, leads, conversão, investimento/CPL quando existentes; estados e canais | `/api/analytics/communication` | atualização existente | Implementada com restrições |
| Caixa de Entrada | mensagens e conversas | recebidas, enviadas, abertas, pendentes, atribuídas, sem resposta; canais/estados | `/api/analytics/communication`, inbox | feed/polling existente | Implementada com restrições |
| Centro de Notificações | outbox e notificações | geradas, enviadas, falhadas, pendentes, lidas; tipos e estados | `/api/analytics/communication`, notificações | feed/polling existente | Implementada com restrições |
| Site Institucional | CMS e formulários | conteúdos, estados, formulários/contactos registados; tipos e evolução | `/api/analytics/corporate-operations` | atualização da área existente | Implementada com restrições |
| Vagas/Recrutamento | vagas e candidaturas | vagas, candidaturas, estados e departamentos; funil disponível | `/api/analytics/corporate-operations` | atualização da área existente | Implementada com restrições |
| Projetos/Tarefas | projetos e tarefas | ativos/concluídos, pendentes, atrasadas, prioridade e estado; série | `/api/analytics/corporate-operations`, projects | eventos/polling existente | Implementada com restrições |
| Relatórios | relatórios/exportações | disponibilidade, tipos, estados e geração registada | `/api/analytics/corporate-operations`, reports | atualização da área existente | Implementada com restrições |
| Triunfal Microcrédito | pedidos e análise | pedidos, estados, montantes solicitados quando disponíveis; série por estado | `/api/analytics/microcredit`, `loan_applications` | atualização existente | Implementada com restrições |
| Centro de Mapas | mapa operacional | posições atuais, operações, entregas/viagens e histórico; distribuição por plataforma | `/api/map`, `/api/analytics/map`, `hq.platform_events` | polling/cursor; sem tracking novo | Implementada com restrições |
| Auditoria/Compliance | registo de auditoria | eventos, acessos e alterações existentes; filtros do registo | `/api/audit` | consulta autorizada | Sem dashboard dedicado; fonte parcial |

## Regras aplicadas

- Período padrão: 30 dias.
- Fuso horário: `Africa/Maputo`.
- Receita, GMV, carteiras de utilizadores, passivos e PaySuite permanecem separados.
- `Indisponível` não é convertido em zero.
- Não são calculados DAU/MAU, retenção, churn, CSAT, CAC, ROAS, PAR30, distância, velocidade, percurso ou cobertura quando não há fonte verificável.
- O feed e as ações pendentes reutilizam o Command Center existente; não executam operações automaticamente.
- System Health marca integrações sem confirmação recente como `Desconhecido` ou `Degradado`.
- Nenhuma alteração foi feita a RLS/RBAC, PaySuite, webhooks, ledger, pagamentos ou carteiras.

## Validação desta revisão

- TypeScript: PASS.
- Build: PASS.
- Testes Node: PASS — 121/121.
- Playwright: última execução 6/6; deve ser repetido em staging autenticado após esta revisão.
- Lint: ainda não concluído dentro do tempo disponível; não classificado como PASS.
- Deploy/migrations: não executados.
