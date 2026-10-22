-- O fluxo de dupla aprovação usa approved antes de reservar e executar o ledger.
alter table public.admin_corporate_withdrawals
  drop constraint if exists admin_corporate_withdrawals_status_check;

alter table public.admin_corporate_withdrawals
  add constraint admin_corporate_withdrawals_status_check
  check (status in (
    'pending', 'pending_approval', 'approved', 'reserved',
    'processing', 'paid', 'failed', 'rejected', 'cancelled', 'completed'
  ));

notify pgrst, 'reload schema';
