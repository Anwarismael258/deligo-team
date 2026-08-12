# DeliGo Central — camada corporativa de integração

O DeliGo Central é o único produto administrativo do ecossistema DeliGo Triunfal, Lda. As aplicações DeliGo, SARCA, DeliGo Market, Comunhão, Mestre24 e ExploreMoz mantêm os seus dados operacionais; o HQ fornece identidade, controlo, auditoria, suporte, eventos, finanças e métricas corporativas.

## Catálogo e identidade

`hq.platforms` é o registo corporativo. Os códigos estáveis são `DELIGO`, `SARCA`, `DELIGO_MARKETING`, `COMUNHAO`, `MESTRE24` e `EXPLOREMOZ`. O slug legado `taomoz` é mantido apenas para não quebrar o DeliGo Market já existente.

Uma Conta Triunfal é uma única identidade em `auth.users` e `core.profiles`. A participação por produto é registada em `core.user_app_memberships` e os papéis em `core.user_roles`, ligados a `core.apps` e `core.roles`. A visão `hq.global_user_platforms_v1` é a base segura para o perfil corporativo de utilizador.

## Eventos, auditoria e finanças

A migration `388_hq_corporate_platform_integration_layer.sql` cria:

- `hq.platform_events`: stream corporativo idempotente para atividade operacional;
- `hq.platform_financial_events`: leitura financeira consolidada por plataforma;
- `hq.central_daily_metrics`: métricas agregadas, evitando consultas pesadas nos dashboards;
- `hq.platform_notification_requests`: pedidos de envio sujeitos a aprovação;
- `hq_ingest_platform_event_v1` e `hq_ingest_platform_financial_event_v1`: contratos de ingestão exclusivos de `service_role`.

Cada evento inclui plataforma, origem, tipo, entidade, utilizador/actor quando aplicável, instante e payload limitado. O payload não deve conter palavras-passe, tokens, documentos KYC ou outros segredos. A auditoria administrativa continua em `hq.audit_logs` e em `core.audit_logs`.

A migration `389_hq_platform_event_adapters.sql` liga o stream automaticamente aos domínios existentes: `public.order_events` (DeliGo), `sarca.trip_events` e viagens concluídas, `taomoz.orders`, `comunhao.churches`, `comunhao.memberships`, `comunhao.church_subscriptions`, `mestre24.service_requests` e `mestre24.subscription_cycles`. Todos usam uma chave de origem idempotente: repetir uma alteração não duplica eventos no HQ.

O HQ expõe a leitura autorizada através de `GET /api/activity`, com filtro opcional `?platform=deligo`, `sarca`, `taomoz`, `comunhao` ou `mestre24`. A rota aplica o escopo do colaborador antes de devolver eventos.

## KYC corporativo único

`hq.platform_kyc_cases` é a fila central de KYC para DeliGo, SARCA, DeliGo Market, Comunhão e Mestre24. Ela armazena a referência de origem, o tipo de sujeito, o estado, a razão de decisão e apenas referências privadas a documentos. A Central abre documentos por URLs assinados temporários, sem tornar os buckets públicos.

`GET /api/kyc` lista a fila com filtros por `platform` e `status`. `PATCH /api/kyc` aceita `approve`, `reject`, `suspend` e `correction`; as três últimas exigem motivo e toda decisão é guardada em `hq.audit_logs`. A alteração é propagada para o domínio de origem: perfis DeliGo, documentos/perfil SARCA, vendedores DeliGo Market, igrejas Comunhão ou profissional Mestre24. ExploreMoz permanece preparado no catálogo e entrará na mesma fila quando tiver backend operacional.

## Command Center e pesquisa global

`GET /api/command-center` fornece indicadores consolidados de GMV, receita de comissão, operações do dia, KYC pendente, suporte e pedidos de comunicação, além do Live Feed alimentado por `hq.platform_events`. A Home consulta esta rota a cada 15 segundos enquanto está aberta; relatórios históricos continuam a usar agregações, não Realtime.

`GET /api/global-search?q=` pesquisa a Conta Triunfal por nome, telefone ou email e devolve apenas as memberships, papéis, KYC e atividade permitidos pelo escopo do colaborador. O atalho “Pesquisar em toda a Central” usa esta rota. Dados financeiros sensíveis e documentos privados permanecem fora desta pesquisa geral.

## Integração por plataforma

| Plataforma | Integração já existente | Próximo adaptador operacional |
| --- | --- | --- |
| DeliGo | Operações, restaurantes, estafetas, suporte e campanhas no HQ | emitir pedidos/entregas e comissão para o stream corporativo |
| SARCA | Dashboard, motoristas e segurança | emitir viagens, estados e comissão de viagem |
| DeliGo Market | KYC, produtos, pedidos, disputas e levantamentos | emitir vendas, envios e comissão de marketplace |
| Comunhão | Igrejas, subscrições e notificações | emitir adesões, eventos e pagamentos permitidos |
| Mestre24 | KYC, profissionais, pedidos, subscrições, denúncias e avaliações | emitir pedidos e ciclos de subscrição |
| ExploreMoz | Registado no catálogo como planeado, sem backend operativo | criar app/backend e ligar parceiros, locais e reservas |

## Segurança e próximas fases

As aplicações não recebem credenciais de serviço. Cada adaptador de backend usa `service_role` no servidor/Edge Function para chamar os RPCs idempotentes. O HQ aplica RBAC por plataforma e mantém URLs de KYC assinadas.

As próximas fases são ligar os adaptadores a eventos reais de cada app, consolidar pagamentos após a chegada das APIs oficiais e expor no HQ as filas globais de KYC, denúncias, métricas, pesquisa e mapa operacional conforme permissões.
