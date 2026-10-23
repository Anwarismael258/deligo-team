# Fase 9E — preparação de staging e testes E2E

Data: 2026-10-23
Referência: `18ec4ea`

## Classificação

**NÃO PRONTO para validação E2E externa.** A infraestrutura de staging não está demonstrada no checkout e Playwright não está instalado. Não foram criados recursos, não houve deploy e não foram simulados resultados E2E.

## Infraestrutura auditada

- Repositório remoto: GitHub `Anwarismael258/deligo-team`.
- Não existe metadata local `.vercel`; o projeto Vercel, branch de produção e preview não podem ser confirmados apenas pelo checkout.
- `vercel.json` contém apenas os crons `/api/cron/inbox-email` e `/api/cron/microcredit`.
- `next.config.ts` não define domínio ou target de staging.
- `supabase/config.toml` configura apenas a função `paysuite-webhook` com `verify_jwt = false`; não prova isolamento de projeto.
- `.env.example` contém chaves de configuração, mas sem valores secretos. Há `DELIGO_STAGING_SUPABASE_URL`, porém a URL não prova que o projeto seja isolado de produção.
- `PAYSUITE_ENABLED=false` está previsto no exemplo; PaySuite, SMTP, WhatsApp, SMS e crons devem permanecer desativados/sandbox em staging.
- Não foram lidos valores de `.env`, Vercel ou Supabase e nenhum segredo foi exposto.

Documentação existente menciona um staging partilhado em alguns relatórios anteriores, mas não há credenciais nem evidência live disponível nesta execução; portanto não foi tratado como staging isolado confirmado.

## Preparação de staging proposta

Não criar sem autorização explícita. O plano executável é:

1. Projeto Vercel separado, domínio privado/não indexável e branch de staging dedicada.
2. Projeto Supabase separado, com dados sintéticos, Auth de teste e sem service keys de produção.
3. Contas sintéticas para `SUPER_ADMIN`, `FINANCE`, `SUPERVISOR` e trabalhador limitado.
4. Variáveis de staging próprias; PaySuite desativado ou sandbox; WhatsApp, SMTP, SMS e crons desligados.
5. Logs, alertas e retenção separados; proteção por autenticação e `noindex`.
6. Smoke test de isolamento antes de qualquer teste funcional.

Não é seguro usar o projeto Supabase apontado no `.env.example` como staging sem confirmação independente de titularidade e isolamento.

## E2E

Playwright não está instalado e não existe `playwright.config.ts`; por isso nenhum teste E2E foi criado ou executado. A matriz preparada é:

| Perfil | Cenários |
|---|---|
| SUPER_ADMIN | Login/logout, sidebar, dashboards, filtros 7/30/90, APIs autorizadas, realtime e responsividade |
| FINANCE | Finanças, métricas, filtros, APIs reservadas e bloqueio de operações externas reais |
| SUPERVISOR | Equipa/operações autorizadas, isolamento por plataforma e bloqueio de payroll |
| Trabalhador limitado | Áreas atribuídas, estados vazio/erro e respostas 401/403 em endpoints fora do âmbito |

Cada perfil deve ser testado em desktop, tablet e telemóvel, incluindo loading, vazio, erro, gráficos, filtros, sidebar, realtime e operações existentes sem movimentar dinheiro.

## ESLint de `app/api`

Foram tentados três lotes únicos, sem processo por ficheiro, cobrindo todas as rotas de `app/api`. Os lotes permaneceram sem saída por mais de 90 segundos e foram interrompidos. Isto é diagnosticado como timeout do ESLint/configuração, não como aprovação.

Auditorias individuais já confirmadas:

- `app/api/audit/route.ts`: PASS.
- `app/api/reports/export/route.ts`: PASS.
- `app/api/whatsapp/webhook/route.ts`: 7 erros `@typescript-eslint/no-explicit-any` e 1 aviso de variável não utilizada.

Não foram modificadas as rotas restantes. O bloqueio de desempenho impede declarar inventário completo sem uma execução que termine.

## Preservação e resultado

- Nenhum deploy.
- Nenhum recurso externo criado.
- Nenhum pagamento, payout, alteração financeira, migration, RLS ou RBAC modificado.
- Alterações não relacionadas do workspace preservadas.
- Playwright/E2E: **não executável neste ambiente**.
- Inventário API: **incompleto por timeout**.

Ficheiro criado nesta fase: `docs/phase9e-staging-e2e-report.md`.

Classificação final: **NÃO PRONTO para validação E2E**, até existir staging isolado autorizado, Playwright disponível e inventário API concluído.
