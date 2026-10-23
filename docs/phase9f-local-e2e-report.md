# Fase 9F — preparação técnica de E2E local

Data: 2026-10-23

## Resultado

**PRONTO COM RESTRIÇÕES para E2E local.** A configuração e os testes sintéticos foram criados, mas a execução depende dos browsers do Playwright, que não foram descarregados nesta fase. Não houve ligação a produção, deploy ou criação de serviços externos.

## Ambiente

- Node: `v25.2.1`
- npm: `11.6.2`
- Vinext: `0.0.50`
- ESLint: `9.39.4`
- `eslint-config-next`: `16.2.6`
- `@typescript-eslint/parser`: `8.59.3`
- `@playwright/test`: `^1.64.1`, instalado com `--ignore-scripts`
- Browsers Playwright: **não instalados**

O npm reportou 33 vulnerabilidades no conjunto de dependências existente (1 low, 6 moderate, 25 high, 1 critical). Não foi executado `npm audit fix`.

## Playwright criado

- `playwright.config.ts`: servidor Vinext local em `localhost:4173`, dois projetos (desktop e mobile), `serviceWorkers` bloqueados e sem segredos de produção.
- `tests/e2e/local-smoke.spec.ts`: três testes sintéticos para login corporativo, overflow mobile e bloqueio de chamadas externas.

Os testes usam apenas a aplicação local e mocks HTTP. Não constituem prova de integração Supabase, segurança de produção ou funcionamento real de APIs.

## Execução E2E

O Playwright iniciou o servidor local, mas os 6 testes falharam antes de executar porque os browsers não existem:

```text
Executable doesn't exist at ...\\ms-playwright\\chromium_headless_shell-1248\\...
```

Não foi executado `npx playwright install`, conforme a restrição de não descarregar browsers sem informar/autorização adicional.

## Diagnóstico ESLint

- A configuração usa `eslint-config-next/core-web-vitals` e `eslint-config-next/typescript`.
- `.next`, `out`, `build`, `next-env.d.ts` e `dist` são ignorados; não há evidência de ficheiros gerados incluídos.
- `app/api` contém 88 ficheiros TypeScript.
- Lotes de `app/api` sem processos por ficheiro permaneceram sem saída por mais de 90 segundos e foram interrompidos.
- A execução individual automatizada com timeout de 12 segundos também excedeu o limite, devido ao custo de inicialização repetido; não foi considerada aprovação.
- O custo parece concentrar-se no arranque/análise TypeScript do ESLint Next, mas não foi possível obter profiling conclusivo sem alterar a configuração.
- Não foram desativadas regras, reduzido o âmbito do lint ou adicionadas supressões.

Auditoria individual previamente confirmada:

- `app/api/audit/route.ts`: PASS.
- `app/api/reports/export/route.ts`: PASS.
- `app/api/whatsapp/webhook/route.ts`: 7 erros de `no-explicit-any` e 1 aviso de variável não utilizada.

## Segurança

- Supabase: variáveis vazias no processo do servidor local.
- PaySuite: `PAYSUITE_ENABLED=false` e token vazio.
- WhatsApp, SMTP e SMS: variáveis vazias.
- Crons: não ativados pelo teste local.
- Sem migrations, pagamentos, webhooks, alterações de saldo ou deploy.

## Validação existente

- TypeScript: **PASS**.
- Build: **PASS**.
- Suíte Node: **119/119 PASS** antes da adição apenas documental dos testes E2E.
- ESLint dos ficheiros E2E: não concluiu em 90 segundos no mesmo ambiente; não foi classificado como PASS.
- E2E Playwright: **6 falhas de ambiente**, nenhuma execução funcional, por falta de browsers.

## Ficheiros desta fase

- `playwright.config.ts`
- `tests/e2e/local-smoke.spec.ts`
- `docs/phase9f-local-e2e-report.md`
- Dependência de desenvolvimento `@playwright/test` e respetivo shrinkwrap.

As alterações não relacionadas existentes no workspace foram preservadas e não foram incluídas.

## Próximo passo bloqueado

Para executar os testes locais, é necessária autorização explícita para descarregar o browser Playwright (`npx playwright install chromium`). Até lá, a configuração está preparada, mas E2E permanece não executado.
