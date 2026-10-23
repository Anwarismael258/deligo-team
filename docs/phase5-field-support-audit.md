# Fase 5 — Auditoria de Operações de Campo e Apoio ao Cliente

## Fontes canónicas usadas

| Área | Fonte | Uso |
| --- | --- | --- |
| Campo | `public.field_visits` | visitas concluídas, datas e tipo de atividade |
| Campo | `hq.acquisition_leads` | estabelecimentos contactados e conversão |
| Campo | `hq.acquisition_partners` | novos parceiros e estados aprovados |
| Campo | `hq.tasks` | tarefas pendentes/concluídas, responsável e prazo |
| Campo | `hq.employees`, `hq.platforms` | agentes ativos, filtros e nomes de plataforma |
| Suporte | `hq.support_tickets` | fila, estados, prioridade, atribuição e tempos |
| Suporte | `hq.support_conversations` | primeira resposta verificável |
| Suporte | `hq.support_history` | reaberturas por evento |

## Fórmulas

- Visitas realizadas: registos de `field_visits` cujo estado é `completed`, `done` ou `realized` no período.
- Conversão: leads com estado `won`, `approved` ou `converted` divididos pelos leads criados no período; sem denominador não há percentagem.
- Parceiros aprovados: união deduplicada por identificador entre leads e parceiros aprovados.
- Primeira resposta: primeira mensagem do ticket cujo `sender_type` não é `customer`, menos a criação do ticket, em minutos.
- Resolução média: `resolved_at`, `closed_at` ou `updated_at` menos a abertura, apenas para estados resolvidos.
- Críticos: prioridade `critical`, `urgent` ou `high` e estado não resolvido.
- Reabertos: `reopen_count > 0` ou evento de histórico contendo `reopen`.

Todos os intervalos são calculados em `Africa/Maputo`, com períodos de 7, 30, 90 dias ou intervalo personalizado.

## Limitações conhecidas

- A taxa de conversão é operacional e não uma métrica financeira.
- A identificação de agentes depende de `role` ou `department_id` reconhecível como Field/Operations; departamentos sem código/nome exposto não são inferidos.
- SLA e satisfação não são exibidos sem política e dados verificáveis.
- O dashboard agregado usa a fila HQ `support_tickets`; casos do núcleo `core.support_cases` continuam disponíveis no endpoint operacional existente, mas não são somados para evitar duplicação sem uma chave de correspondência verificável.
- Esta camada não altera tickets, tarefas, notificações, saldos, PaySuite, RLS ou RBAC.
