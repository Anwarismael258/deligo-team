# Fase 9G — E2E local e auditoria de dependências

Data: 2026-10-23

## Resultado

**PRONTO COM RESTRIÇÕES para validação local.** O Chromium autorizado foi instalado e os seis cenários Playwright passaram em desktop e mobile. Isto valida apenas o harness local com dados sintéticos; não é prova de integração com Supabase, PaySuite, WhatsApp, SMS, SMTP ou produção.

## Instalação e isolamento

- Executado `npx playwright install chromium` com sucesso.
- Nenhum outro browser foi instalado.
- O harness usa `vinext start` sobre o build local em `localhost:4173`.
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, tokens PaySuite/WhatsApp e senha SMTP são esvaziados no processo do servidor.
- `PAYSUITE_ENABLED=false`.
- Não foram criados serviços externos, migrations, pagamentos, levantamentos, webhooks ou deploys.

O servidor foi alterado de `vinext dev` para `vinext start` no harness. O modo dev falhava ao arrancar porque o plugin Cloudflare tentava obter tipos do worker e recebia `ECONNRESET`; o servidor de produção local usa o build já gerado e não necessita dessa chamada externa.

## Playwright

Configuração: `playwright.config.ts`.

Testes: `tests/e2e/local-smoke.spec.ts`.

Resultado final:

```text
6 passed (desktop + mobile)
```

Os seis testes cobrem renderização do login corporativo, acessibilidade dos controlos, overflow horizontal em mobile e bloqueio de chamadas API externas através de mocks locais. Uma falha inicial de seletor foi corrigida no teste; não houve correção da aplicação.

## Validação técnica

- `npm run typecheck`: **PASS**.
- `npm run build`: **PASS**.
- `node --test tests/*.test.mjs`: **119/119 PASS**.
- `npx playwright test`: **6/6 PASS**.

## Auditoria `npm audit --json`

Resultado: exit code 1 por vulnerabilidades encontradas.

| Severidade | Quantidade |
|---|---:|
| Critical | 1 |
| High | 25 |
| Moderate | 6 |
| Low | 1 |
| Total | 33 |

### Crítica

| Pacote | Versão instalada | Tipo | Correção indicada | Risco |
|---|---|---|---|---|
| `next` | 16.2.6 | direto | 16.4.2 | Atualização de framework; exige build, rotas e regressão completos |

### Altas

| Pacote | Tipo | Correção indicada | Risco principal |
|---|---|---|---|
| `@cloudflare/vite-plugin` | direto | 1.65.0 | Alteração do plugin de runtime/worker |
| `@next/eslint-plugin-next` | transitivo | via `eslint-config-next` 14.2.35 | Mudança incompatível no stack de lint |
| `brace-expansion` | transitivo | disponível | Atualização transitiva; validar lockfile |
| `braces` | transitivo | via `eslint-config-next` 14.2.35 | Cadeia de lint/glob; proposta major |
| `browserslist` | transitivo | disponível | Atualização de tooling de browsers |
| `eslint-config-next` | direto | 14.2.35 | Proposta major incompatível com Next atual |
| `fast-glob` | transitivo | via `eslint-config-next` 14.2.35 | Cadeia de lint/glob |
| `fast-uri` | transitivo | disponível | Atualização transitiva |
| `image-size` | transitivo | via `vinext` 1.3.0 | Atualização major de Vinext |
| `js-yaml` | transitivo | disponível | Atualização transitiva |
| `micromatch` | transitivo | via `eslint-config-next` 14.2.35 | Cadeia de lint/glob |
| `miniflare` | transitivo | via `@cloudflare/vite-plugin` 1.65.0 | Alteração do runtime Cloudflare |
| `nanoid` | transitivo | disponível | Atualização transitiva |
| `nodemailer` | direto | 10.2.1 | Proposta major; validar email e transporte SMTP |
| `postcss` | transitivo | via `next` 16.4.2 | Alteração do pipeline CSS |
| `react-server-dom-webpack` | direto | 19.3.1 | Alteração do protocolo RSC; risco alto de regressão |
| `sharp` | transitivo | via `@cloudflare/vite-plugin` 1.65.0 | Alteração de processamento de imagens |
| `source-map-js` | transitivo | disponível | Atualização transitiva |
| `undici` | transitivo | via `@cloudflare/vite-plugin` 1.65.0 | Alteração de fetch/runtime |
| `vinext` | direto | 1.3.0 | Atualização major do framework usado pela Central |
| `vite` | direto | 8.3.5 | Alteração do bundler; requer build/regressão |
| `vite-plugin-commonjs` | transitivo | via `vinext` 1.3.0 | Atualização major de Vinext |
| `vite-plugin-dynamic-import` | transitivo | via `vinext` 1.3.0 | Atualização major de Vinext |
| `wrangler` | direto | via `@cloudflare/vite-plugin` 1.65.0 | Alteração de tooling Cloudflare |
| `ws` | transitivo | via `@cloudflare/vite-plugin` 1.65.0 | Alteração de transporte WebSocket |

Versões diretas relevantes verificadas:

```text
next 16.2.6
@cloudflare/vite-plugin 1.37.1
eslint-config-next 16.2.6
nodemailer 7.0.6
react-server-dom-webpack 19.2.6
vinext 0.0.50
vite 8.0.13
wrangler 4.92.0
```

Não foi executado `npm audit fix` e nenhuma dependência crítica foi atualizada. As correções sugeridas misturam atualizações diretas, transitivas e majors; devem ser tratadas numa tarefa própria, com análise de compatibilidade e regressão.

## Ficheiros alterados nesta fase

- `playwright.config.ts`
- `tests/e2e/local-smoke.spec.ts`
- `docs/phase9g-e2e-security-report.md`

O relatório da Fase 9F e as alterações não relacionadas existentes no workspace foram preservados. Artefactos temporários de `test-results` não foram incluídos no commit.

## Bloqueios restantes

1. As vulnerabilidades críticas/altas continuam presentes e exigem plano de atualização separado.
2. Os testes são locais e sintéticos; não validam produção nem integrações externas.
3. O inventário de lint de `app/api` continua com o problema de timeout documentado na Fase 9F.

Classificação atual: **PRONTO COM RESTRIÇÕES**. A Central não deve ser declarada pronta para produção apenas com estes testes.
