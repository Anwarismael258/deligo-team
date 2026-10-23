# Fase 9H — auditoria e correção segura de dependências

Data: 2026-10-23

## Resultado

**PRONTO COM RESTRIÇÕES.** Foi aplicada apenas uma atualização direta de baixo risco: `vite` `8.0.13 → ^8.3.5`. A atualização reduziu o inventário de 33 para 30 vulnerabilidades e passou toda a validação técnica. A vulnerabilidade crítica em Next.js e os grupos ligados a Vinext/Cloudflare continuam pendentes; não foram atualizados automaticamente.

Não houve deploy, ligação a produção, pagamentos, levantamentos, migrations, alteração de saldos, contratos, PaySuite, webhooks, RLS ou RBAC.

## Inventário npm

`npm audit --json` inicial da Fase 9H:

| Severidade | Antes | Depois do Vite |
|---|---:|---:|
| Critical | 1 | 1 |
| High | 25 | 22 |
| Moderate | 6 | 6 |
| Low | 1 | 1 |
| Total | 33 | 30 |

As dependências passaram de 747 para 728 entradas reportadas pelo npm após a atualização do Vite. O exit code do audit continua 1 porque permanecem vulnerabilidades.

## Vulnerabilidade crítica

O pacote direto `next@16.2.6` está dentro da faixa afetada `9.3.4-canary.0 - 16.4.0`. O relatório inclui advisories de bypass de middleware/proxy, SSRF/DoS em Server Actions e múltiplos advisories de execução remota de código na otimização de imagens e `use cache`, incluindo:

- `GHSA-p293-qw3h-jr36` — RCE não autenticado em servidores Windows.
- `GHSA-2xp9-vwfh-vxw4` — RCE na Image Optimization API com AVIF.
- `GHSA-vcvr-r3jv-pc5j` — RCE em `next/og`.
- `GHSA-2464-fhr4-w9xw` — RCE na Image Optimization API com SVG.
- `GHSA-673q-mjm6-r5xr` — RCE em funções `use cache` que devolvem typed arrays.

O npm indica `next@16.4.2`. É uma atualização de framework com impacto potencial em App Router, Vinext e rotas dinâmicas; por isso não foi aplicada nesta fase sem uma janela dedicada de compatibilidade e revisão de segurança.

## Pacotes High após a correção

| Pacote | Tipo | Introdução/cadeia | Problema representativo | Correção indicada | Decisão |
|---|---|---|---|---|---|
| `@cloudflare/vite-plugin@1.37.1` | direto dev | `miniflare`, `wrangler`, `ws` | runtime/tooling Cloudflare | `1.65.0` | pendente; plugin altera o servidor worker |
| `@next/eslint-plugin-next` | transitivo dev | `eslint-config-next` | regras/stack de lint | `eslint-config-next@14.2.35` | não aplicar; proposta incompatível |
| `brace-expansion` | transitivo dev | glob/lint | DoS por expansão/recursão | atualização transitiva | pendente; validar cadeia |
| `braces` | transitivo dev | glob/lint | stack exhaustion DoS | `eslint-config-next@14.2.35` | não aplicar; major |
| `browserslist` | transitivo dev | tooling de browsers | crescimento de memória/crash | atualização transitiva | pendente |
| `eslint-config-next@16.2.6` | direto dev | ESLint Next | cadeia `fast-glob`/`micromatch` | npm sugere `14.2.35` | não aplicar; downgrade incompatível |
| `fast-glob` | transitivo dev | ESLint Next | glob e DoS | `eslint-config-next@14.2.35` | pendente |
| `fast-uri` | transitivo | cliente URI | host confusion/SSRF | atualização transitiva | pendente |
| `image-size` | transitivo | Vinext | loops em parsers JXL/HEIF/ICNS | `vinext@1.3.0` | não aplicar; major |
| `js-yaml` | transitivo dev | tooling | CPU DoS em merge keys | atualização transitiva | pendente |
| `micromatch` | transitivo dev | ESLint Next | padrões/glob | `eslint-config-next@14.2.35` | pendente |
| `miniflare` | transitivo dev | Cloudflare plugin | runtime worker | `@cloudflare/vite-plugin@1.65.0` | pendente |
| `nodemailer@7.0.6` | direto runtime | API SMTP | domain confusion/SMTP injection/CRLF | `10.2.1` | não aplicar; major e fluxo SMTP sensível |
| `postcss` | transitivo build | Next/Vite | XSS/leitura de source map | `next@16.4.2` | aguarda upgrade Next |
| `react-server-dom-webpack@19.2.6` | direto runtime/build | RSC | DoS em Server Functions | `19.3.1` | pendente; validar compatibilidade RSC |
| `sharp` | transitivo | Cloudflare plugin | vulnerabilidades em libvips/libheif/librsvg | plugin `1.65.0` | pendente; processamento de imagens |
| `undici` | transitivo | Cloudflare plugin | TLS/cookies/WebSocket/SSRF | plugin `1.65.0` | pendente; rede/runtime |
| `vinext@0.0.50` | direto runtime/build | `image-size`, plugins Vite | cadeia de build/runtime | `1.3.0` | não aplicar; major do framework |
| `vite-plugin-commonjs` | transitivo build | Vinext | cadeia dinâmica CommonJS | Vinext `1.3.0` | aguarda Vinext |
| `vite-plugin-dynamic-import` | transitivo build | Vinext | cadeia de imports | Vinext `1.3.0` | aguarda Vinext |
| `wrangler@4.92.0` | direto dev | Cloudflare plugin | cadeia esbuild/miniflare | plugin `1.65.0` | pendente; tooling Cloudflare |
| `ws` | transitivo dev | Cloudflare plugin | memory disclosure/DoS | plugin `1.65.0` | pendente |

