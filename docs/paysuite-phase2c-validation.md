# Fase 2C — Validação externa PaySuite

Data da investigação: 2026-10-23  
Escopo: somente leitura; sem chamadas de produção, sem alterações de credenciais, webhooks, saldos ou movimentos.

## Fontes oficiais consultadas

- [PaySuite API Documentation](https://paysuite.tech/docs/), última atualização indicada na página: 29/03/2026.
- [PaySuite Terms and Conditions](https://paysuite.tech/terms/), consultado apenas como contexto do serviço.

## Integração existente na Central

O cliente comum está em `lib/paysuite.ts` e usa:

- `PAYSUITE_API_URL`, com fallback para `https://paysuite.tech/api/v1`;
- `PAYSUITE_API_TOKEN` em `Authorization: Bearer ...`;
- `PAYSUITE_ENABLED` para ativação explícita;
- timeout de 10 segundos;
- sem exposição dos valores das variáveis.

Chamadas existentes verificadas no código:

| Área | Endpoint | Método | Estado |
| --- | --- | --- | --- |
| Pagamentos | `/payments` | `POST` | existente; cria pedido de pagamento |
| Levantamentos | `/payouts` | `POST` | existente; cria payout |
| Webhook | `/api/payments/paysuite/webhook` | `POST` recebido | existente; valida assinatura e processa eventos |

Não foi adicionada nenhuma chamada externa nesta fase.

## Capacidades oficiais confirmadas

| Capacidade | Evidência oficial | Estado para reconciliação |
| --- | --- | --- |
| Detalhe de pedido de pagamento | `GET /api/v1/payments/{id}` | Confirmada para um pagamento conhecido |
| Estado de pagamento | campo `status` no detalhe e eventos `payment.success`/`payment.failed` | Confirmada para pagamentos conhecidos |
| Lista de payouts | `GET /api/v1/payouts?page=&limit=` | Confirmada; paginada |
| Detalhe de payout | `GET /api/v1/payouts/{id}` | Confirmada |
| Estados de payout | `pending`, `completed`, `failed`, `cancelled` | Confirmada |
| Lista/detalhe de reembolsos | `GET /api/v1/refunds` e `GET /api/v1/refunds/{id}` | Confirmada; paginada na lista |
| Consulta de saldo da conta | Nenhum endpoint documentado na fonte oficial consultada | Não confirmada |
| Extrato financeiro | Nenhum endpoint documentado na fonte oficial consultada | Não confirmada |
| Relatório de liquidação | Nenhum endpoint documentado na fonte oficial consultada | Não confirmada |
| Lista geral de transações | Não há endpoint geral documentado; existe apenas detalhe de pagamento por ID | Não confirmada |
| Taxa por movimento | A documentação menciona taxas, mas não define um campo/end-point de reconciliação completo | Fonte insuficiente |
| Movimentos em trânsito | Estados de pagamentos/payouts são documentados; não há consulta agregada de trânsito | Parcial; não reconciliável como saldo |

A autenticação documentada é Bearer token. Payouts e reembolsos listáveis aceitam `page` e `limit`; a documentação indica limite máximo de 100 para reembolsos. A documentação não define um endpoint de saldo ou um extrato com saldo inicial/final.

## Webhooks e limites de evidência

A documentação descreve assinatura HMAC no webhook e eventos de pagamento. O código da Central já trata eventos de pagamento, payout e reembolso, com persistência/idempotência interna. Um webhook confirma um evento recebido, mas não substitui um extrato externo nem prova o saldo disponível da conta PaySuite.

Por isso, a Central não deve mostrar `Saldo PaySuite` como confirmado apenas porque existem pagamentos ou webhooks internos. O estado permanece `NAO_RECONCILIADO_EXTERNAMENTE` até existir documentação e acesso autorizado a uma fonte de saldo/extrato/settlement, ou um relatório oficial verificável do período.

## Contrato de reconciliação recomendado

Quando a PaySuite disponibilizar uma fonte oficial suficiente, o adaptador de leitura deve receber:

1. identificador da conta/merchant;
2. período e fuso horário;
3. página e limite;
4. movimentos com ID único, tipo, estado, bruto, taxa, líquido, moeda e timestamps;
5. saldo inicial, saldo final ou saldo disponível, quando fornecido;
6. referências de payout, refund e settlement.

O adaptador deve normalizar os dados sem escrever no ledger, deduplicar pelo ID do provedor e devolver um dos estados `RECONCILIADO_EXTERNAMENTE`, `DIVERGENTE`, `PENDENTE`, `FONTE_INSUFICIENTE` ou `NAO_RECONCILIADO_EXTERNAMENTE`. Não deve inferir saldo a partir da soma de pagamentos.

## Resultado da Fase 2C

- Nenhuma chamada financeira foi executada.
- Nenhum saldo, webhook, credencial ou permissão foi alterado.
- O endpoint interno de reconciliação continua a expor PaySuite como não verificada.
- A recomendação é solicitar à PaySuite a documentação/permissionamento oficial de saldo, transações agregadas e settlement antes de implementar o adaptador.
