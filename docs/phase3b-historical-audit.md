# Fase 3B — Auditoria e séries históricas

Data: 2026-10-23  
Escopo: consultas agregadas somente de leitura; sem migrations, pagamentos, webhooks ou alterações de saldos.

## Fontes encontradas

| Fonte | Campos verificáveis | Métricas suportadas | Estado |
| --- | --- | --- | --- |
| `hq.platform_financial_events` | `id`, `platform_id`, `source_record_id`, `gross_amount`, `platform_fee`, `payment_status`, `occurred_at`, `created_at` | GMV, receita/comissões confirmadas, contagem de eventos financeiros | Canónica para eventos financeiros HQ |
| `hq.platform_events` | `id`, `platform_id`, `source_event_id`, `event_type`, `entity_type`, `occurred_at`, `created_at` | Volume de eventos operacionais, cancelamentos identificáveis pelo tipo | Canónica para actividade de eventos HQ |
| `hq.central_daily_metrics` | `metric_date`, `platform_id`, `metric_code`, `metric_value`, `calculated_at` | Potencialmente diária | Existe, mas não foi encontrada rotina de alimentação; não é usada como dado real |

## Regras aplicadas

- A data contabilística da série financeira é `occurred_at`, não `created_at`.
- Só `payment_status = confirmed` entra em GMV, receita e comissões.
- Eventos são deduplicados por `platform_id + source_record_id` ou `platform_id + source_event_id`; quando ausente, usa-se o ID interno.
- Cancelamentos só são contados quando `event_type` contém `cancel`, `cancelled`, `canceled`, `rejected` ou `failed`.
- Os limites de dia são calculados em `Africa/Maputo` e convertidos para UTC na consulta.
- A comparação percentual retorna `null` quando o período anterior não tem dados ou o denominador é zero.
- Saldos atuais não são usados para reconstruir movimentos históricos.

## Métricas disponíveis

- Receita diária no período.
- GMV diário no período.
- Comissões confirmadas.
- Volume de eventos operacionais.
- Cancelamentos identificáveis.
- Comparação com período anterior equivalente.

## Métricas ainda indisponíveis

Utilizadores activos históricos, novos utilizadores, subscrições activas/vencidas, serviços concluídos específicos, tempo médio de entrega e viagens concluídas exigem eventos de domínio com semântica confirmada. Como esses campos não estão expostos de forma verificável nas fontes auditadas, a API não inventa pontos nem os apresenta como zero confirmado.

## Implementação

- Endpoint read-only: `/api/analytics/history`.
- Períodos: últimos 7, 30, 90 dias e intervalo personalizado.
- Limite de consulta: 10.000 eventos por fonte; a resposta indica `truncated` quando o limite é atingido.
- RBAC: `dashboard.view`, com filtro adicional pelas plataformas autorizadas.
- Interface: Visão Geral reutiliza `DashboardFilters`, `KPIGrid`, `ChartContainer`, `TrendIndicator`, `DataFreshnessIndicator` e `EmptyState`.
- Os gráficos usam apenas pontos devolvidos pela API; sem pontos válidos, mostram indisponibilidade.
