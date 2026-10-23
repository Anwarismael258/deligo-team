# Fase 9D — correções seguras e preparação de staging

Data: 2026-10-23
Referência: `723df02`

## Resultado

**PRONTO COM RESTRIÇÕES.** Foram corrigidos quatro problemas de baixo risco em módulos institucionais/operacionais não financeiros. TypeScript, build, lint direcionado e os 119 testes continuam a passar. Não houve deploy nem alterações em produção.

## Correções realizadas

- `components/InstitutionalJobsManager.tsx`: carregamento inicial estabilizado com `useCallback` e timer cancelável.
- `components/InstitutionalNewsManager.tsx`: dependências do carregamento corrigidas, timer cancelável e imagem migrada para `next/image` sem otimização, preservando URLs públicas/assinadas.
- `components/OperationalModule.tsx`: galeria KYC migrada para `next/image` sem alterar links ou permissões.

Não foram alterados Finanças, WhatsApp, autenticação, aprovações, PaySuite, webhooks, RLS ou RBAC.

## Inventário de lint

Resultados por grupo:

| Grupo | Resultado |
|---|---|
| `app/components` | 20 problemas antes das correções: 17 erros e 3 avisos. Permanecem em componentes de finanças, suporte, inbox, mapa, perfil, notificações, tecnologia e workflow. |
| `components` | 5 problemas antes das correções; os 2 erros e 3 avisos dos módulos Jobs/News/Operational foram corrigidos. Lint direcionado posterior: **PASS**. |
| `lib` | **PASS**, 0 problemas. |
| `tests` | **PASS**, 0 problemas. |
| `app/api` | O grupo completo excede o tempo normal. Auditoria individual confirmada: `app/api/audit/route.ts` PASS, `app/api/reports/export/route.ts` PASS, `app/api/whatsapp/webhook/route.ts` com 7 erros e 1 aviso. |

Foi tentada uma execução individual automatizada de 88 ficheiros de `app/api` com limite de 12 segundos; todos os processos ultrapassaram esse limite devido ao custo de inicialização do ESLint neste ambiente, portanto esses timeouts não foram classificados como aprovação. A auditoria individual dos três ficheiros acima permanece a evidência válida.

Principais riscos restantes:

- `react-hooks/set-state-in-effect`: componentes que carregam dados no efeito; risco médio, requer refatoração controlada.
- `@typescript-eslint/no-explicit-any`: Inbox/Workflow/Technology e WhatsApp; risco médio/alto.
- `react-hooks/purity`: componentes operacionais; risco funcional a analisar.
- `@next/next/no-img-element`: imagens privadas/KYC e outros módulos; risco de URL assinada se migrado sem teste.

## Validação executada

- `npm run typecheck`: **PASS**.
- `npm run build`: **PASS**.
- `node --test tests/*.test.mjs`: **119/119 PASS**.
- Lint direcionado dos três ficheiros corrigidos: **PASS**.
- `lib` e `tests`: **PASS**.

## Staging

Não foram criados recursos externos. O checkout possui apenas `.env.example`, com URLs de plataformas e uma variável `DELIGO_STAGING_SUPABASE_URL`; isso não prova isolamento de produção. `vercel.json` contém apenas cron paths e não define projeto ou domínio de staging.

Plano operacional antes da validação E2E:

1. Vercel separado, URL privada/não indexável e projeto independente.
2. Supabase separado, dados sintéticos e sem service keys de produção.
3. Contas de teste SUPER_ADMIN, FINANCE, SUPERVISOR e trabalhador limitado.
4. PaySuite, WhatsApp, SMTP e crons em sandbox/desativados.
5. Logs separados, proteção de acesso e verificação de isolamento.

Nenhum recurso foi criado e nenhum deploy foi feito.

## Matriz E2E preparada

Para cada perfil: login, sidebar, dashboards, filtros 7/30/90 dias, gráficos, estados loading/vazio/erro, realtime, responsividade desktop/tablet/telemóvel, acesso direto a APIs e regressão dos fluxos operacionais.

- SUPER_ADMIN: áreas autorizadas e visão consolidada.
- FINANCE: finanças e decisões permitidas sem payout real.
- SUPERVISOR: equipa/operações autorizadas, sem payroll reservado.
- Trabalhador limitado: apenas o âmbito atribuído; APIs fora do âmbito devem responder 401/403.

## Commit e prontidão

O commit da Fase 9C foi confirmado como `723df02`, contendo exclusivamente os três ficheiros autorizados. As correções desta Fase 9D foram commitadas em `18ec4ea`, limitado aos três componentes corrigidos e a este relatório. Alterações não relacionadas permanecem fora do staging.

Classificação: **PRONTO COM RESTRIÇÕES** até concluir a auditoria completa de `app/api` e executar a matriz E2E em staging isolado.
