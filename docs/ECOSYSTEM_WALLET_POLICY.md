# Política de carteiras do ecossistema

As contas `841130015`, `827688695` e `877688695` usam uma carteira central por pessoa, com saldo inicial de `20.000 MZN` cada.

O saldo é interno ao ecossistema: pode ser usado em transferências entre plataformas e no processamento de payroll, mas não pode ser levantado para M-Pesa, E-Mola, banco ou outro fornecedor externo enquanto a integração de pagamentos não estiver ativa e aprovada.

As carteiras antigas por plataforma não são apagadas. São fechadas após a reconciliação e todos os lançamentos permanecem no ledger para auditoria. A interface dos apps não expõe a etiqueta de teste; o backend mantém `internal_only`, `withdrawal_disabled` e `provider_integration=pending` para impedir que um saldo interno seja apresentado como dinheiro externo disponível.
