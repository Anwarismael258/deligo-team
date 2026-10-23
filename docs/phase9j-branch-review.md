# Fase 9J — Revisão da branch de segurança

Data: 2026-10-23

## Git

- Branch local e remota: `security/next-remediation`
- Commit da atualização: `14a5867881190b42887206d1fb0d42b1a18d8b66`
- Base: `c7df2ef`
- `origin/security/next-remediation`: igual ao commit local
- `main`: não alterada
- Diff da Fase 9I: `package.json`, `npm-shrinkwrap.json` e `docs/phase9i-next-remediation-report.md`
- O workspace possui alterações não relacionadas não commitadas; não fazem parte da branch publicada.
- A inspeção do diff não encontrou valores de segredos; apenas nomes de variáveis de ambiente e referências `process.env`.

## Compatibilidade

O upgrade de `next` 16.2.6 para 16.4.2 manteve o build Vinext, as rotas API, o fluxo de autenticação, RSC, Next Image e as rotas de microcrédito/finanças no output de build. Não foram alterados código de negócio, documentos privados, WhatsApp, PaySuite, webhooks, RLS ou RBAC.

Os testes locais não cobrem autenticação real, Supabase, PaySuite, WhatsApp, SMTP, documentos assinados ou webhooks de produção. Esses fluxos continuam a exigir staging autenticado antes da integração em `main`.

## Riscos residuais

| Dependência | Gravidade | Exposição provável | Correção disponível | Decisão |
|---|---:|---|---|---|
| `react-server-dom-webpack@19.2.6` | Alta | runtime RSC/Vinext; risco de DoS em Server Functions | atualização para 19.3.1 | não atualizar sem validar compatibilidade React/Vinext |
| `nodemailer@7.0.6` | Alta | rotas de email/cron; parsing e conteúdo SMTP | major 10.2.1 | análise separada antes de major |
| `vinext@0.0.50` | Alta | build e shims de runtime/imagem | major 1.3.0 | não atualizar nesta branch |
| `@cloudflare/vite-plugin` / `wrangler` | Alta | tooling de build/deploy e dependências Miniflare/esbuild | 1.65.0 / atualização relacionada | não atualizar sem validar Cloudflare |
| `eslint-config-next@16.2.6` | Alta | desenvolvimento/lint, não runtime do bundle | sugestão npm incompatível com a linha atual | manter até plano de atualização do lint |
| dependências HTTP/imagem transitivas | Alta/moderada | depende do caminho que as carrega | correções variáveis | investigar por pacote, sem `audit fix --force` |

O `npm audit` atual reporta 28 vulnerabilidades: 0 críticas, 21 altas, 6 moderadas e 1 baixa. A ausência de vulnerabilidade crítica não equivale a aprovação de produção.

## Validação repetida

- `npm run typecheck`: PASS
- `npm run build`: PASS
- `node --test tests/*.test.mjs`: 119/119 PASS
- `npx playwright test`: 6/6 PASS
- ESLint de `app/api/reports/export/route.ts`: PASS, após aproximadamente 88 segundos
- ESLint agrupado: excede o limite operacional observado; não tratado como PASS
- `npm audit --json`: executado; 28 vulnerabilidades residuais

## Recomendação

Não integrar automaticamente em `main`. A branch está pronta para revisão e para abertura manual de Pull Request, mas a classificação continua **PRONTO COM RESTRIÇÕES / NÃO PRONTO PARA PRODUÇÃO** até:

1. validação autenticada em staging isolado;
2. análise dos riscos RSC, Nodemailer e Vinext;
3. execução de lint agrupado concluída ou diagnóstico de desempenho corrigido;
4. cobertura real dos fluxos externos e documentos privados.
