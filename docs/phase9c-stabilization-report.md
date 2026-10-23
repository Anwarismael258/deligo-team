# Fase 9C — estabilização por módulos e preparação de staging

Data: 2026-10-23
Referência: relatório da Fase 9B

## Classificação

**PRONTO COM RESTRIÇÕES.** A aplicação compila, os 119 testes passam e o lint do grupo central configurado passa. A classificação não pode subir para PRONTO porque o lint abrangente não concluiu e não existe staging autenticado isolado para validação E2E.

## Inventário do lint

O `package.json` atualmente define:

- `npm run lint`: `lint:central`, limitado a `app/api/sarca`, `components/SarcaOperationsWorkspace.tsx` e `lib/platform-backends.ts`, com `--max-warnings=0`.
- `npm run lint:all`: `eslint app components lib tests`.

Resultado observado:

- `npm run lint`: **PASS**.
- `npm run lint:all`: não concluiu em duas janelas superiores a 60 segundos e foi interrompido sem alterações.
- O inventário anterior da Fase 9B registava 39 erros e 88 avisos. Os principais grupos eram APIs de auditoria/exportação/WhatsApp, hooks em componentes operacionais e avisos de imagens. O inventário completo continua pendente de execução terminada por ficheiro.

Não se alterou o `package.json`, pois a diferença existente já fazia parte do workspace e não foi introduzida nesta fase.

## Correções controladas

Foram corrigidos apenas dois problemas mecânicos de baixo risco:

1. `app/api/audit/route.ts`: renomeado o filtro local `module` para `moduleFilter`, sem alterar o parâmetro HTTP nem a consulta.
2. `app/api/reports/export/route.ts`: separado o `let out` da constante `offsets`, preservando a geração do PDF.

Não foram alterados fluxos financeiros, autenticação, aprovações, WhatsApp, PaySuite, webhooks, RLS, RBAC, saldos, contratos ou migrations.

## Validação técnica

- TypeScript (`npm run typecheck`): **PASS**.
- Build (`npm run build`): **PASS** após limpar apenas o artefacto gerado `dist`; o primeiro retry encontrou `EEXIST` em `dist/.openai/drizzle`.
- Testes (`node --test tests/*.test.mjs`): **PASS — 119/119**.
- Lint central (`npm run lint`): **PASS**.
- Lint abrangente: **não concluído**, conforme inventário acima.

## Proposta de staging seguro

Não foi criado nenhum recurso externo. Antes de configurar staging, a proposta é:

| Área | Proposta |
|---|---|
| URL | Projeto/Deployment Vercel separado, sem apontar o domínio de produção |
| Dados | Projeto Supabase separado ou branch/database isolado, com dados sintéticos |
| Contas | Utilizadores de teste separados para SUPER_ADMIN, FINANCE, SUPERVISOR e trabalhador limitado |
| Segredos | Variáveis de staging distintas; nenhum segredo de produção reutilizado |
| PaySuite/WhatsApp/email | Sandbox ou integrações desativadas; nenhum payout, cobrança ou mensagem real |
| Acesso | Proteção por autenticação e bloqueio de indexação pública |
| Observabilidade | Logs separados, retenção limitada e alertas sem dados pessoais desnecessários |
| Migrações | Apenas migrations reversíveis e aprovadas; nenhuma migration foi executada nesta fase |

O staging só deve ser criado após aprovação explícita e confirmação de que a base financeira de produção não será usada.

## Matriz E2E preparada

| Perfil | Navegação/dashboard | APIs | Isolamento | Operações existentes |
|---|---|---|---|---|
| SUPER_ADMIN | todas as áreas autorizadas | leitura e ações permitidas | todas as plataformas atribuídas | validar sem executar pagamentos reais |
| FINANCE | finanças e módulos atribuídos | leitura financeira e decisões autorizadas | sem dados fora do âmbito | confirmar dupla aprovação em sandbox |
| SUPERVISOR | equipa/operações atribuídas | apenas endpoints permitidos | validar separação por plataforma | sem alterar dinheiro |
| Trabalhador limitado | apenas módulos autorizados | tentativas diretas devem dar 401/403 | sem dados de outros âmbitos | ações não autorizadas bloqueadas |

Para cada perfil, o staging deverá cobrir desktop, tablet e telemóvel, filtros 7/30/90 dias, estados vazio/loading/erro, sidebar, tabelas, gráficos, realtime e acesso direto aos endpoints.

## Ficheiros alterados nesta fase

- `app/api/audit/route.ts`
- `app/api/reports/export/route.ts`
- `docs/phase9c-stabilization-report.md`

Alterações não relacionadas existentes no workspace foram preservadas e não foram incluídas.

## Commits

Esta fase ainda não foi commitada. O commit deve incluir somente os três ficheiros acima, após revisão final. Não foi feito deploy.

## Pendências críticas

1. Completar o inventário do `lint:all` por ficheiro, sem correções automáticas em massa.
2. Disponibilizar staging isolado e executar a matriz E2E.
3. Repetir auditoria de segurança e desempenho no staging.

## Fase 9C.1 — inventário executado

