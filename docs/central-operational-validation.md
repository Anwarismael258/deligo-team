# Central HQ — validação operacional

## Correcções desta revisão

- Perfil e levantamento passam a resolver o mesmo titular canónico do trabalhador. O backend escolhe as carteiras pessoais pela identidade autenticada; valores de carteira enviados pelo cliente não escolhem carteiras alheias.
- O disponível para levantamento soma apenas fontes activas e elegíveis. O pedido pode usar saldos HQ e canónicos, reservando as parcelas antes de chamar o fornecedor. Não inclui carteiras corporativas ou contas marcadas como fictícias/teste.
- Cada pedido tem uma chave persistida no servidor e recuperável pelo navegador após falha de ligação. Repetir o mesmo pedido não faz novo envio. Conclusão e rejeição são idempotentes; uma rejeição tardia não devolve um pagamento já liquidado. Uma falha de rede ou de confirmação conserva a reserva para reconciliação.
- A resposta `status: success` do envelope HTTP PaySuite não é considerada prova de pagamento: utiliza-se `data.status`. As referências novas respeitam o formato alfanumérico e o limite de 30 caracteres da API. O webhook mantém HMAC-SHA256 e suporta a chave Supabase secreta actual; valores do evento em MZN são convertidos para unidades menores.
- As notificações pessoais estão disponíveis a todos os trabalhadores activos e consultam sempre `employee_id` do utilizador autenticado. A entrega Mestre24 usa chave única e upsert atómico, evitando duplicação por consultas simultâneas. A API de tarefas deixa a criação da notificação ao trigger existente. Duplicados legados conhecidos são ocultados na leitura, sem apagar o histórico ou agrupar mensagens distintas de chat.
- O Centro de Notificações abre o registo de origem e regista a leitura. Os erros de actualização são apresentados. Respostas da caixa institucional são filtradas pelas mensagens da área autorizada; actualizações de tarefas são filtradas pelas tarefas do destinatário.

- Corrigida a chamada RPC da Inbox interna: as funções `chat_*` são invocadas no esquema `hq`, mantendo as funções financeiras existentes no esquema `public`.

## Activação indispensável

1. Executar `487_hq_withdrawal_reliability.sql` e `488_hq_notification_delivery_dedupe.sql` no SQL Editor do Supabase correspondente à Central, depois das migrações anteriores. Não são executadas pelo deploy Vercel.
2. Configurar no projecto Vercel que publica a Central: `PAYSUITE_ENABLED=true`, `PAYSUITE_API_TOKEN`, `PAYSUITE_WEBHOOK_SECRET`, `PAYSUITE_API_URL=https://paysuite.tech/api/v1`, `PAYSUITE_WEBHOOK_URL=https://www.deligoteam.online/api/payments/paysuite/webhook`. Nunca guardar o token no GitHub ou expô-lo ao navegador. Na revisão, o projecto Vercel `deligo-team` não apresentava nenhuma variável `PAYSUITE_*`.
3. Confirmar com o fornecedor que payouts estão habilitados e que a conta tem fundos, configurar o mesmo segredo e URL de webhook, e publicar novamente.
4. O número de destino deve estar verificado no perfil oficial do trabalhador. A activação não modifica esse número e não transfere dinheiro automaticamente.

## Critério de aceitação em produção

| Área | Validação necessária com contas reais |
| --- | --- |
| Perfil e saldo | Cada cargo vê o próprio saldo; a troca de identidade/carteira na requisição não permite saldo de outro trabalhador. |
| Levantamentos | Um trabalhador escolhe M-Pesa/e-Mola, confirma um montante e recebe a transferência; a reserva torna-se débito apenas após confirmação e o webhook reconcilia o pedido. Repetir o envio não duplica o pagamento. |
| Notificações | Um evento aparece uma vez por destinatário, também com várias sessões abertas; abrir regista leitura; o destinatário consegue consultar o seu registo. |
| Inbox interna | Duas contas de cargos diferentes trocam mensagens e anexos; não participantes não consultam mensagens/anexos; reunião validada com dois navegadores. |
| Projectos e tarefas | Apenas Admin/Finanças/Supervisor atribuem; o destinatário abre a descrição completa e actualiza a sua tarefa. |
| RH e Pessoas | Admissão, activação, alteração autorizada e desligamento percorrem o fluxo e preservam auditoria; salários só para perfis autorizados. |
| Finanças e Contabilidade | Receitas conciliadas, lançamentos e aprovações respeitam separação de funções; relatórios conferem com o ledger. |
| Suporte e Campo | Ticket/KYC atribuído percorre abertura, tratamento e conclusão, com evidências acessíveis só ao âmbito autorizado. |
| Marketing e site | Conteúdo percorre rascunho, revisão e publicação e aparece no canal correcto. |
| Jurídico, Compliance, IT e Património | Cada módulo confirma leitura autorizada, escrita, aprovação quando exigida e auditoria com uma conta do cargo correspondente. |

Os testes locais e a compilação não substituem estes cenários autenticados, os serviços externos nem a execução das migrações. Nesta revisão não foi realizada nenhuma transferência real e não se certifica a Central inteira como operacional em produção.

## Operações com confirmação pendente

Se uma chamada ao fornecedor expirar ou a aplicação falhar depois de reservar, o pedido permanece em processamento. O suporte financeiro deve consultar o payout pela referência e reconciliar com o ledger; não deve devolver o saldo nem reenviar o pagamento só porque ocorreu timeout. Não existe nesta entrega um job automático de reconciliação de todos os casos ambíguos.

Documentação oficial consultada: https://paysuite.tech/docs/ (payouts e webhooks).

## Resultado da suite existente

Foram executados 154 testes: 146 passaram e 8 falharam. As mesmas 8 falhas foram reproduzidas num checkout separado da `main` anterior a esta alteração. Envolvem asserções de dashboards executivo/plataformas, governação financeira, histórico, mapa, suporte e dashboard de equipa. Não foram alteradas as asserções para forçar aprovação. TypeScript e compilação passaram. Os novos testes incluem execução das migrações numa base PostgreSQL isolada e cenários de saldo, timeout, rejeição, reenvio e deduplicação.
