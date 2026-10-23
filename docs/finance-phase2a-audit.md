# Fase 2A — Auditoria financeira somente de leitura

## Fontes canónicas identificadas

| Indicador | Fonte usada | Estado |
| --- | --- | --- |
| Receita corporativa confirmada | `hq.corporate_revenue_credits` e `hq.platform_financial_events`, via RPC `corporate_revenue_summary_v1` | Disponível quando a RPC responde |
| GMV e receita por plataforma | `hq.platform_financial_events`, via RPC `financial_platform_summary_v1` | Disponível quando a RPC responde |
| Carteiras DeliGo | `deligo.legacy_wallets`, filtrando carteiras activas ligadas a perfis reais | Disponível quando a fonte responde |
| Carteiras de outras plataformas | `payments.wallet_accounts`, separando contas de utilizadores de contas técnicas/escrow | Disponível na rotina de fallback existente |
| Movimentos contabilísticos | `financial_transactions`, `journal_entries` e `journal_lines` | Leitura existente em Finanças/Contabilidade |
| Levantamentos e reembolsos | APIs existentes de finanças e fundação de pagamentos | Não usados para alterar estado nesta fase |
| Eventos incrementais | `hq.realtime_events`, via `/api/realtime` | Feed incremental protegido por sessão e plataforma |

## Regra de consolidação

Carteiras de utilizadores não são somadas novamente a um saldo PaySuite. O total de custódia só pode ser calculado quando a titularidade, disponibilidade e fonte de cada componente forem conhecidas. Carteiras pessoais HQ permanecem separadas.

## PaySuite

O código contém uma integração autenticada para payout (`POST /payouts`) e webhook de estados. Não foi encontrada uma operação documentada de leitura de saldo, extrato ou histórico de liquidação. Por isso a Central apresenta PaySuite como **Não reconciliado** e não como saldo confirmado. Nenhum endpoint foi inventado ou chamado nesta fase.

## Indicadores ainda não fiáveis

- Saldo confirmado PaySuite.
- Diferença PaySuite versus ledger.
- Custos e resultado operacional quando não houver lançamentos contabilísticos reconciliados.
- Qualquer valor de carteira cuja titularidade ou ligação ao perfil não possa ser verificada.

## Alterações desta fase

- `components/analytics/FinanceReadOnlyDashboard.tsx`: painel financeiro read-only com KPI, estado da fonte e origem dos dados.
- `app/page.tsx`: integração do painel na área de Finanças, preservando os fluxos existentes.
- `app/globals.css`: estilos do painel de fontes financeiras.
- Este documento: mapa de fontes, limites e riscos da reconciliação.

Não foram criadas migrations, não foram alterados webhooks, saldos, comissões, RBAC, RLS ou integrações de escrita.