Os grupos foram executados separadamente em 2026-10-23:

| Grupo | Resultado | Evidência |
|---|---:|---|
| `app/api` | **Timeout** | Mais de 60 segundos sem saída; interrompido. Ficheiros individuais auditados: `audit/route.ts` PASS, `reports/export/route.ts` PASS, `whatsapp/webhook/route.ts` 7 erros + 1 aviso. |
| `app/components` | **17 erros + 3 avisos** | 20 problemas. Principais regras: `react-hooks/set-state-in-effect`, `@typescript-eslint/no-explicit-any`, `react-hooks/exhaustive-deps`, `react-hooks/purity`. |
| `components` | **2 erros + 3 avisos** | 5 problemas: efeitos de carregamento em Vagas/Notícias e avisos de imagem/dependência. |
| `lib` | **PASS** | 0 problemas. |
| `tests` | **PASS** | 0 problemas. |

O erro do formatter `compact` não foi contado como lint: o formatter não está instalado nesta versão do ESLint. Os grupos válidos foram executados com o formatter padrão.

### Distribuição conhecida por regra

- `react-hooks/set-state-in-effect`: maioria dos erros em componentes que carregam dados no `useEffect`; requer refatoração controlada do ciclo de carregamento.
- `@typescript-eslint/no-explicit-any`: concentrado em Inbox/Workflow/Technology e no webhook WhatsApp; requer tipos de payload reais.
- `react-hooks/exhaustive-deps`: dependências incompletas em componentes existentes.
- `react-hooks/purity`: uso de APIs potencialmente impuras durante renderização; requer análise funcional antes de tocar.
- `@next/next/no-img-element`: avisos em imagens de KYC/notícias; a troca pode afetar URLs privadas/assinadas.

Não foram feitas correções automáticas nesses grupos. Os erros de `app/components` incluem Finanças, Perfil, Notificações, Inbox e mapa operacional; por isso são classificados como risco médio/alto. O webhook WhatsApp é risco alto. `lib` e `tests` estão limpos.

## Diagnóstico do desempenho do lint

- `npm run lint` passa, mas o script está configurado no workspace para chamar apenas `lint:central` e analisar o grupo SARCA.
- `npm run lint:all` inclui `app`, `components`, `lib` e `tests`; não é equivalente ao `npm run lint`.
- `app/components` concluiu em cerca de 22 segundos.
- `components` concluiu em cerca de 19 segundos.
- `lib` concluiu em cerca de 10 segundos.
- `tests` concluiu em cerca de 10 segundos.
- `app/api` excedeu 60 segundos sem saída. Não há evidência de que ficheiros gerados sejam incluídos: a configuração ignora `.next`, `out`, `build` e o comando ignora `dist`.

Não foram alteradas regras ESLint, scripts ou supressões. O próximo diagnóstico seguro é executar `app/api` por ficheiro ou em lotes pequenos, com cache e timeout controlado.

## Preparação de staging auditada

Existe apenas `.env.example`; não há credenciais preenchidas nem configuração Vercel de staging no checkout. O ficheiro contém uma variável chamada `DELIGO_STAGING_SUPABASE_URL`, mas ela aponta para um projeto já conhecido e não prova isolamento de produção. Também existe `vercel.json` apenas com dois cron paths; não há projeto/URL de staging configurado localmente.

Plano executável, sem criação nesta fase:

1. Criar projeto Vercel separado e URL não indexável.
2. Criar projeto Supabase separado, com schema/dados sintéticos e sem credenciais de produção.
3. Criar quatro contas de teste: `SUPER_ADMIN`, `FINANCE`, `SUPERVISOR` e trabalhador limitado.
4. Definir variáveis próprias de staging; manter `PAYSUITE_ENABLED=false`, WhatsApp/email em sandbox e cron protegido por segredo próprio.
5. Validar logs, retenção, bloqueio de indexação e isolamento antes de qualquer smoke test.

Nenhum recurso externo foi criado e nenhum deploy foi executado.

## Matriz E2E preparada

Para cada perfil, a validação deverá cobrir: login/sessão, sidebar, áreas autorizadas, endpoints diretos 401/403, filtros 7/30/90 dias, KPIs/gráficos, loading/erro/vazio, realtime, desktop/tablet/telemóvel e operações existentes sem dinheiro real.

- **SUPER_ADMIN:** todas as áreas autorizadas; verificar separação de receita, carteiras e fundos de terceiros.
- **FINANCE:** finanças e áreas atribuídas; confirmar que decisões reservadas não executam PaySuite em staging.
- **SUPERVISOR:** equipa/operações/conteúdos autorizados; negar payroll e áreas fora do âmbito.
- **Trabalhador limitado:** apenas áreas atribuídas; confirmar que acesso direto a APIs e dados de outras plataformas é bloqueado.

## Estado desta subfase

O commit `e4ba487` contém exclusivamente `app/api/audit/route.ts`, `app/api/reports/export/route.ts` e este relatório. As alterações não relacionadas permanecem fora do commit. A validação continua **PRONTO COM RESTRIÇÕES** até concluir o inventário de `app/api` e executar a matriz em staging isolado.
