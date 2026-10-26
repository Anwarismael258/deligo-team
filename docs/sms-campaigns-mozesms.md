# Campanhas SMS na Central HQ

## Resultado

Página `/marketing/sms`, ligada na área Marketing da Central. Usa o endpoint MozeSMS `/sms/send`, já utilizado pelo hook OTP, e as credenciais existentes no Vault. Nenhuma alteração ao OTP nem chamadas reais durante o desenvolvimento.

Inclui rascunhos por plataforma, diretório paginado, registo de prova de consentimento, teste individual por campanha direcionada a um utilizador autorizado, autorização pelo Super Admin, fila persistente, pausa/cancelamento, consulta de saldo, estimativa por destinatário e resultados agregados. Telefones são normalizados e deduplicados. Contactos são revalidados contra o diretório e consentimentos no momento da preparação e de cada envio.

Aceite pela API não significa entregue. `unknown` nunca é reenviado automaticamente. Uma operação interrompida em `sending` torna-se desconhecida após cinco minutos na próxima execução de uma campanha pronta. Estados incertos devem ser reconciliados no painel MozeSMS.

## Configuração antes de ativar

1. Rever/aplicar `486_hq_sms_campaigns.sql` no ambiente de teste. Confirmar os campos `primary_phone`, `membership_status` e `profile_status` da visão `hq.global_user_platforms_v1` e os valores activos. Ausência de confirmação de estado activo exclui o contacto.
2. Confirmar os segredos já existentes no Supabase Vault: `mozesms_api_key`, `mozesms_api_secret` e `mozesms_sender_id`. O remetente precisa estar aprovado para marketing. A RPC de configuração só pode ser chamada por `service_role`; nunca expor o seu resultado ao cliente ou logs.
3. Manter `MOZESMS_MARKETING_ENABLED=false` até terminar a homologação.
4. Configurar `MOZESMS_MARKETING_MIN_BALANCE_MZN` com uma margem positiva escolhida pela empresa para OTP. Sem esta variável válida ou sem saldo/preço MZN verificável, nenhum envio de campanha é efectuado.
5. Para execução automática independente do navegador: definir `MOZESMS_MARKETING_WORKER_SECRET` aleatório com pelo menos 32 caracteres e um scheduler privado que faça POST a `/api/marketing/sms/dispatch` com o header `Authorization: Bearer <segredo>`. O segredo fica apenas no servidor/scheduler. O endpoint não é um webhook do fornecedor.
6. O processador é conservador: até cinco campanhas por chamada e um SMS por campanha, com serialização global dos envios de marketing. Para campanhas maiores, validar limites/rate limit contratados antes de aumentar a frequência. Não foi configurado nenhum scheduler nem feito deploy.
7. Activar `MOZESMS_MARKETING_ENABLED=true` apenas no ambiente de teste e realizar uma campanha individual para um destinatário autorizado; confirmar nome do remetente, cobrança e receção real. Depois testar as três redes, duplicados, pausa e falhas.

O piso de saldo é uma verificação antes de cada envio, não uma reserva financeira transacional no fornecedor. OTP e outros sistemas podem consumir a mesma conta. Para garantia de separação financeira, confirmar subconta/créditos separados com a MozeSMS.

## Segurança e operação

- `marketing.sms` controla leitura/rascunhos/consentimentos, com âmbito de plataforma no servidor. Super Admin autoriza a fila e faz envios manuais. Worker usa segredo próprio e processa apenas filas já autorizadas.
- RLS activada nas cinco tabelas e sem acesso directo para `anon`/`authenticated`. Funções públicas restritas a `service_role`.
- Mutations com cookie exigem Origin igual ao origin da aplicação. Confirmar reverse proxy no staging; não remover a verificação para contornar problemas de configuração.
- Marketing não herda consentimento do OTP. O registo de autorização precisa de prova. Revogação por Super Admin também cria supressão global do número, que não é removida automaticamente quando uma autorização é novamente registada.
- Cada campanha autorizada é imutável; alterações exigem novo rascunho. Pausa/cancelamento só impedem novas reclamações da fila, não recolhem SMS já em trânsito.
- Incluir no texto um contacto ou link funcional para deixar de receber publicidade. Esta versão não implementa página pública de cancelamento nem recebe respostas do remetente alfanumérico.
- A documentação MozeSMS tem limites bulk contraditórios e exemplos de saldo divergentes. Esta versão usa apenas envio individual e falha fechada se o saldo não tiver o contrato esperado. Não assume limites bulk nem preço fixo.

## Validação efectuada

`node --test tests/sms-campaigns.test.mjs`: 6 testes passaram. Cobrem telefones, GSM-7/extensão/Unicode, validação, payload e autenticação do fornecedor, falhas explícitas vs incertas, ausência de retries e piso de saldo. Usam transportes simulados e não enviam SMS.

`node --check` passou nos novos ficheiros TypeScript de servidor/helpers. A análise sintática Babel passou em ambas as páginas TSX alteradas (não substitui typecheck). O ambiente não dispõe das dependências completas do projecto nem de PostgreSQL: typecheck/build/lint completos, execução da migração, testes de concorrência/RLS e QA visual autenticado continuam pendentes. A mudança deve permanecer em draft até esses checks passarem.

## Próximas extensões

Relatórios de entrega reais com autenticação do webhook validada pelo fornecedor; opt-out público com token; filtros por cidade e grupos; agendamento por campanha; reconciliação automática dos estados desconhecidos. Estes itens não são simulados como implementados.
