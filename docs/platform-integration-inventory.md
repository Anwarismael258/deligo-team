# Inventário de integração das plataformas

## DeliGo

Fonte: `C:\Users\Administrator\deligo_app`.

- `deligo_admin`: operações administrativas, pagamentos, pedidos, KYC, suporte e segurança.
- `deligo_field`: verificações no terreno, estafetas, restaurantes e notas internas.
- `deligo_marketing`: campanhas, notificações e aquisição.
- Serviços relevantes: `kyc_service.dart`, `order_service.dart`, `trust_safety_service.dart`, `wallet_deposit_service.dart` e `realtime_service.dart`.

## Comunhão

Fonte: `C:\Users\Administrator\igreja`.

- `apps/comunhao_super_admin`: painel de super administração.
- Fluxos confirmados: candidaturas de igrejas, aprovação/correção/rejeição, subscrições, igrejas geridas, membros, eventos, campanhas, pedidos de oração, documentos, activos, despesas e comunicações.
- Migrações relevantes: `20260720192000_super_admin_church_controls_notifications.sql`, `20260720201000_plus_trial_blocks_after_30_days.sql` e `20260720204000_finalize_church_registration_approval_flow.sql`.

## SARCA

Fonte: `C:\Users\Administrator\sarca`.

- Edge Functions administrativas confirmadas: `admin-get-dashboard`, `admin-list-accounts`, `admin-list-driver-reviews`, `admin-review-driver-onboarding`, `admin-update-account-status`, `admin-list-payout-requests` e `admin-review-payout-request`.
- Fluxos confirmados: condutores, documentos KYC, veículos, viagens, pagamentos, carteiras, levantamentos e auditoria administrativa.
- Migrações relevantes: `20260427101000_driver_onboarding_and_kyc.sql`, `20260427193000_admin_backoffice_and_manual_payouts.sql` e `20260426115500_profile_media_bucket.sql`.

## Regra de integração do HQ

O HQ deve chamar APIs/RPCs/Edge Functions server-side de cada plataforma, usando o actor corporativo e registando cada operação no audit log central. Não deve escrever directamente nas tabelas financeiras ou contornar os fluxos nativos de aprovação.

## Configuração do gateway

As URLs podem ser definidas separadamente no ambiente do HQ através de `DELIGO_SUPABASE_URL`, `COMUNHAO_SUPABASE_URL`, `SARCA_SUPABASE_URL` e `TAOMOZ_SUPABASE_URL`. Quando não definidas, o gateway usa o backend configurado em `SUPABASE_URL`, útil para o staging partilhado.