Os advisories restantes representam sobretudo DoS em tooling/build, globbing, parsers de imagem, transporte HTTP/WebSocket e SMTP. Não foram tratados como irrelevantes: cada grupo ficou associado à sua cadeia e ao risco operacional acima.

## Análise de exposição

- `next`, `react-server-dom-webpack`, `nodemailer`, `postcss`, `sharp` e `undici` podem alcançar caminhos de runtime/build e não devem ser ignorados antes de uma revisão de versões.
- `@cloudflare/vite-plugin`, `wrangler`, `miniflare`, Vite plugins, ESLint, `browserslist`, globbing e `js-yaml` são predominantemente desenvolvimento/build, mas afetam o processo de geração e o servidor local.
- O risco crítico do Next é bloqueador para produção até atualização compatível, revisão das rotas afetadas e validação autenticada/staging.
- Nenhuma conclusão de “não alcançável” foi usada para esconder uma vulnerabilidade.

## Validação após a atualização

- `npm run typecheck`: **PASS**.
- `npm run build`: **PASS** com Vite 8.3.5.
- `node --test tests/*.test.mjs`: **119/119 PASS**.
- `npx playwright test`: **6/6 PASS** em Chromium desktop e mobile.
- Lint direcionado de `playwright.config.ts` e `tests/e2e/local-smoke.spec.ts`: não terminou após 120 segundos; foi interrompido e não classificado como PASS.
- `npm audit --json`: 30 vulnerabilidades restantes.

O primeiro build após a atualização encontrou apenas conflito de artefacto gerado `dist\\.openai\\drizzle` (`EEXIST`). O `dist` foi movido para uma pasta temporária recuperável e o build seguinte passou; nenhum ficheiro de código foi apagado.

## Ficheiros e commit

Alterações desta fase:

- `package.json`: apenas a versão do Vite foi atualizada no commit; alterações anteriores aos scripts de lint ficaram fora do commit.
- `npm-shrinkwrap.json`: lockfile correspondente ao Vite atualizado.
- `docs/phase9h-dependency-audit-report.md`.

Commit: registado no histórico Git após a validação desta fase.

## Próximo plano seguro

1. Criar branch isolada para atualizar `next` para a versão corrigida indicada pelo audit.
2. Auditar compatibilidade com Vinext, React Server Components, middleware, autenticação e rotas API.
3. Atualizar `react-server-dom-webpack` em conjunto, se a matriz de compatibilidade confirmar.
4. Tratar o stack Cloudflare/Vinext separadamente, sem misturar com a atualização Next.
5. Atualizar Nodemailer apenas após teste dedicado de SMTP/headers e sem credenciais reais.
6. Repetir build, 119 testes, E2E, lint e audit em cada grupo.

Classificação final: **NÃO PRONTO PARA PRODUÇÃO** enquanto a vulnerabilidade crítica do Next e os riscos altos de runtime não tiverem plano executado e validação autenticada em staging.
