# Fase 6 — Auditoria de Marketing, Caixa de Entrada e Notificações

## Fontes auditadas

| Módulo | Fontes reais | Estado |
| --- | --- | --- |
| Marketing | `hq.marketing_campaigns`, `hq.marketing_leads`, `hq.marketing_metrics`, `hq.marketing_channels` | Implementadas no analytics somente leitura |
| Caixa de Entrada | `staging.inbox_messages`, `staging.inbox_replies` | Implementadas no analytics, respeitando áreas do trabalhador |
| Notificações | `hq.notifications` | Implementadas para o trabalhador autenticado |

## Regras de cálculo

- Campanhas ativas: campanhas criadas no período com estado `active`, `published` ou `running`.
- Conversão de marketing: leads com estado `converted`, `won` ou `approved` divididos pelos leads do período.
- Investimento: soma de `marketing_metrics.spend`; custo por lead só é apresentado com leads verificáveis.
- Caixa de entrada: mensagens e respostas são contadas a partir das suas tabelas de origem; uma mensagem sem `inbox_replies` é marcada como sem resposta.
- Notificações: `created`, `queued`, `sent`, `delivered`, `failed` e `read` permanecem estados distintos; leitura usa `read_at` ou estado `read`.

## Limitações

- Receita atribuída e custo por aquisição não são inferidos sem ligação verificável a uma transação.
- O tempo médio de resposta da caixa de entrada permanece indisponível sem relação segura entre mensagem e primeira resposta.
- O Centro de Notificações mostra apenas o destinatário autenticado e não expõe corpo, tokens ou credenciais.
- A entrega ao dispositivo só é considerada confirmada quando o fornecedor grava um estado correspondente.
- Nenhuma consulta deste módulo altera campanhas, mensagens ou notificações.
