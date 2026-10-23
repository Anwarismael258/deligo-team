# Fase 4 — Auditoria de Utilizadores e Equipa

## Fontes canónicas auditadas

| Área | Fonte | Campos usados | Regra |
| --- | --- | --- | --- |
| Utilizadores | `hq.global_user_platforms_v1` | `user_id`, `app_slug`, `joined_at`, `profile_status`, `membership_status`, `roles` | Uma pessoa é contada uma vez; associações de plataforma são contadas separadamente. |
| Equipa | `hq_employee_directory_v1` | `id`, `status`, `department_code/name` | Directório oficial de trabalhadores, sem expor documentos ou salários. |
| Tarefas | `hq.tasks` | `status`, `created_at`, `completed_at`, `due_at`, `department_id` | Concluídas exigem `status=completed` e `completed_at`; atraso exclui concluídas/canceladas. |
| Departamentos | `hq.departments` | `id`, `code`, `name`, `active` | Catálogo para filtros e agregação. |

## Implementação

`/api/analytics/users-team` é uma API somente de leitura, protegida por `users.view`, com períodos de 7/30/90 dias e intervalo personalizado em `Africa/Maputo`. Aceita filtros de plataforma, departamento e estado.

O dashboard reutiliza `DashboardFilters`, `DashboardHeader`, `KPIGrid`, `ChartContainer`, `AnalyticsDataTable`, `EmptyState` e `TrendIndicator`. A área Utilizadores mostra pessoas únicas, novos registos, estados, plataformas, papéis e série de novos registos. A área Equipa mostra trabalhadores, estados, departamentos, tarefas, atrasos e série de conclusões.

## Limitações verificáveis

- “Activo” só é apresentado quando o estado da fonte é explicitamente `active`.
- Não se calcula produtividade individual nem ranking de trabalhadores.
- `last_seen_at` não é usado para inventar novos registos ou actividade.
- Perfis multiplataforma não são somados como pessoas distintas.
- Sem `completed_at`, uma tarefa concluída não entra na série histórica.
- Não foram alteradas tabelas, migrations, RLS, RBAC, autenticação ou dados financeiros.
