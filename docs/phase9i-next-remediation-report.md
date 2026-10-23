# Fase 9I — Remediação de segurança Next.js / Vinext

Data: 2026-10-23
Branch: `security/next-remediation`
Base validada: `c7df2ef` (Fase 9H)

## Diagnóstico

`next` não é apenas tooling. A aplicação usa em runtime:

- `next/server` em múltiplas rotas API (`NextRequest` e `NextResponse`);
- `next/headers` e `next/navigation` no fluxo de autenticação e contexto HQ;
- `next/image` em componentes operacionais e de microcrédito;
- `eslint-config-next` no lint;
- os adaptadores RSC e de otimização de imagem do Vinext.

Não foram encontrados `middleware.*` ou `next.config.*` próprios no código da aplicação durante esta auditoria. O build, contudo, confirma as rotas API e os shims Vinext de RSC e imagem.

## Estratégias avaliadas

### A — Atualização compatível

Escolhida. O `next` foi atualizado de `16.2.6` para `16.4.2`, mantendo React `19.2.6`, Vinext `0.0.50` e as APIs existentes. A atualização é direta, sem alteração de regras de negócio, autenticação, RBAC/RLS, pagamentos ou webhooks.

### B — Remoção controlada

Rejeitada nesta fase. A remoção não é segura porque os imports `next/server`, `next/headers`, `next/navigation` e `next/image` existem em código executado, não apenas em tipos. Removê-los exigiria substituir APIs de runtime do Vinext e revalidar os fluxos de autenticação, documentos, imagens e rotas API.

## Resultado de segurança

Antes da alteração, a auditoria registava 30 vulnerabilidades: 1 crítica, 22 altas, 6 moderadas e 1 baixa. Depois da atualização do Next.js, a auditoria registou 28 vulnerabilidades: 0 críticas, 21 altas, 6 moderadas e 1 baixa.

O resultado não é uma aprovação de produção. Permanecem riscos independentes, incluindo `@cloudflare/vite-plugin`/Wrangler, `eslint-config-next`, Nodemailer, `react-server-dom-webpack` e Vinext. As atualizações major desses pacotes não foram executadas nesta fase.

Os advisories oficiais do Next.js continuam a ser a referência para manter o framework em versão corrigida: [advisórios oficiais](https://github.com/vercel/next.js/security/advisories) e [política oficial de suporte](https://nextjs.org/support-policy).

## Validação executada

- TypeScript: **PASS** — `npm run typecheck`.
- Build Vinext: **PASS** — `npm run build`; rotas API, RSC e shims de imagem foram gerados.
- Testes Node: **PASS** — 119/119 com `node --test tests/*.test.mjs`.
- Playwright: **PASS** — 6/6 testes locais, nos projetos desktop e mobile.
- Lint direcionado: **BLOQUEADO POR TIMEOUT** — o processo não apresentou resultado dentro de aproximadamente dois minutos e foi interrompido; não foi tratado como aprovação.
- `npm audit --json`: **PASS na execução, com vulnerabilidades residuais** — 28 vulnerabilidades, 0 críticas.
- Inspeção de dependências: `next@16.4.2`, `react-server-dom-webpack@19.2.6`, `vinext@0.0.50`.
- Inspeção do bundle: o output contém os shims RSC/Vinext e `next/image` compatibilizado pelo Vinext; não há evidência de remoção segura de Next.js.

## Segurança operacional

Não houve deploy, migration, alteração de produção, chamada PaySuite, alteração de webhook, mudança de RLS/RBAC ou alteração de saldos/contratos. As alterações não relacionadas já existentes no workspace foram preservadas e não foram incluídas nesta mudança.

## Estado e recomendação

Estado: **PRONTO COM RESTRIÇÕES para revisão da branch**, **NÃO PRONTO PARA PRODUÇÃO**.

Recomendação: revisar o diff desta branch e, antes de qualquer integração em `main`, tratar os 21 riscos altos residuais e obter uma execução de lint concluída. A branch não foi integrada na principal.
