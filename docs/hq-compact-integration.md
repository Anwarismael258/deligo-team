# Integração na Central escura

Branch de destino: `feature/hq-overview-compact`.

Este conjunto adapta os PRs #14 (tarefas), #15 (Inbox interna) e #16 (fiabilidade) à Central escura, a partir do commit `d353b03`. O PR #16 dirigido à main foi encerrado sem integração. As alterações anteriores à main não são removidas nem substituem a branch de destino.

## Preservado da branch compacta

- Tema escuro e estilos globais, dashboards compactos, correcções de autenticação e visibilidade, módulos de suporte, caixa institucional/IMAP e funções existentes.
- Detecção automática da operadora pelo número protegido: M-Pesa, e-Mola e mKesh. A escolha não vem do navegador.
- Levantamentos pela função Supabase `wallet-withdraw-v2` quando o token PaySuite não está na Vercel. As credenciais partilhadas continuam no Supabase; não é necessário duplicá-las só para manter este caminho.
- Número protegido do perfil, com fallback para o contacto oficial do trabalhador já utilizado pela branch.

## Acrescentado e corrigido

- Tarefas recebidas primeiro, destaque de novas, leitura completa em diálogo e atribuição apenas por Admin, Finanças e Supervisor, validada no servidor.
- Inbox interna separada das notificações, acessível a todos os trabalhadores activos, com conversas individuais/grupos, respostas, anexos privados e reuniões Jitsi.
- Chamadas RPC da Inbox usam explicitamente o esquema `hq`; as funções financeiras anteriores continuam em `public`.
- Identidade de carteira pessoal consistente, soma apenas de montantes levantáveis, pedido idempotente persistente, protecção de reservas em timeout, interpretação correcta de `data.status` e protecção contra falhas tardias após um payout pago no caminho financeiro local.
- A delegação Edge mantém autenticação pela sessão original. A Central não reenvia a mesma tentativa; também transmite o identificador ao serviço partilhado. O funcionamento interno da Edge Function externa deve ser validado no seu projecto próprio.
- Notificações pessoais para todos os cargos, entrega Mestre24/suporte com upsert atómico e eliminação da dupla criação de notificações de tarefas pela API e trigger. A captação de mensagens de suporte respeita destinatários atribuídos, salvo funções de supervisão.
- Respostas da caixa institucional consultadas no âmbito das mensagens autorizadas.

## Base de dados

Executar no Supabase correspondente a esta Central:

1. `578_hq_internal_messenger.sql`: conversas, mensagens, anexos, RPCs e bucket privado. É idempotente relativamente à migração da Inbox anteriormente fornecida como 486.
2. `579_hq_withdrawal_reliability.sql`: tentativas idempotentes e guardas financeiras, preservando o mapeamento de três operadoras da migração própria desta branch.
3. `580_hq_notification_delivery_dedupe.sql`: unicidade completa para upsert PostgREST.

Os números foram ajustados para evitar confusão com as migrações 486/487 já existentes nesta branch. Não executar em substituição as versões financeiras de outra branch, pois perderiam o mapeamento mKesh e as correcções desta versão.

## Configuração e limites

- O caminho Edge existente exige a função `wallet-withdraw-v2` publicada, credenciais configuradas no Supabase e sessão activa. A inexistência de `PAYSUITE_*` na Vercel não prova indisponibilidade desse caminho.
- O caminho PaySuite directo na Vercel exige as suas credenciais e webhook válidos. A activação não executa transferências automaticamente.
- Anexos: até 5 ficheiros de 3 MB. Grupos incluem os trabalhadores seleccionados/activos no momento da criação.
- Reuniões usam Jitsi; o organizador pode precisar de iniciar sessão no serviço. `HQ_MEET_BASE_URL` permite uma instância HTTPS própria. A admissão na sala é controlada pelo Jitsi.
- Testes locais e compilação não certificam todas as áreas em produção. Requer teste autenticado com duas contas, verificação dos operadores e webhook, e um levantamento real de montante escolhido pelo trabalhador. Não foi realizada nenhuma transferência real nesta integração.

## Validação da integração

TypeScript e compilação de produção concluídos; 165 testes passaram, sem falhas ou testes ignorados, incluindo execução das novas migrações numa base PostgreSQL isolada. As verificações antigas de código foram ajustadas para a extracção do titular da carteira para um helper, a lista ampliada de módulos pessoais, o filtro multilinha de mensagens de clientes e a protecção da navegação durante validação da sessão; não foi removida essa protecção. Os estilos globais da Central escura foram preservados.
