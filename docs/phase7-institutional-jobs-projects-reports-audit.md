# Fase 7 — auditoria e analytics operacionais

## Fontes canónicas auditadas

| Área | Fonte | Uso confirmado |
| --- | --- | --- |
| Site Institucional | `hq.news` | conteúdo editorial, estado, categoria e datas |
| Vagas | `hq.job_openings` | vagas, publicação, estado e departamento |
| Projectos/Tarefas | `hq.projects`, `hq.tasks`, `hq.project_milestones` | estados, prioridades, prazos e conclusões |
| Relatórios | `hq.saved_reports`, `hq.report_schedules`, `hq.report_runs` | disponibilidade, geração e estados de execução |

O endpoint `GET /api/analytics/corporate-operations` é somente leitura, aplica autorização da Central, usa o fuso `Africa/Maputo` e aceita períodos de 7, 30, 90 dias ou intervalo personalizado. Os painéis reutilizam os componentes de `components/analytics/`.

## Limitações deliberadas

Não foram encontrados no código auditado eventos/tabelas verificáveis para formulários institucionais, contactos, visitas, leads, candidaturas, entrevistas ou contratações. Esses indicadores aparecem como indisponíveis, sem valores estimados. Relatórios não exibem consultas quando o backend não regista esse evento. Os dashboards não alteram dados e não mexem em autenticação, RBAC, RLS, finanças ou PaySuite.
