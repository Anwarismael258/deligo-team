# Fase 8 — auditoria do Triunfal Microcrédito

## Fontes auditadas

| Indicador | Fonte canónica verificada | Estado |
| --- | --- | --- |
| Pedidos, estados, montantes solicitados e datas | `staging.loan_applications` | disponível |
| PDFs/WhatsApp do pedido | `staging.loan_application_deliveries` | disponível como entrega, não como pagamento |
| Contratos | `staging.loan_contracts` | indisponível nesta instalação se não houver registos |
| Desembolsos | `staging.loan_disbursements` | indisponível nesta instalação se não houver registos |
| Pagamentos/recuperação | `staging.loan_repayments` | indisponível nesta instalação se não houver registos |
| Garantias/penhores | `staging.loan_collaterals` | indisponível nesta instalação se não houver registos |
| Histórico | `staging.loan_application_history` | indisponível nesta instalação se não houver registos |

O endpoint `GET /api/analytics/microcredit` é somente leitura e fica restrito a `SUPER_ADMIN` e `FINANCE`. O painel usa os componentes analytics existentes, o fuso `Africa/Maputo` e períodos de 7, 30, 90 dias ou personalizados.

## Regras de segurança e limitações

Um pedido aprovado nunca é contado como desembolso. Valores recuperados, dívida, atrasos, contratos e garantias só aparecem quando a fonte específica existe e possui registos verificáveis. Não há pontuação de risco pessoal, classificação automática ou decisão de crédito. Nenhuma migration, alteração financeira, aprovação ou chamada PaySuite foi realizada.
