# DeliGo Triunfal Central — Contexto Consolidado

## Escopo

Este projecto é a Central administrativa única da **DeliGo Triunfal, Lda.**
Concentra a governação de DeliGo, Comunhão, SARCA e TaoMoz.

**Fora do escopo:** Deli Run e qualquer conversa, código ou operação que lhe
pertença. Não deve ser integrado, migrado nem usado como fonte deste HQ.

## Regra operacional

As quatro plataformas mantêm os seus produtos e fluxos para utilizadores
normais. O HQ é o único lugar para administração corporativa, aprovações,
auditoria, suporte transversal, marketing, Field, pessoas e consolidação.

| Unidade | Apps para utilizadores | Responsabilidade no HQ |
| --- | --- | --- |
| DeliGo | Cliente, restaurante, estafeta e parceiros | Operações, KYC, pedidos, suporte, carteira e parceiros |
| Comunhão | Membros e igrejas | Igrejas, pedidos de adesão, membros, subscrições e comunicação |
| SARCA | Passageiro e motorista | Condutores, viagens, segurança, carteira e suporte |
| TaoMoz | Compradores, vendedores e lojas | Vendedores, lojas, KYC, marketplace e operações |

## Arquitectura confirmada

1. A identidade corporativa e o RBAC pertencem ao HQ.
2. Cada plataforma mantém o seu domínio operacional; o HQ integra por APIs,
   RPCs e Edge Functions autenticadas.
3. `SUPER_ADMIN` é o administrador central das quatro unidades, mas todas as
   ações críticas devem continuar auditadas e respeitar escopo de plataforma.
4. Dados financeiros sobem ao Centro Financeiro do Grupo sem confundir receita
   corporativa com saldos de carteiras de utilizadores ou dinheiro de terceiros.
5. Nenhum painel administrativo paralelo deve substituir o HQ. Painéis legados
   passam a ser fontes de capacidades a migrar/integrar, não a autoridade final.

## Integrações já identificadas

- SARCA já possui operações de viagens, presença/localização de motorista,
  segurança, suporte e eventos de pagamento que devem ser apresentados no HQ.
- Comunhão usa a central de identidade e requer fluxos protegidos para pedido,
  aprovação de igreja, código e período de teste.
- DeliGo fornece operações de restaurantes, estafetas, pedidos, suporte,
  marketing e Field.
- TaoMoz deve ser integrado pelo adaptador próprio para vendedores, KYC, lojas
  e operações de marketplace.

## Prioridades de continuação

1. Consolidar no HQ as funções administrativas hoje existentes em SARCA
   Admin, DeliGo Admin, Marketing, Field e Comunhão Admin.
2. Remover duplicação de autoridade administrativa das apps legadas, sem
   interromper os fluxos dos utilizadores finais.
3. Completar adaptadores com credenciais administrativas de cada plataforma,
   para que aprovações e alterações nativas sejam executadas no sistema certo.
4. Ligar centro de alertas, mapa operacional por camadas, atividade corporativa,
   Meu Trabalho e métricas financeiras reais ao backend autorizado.
5. Manter trilho de auditoria imutável para quem, o quê, quando, onde e porquê.

## Fontes de contexto no Codex

As conversas originais continuam preservadas no Codex. Este documento consolida
as decisões técnicas, sem copiar credenciais ou eliminar histórico.

- `Mapear recursos Field para HQ`
- `Atualizar autenticação do Comunhão`
- `Verificar backends das aplicações`
- `Add driver trial and trip fees`
- `Olal robot` (TaoMoz)
- `Implementar CMS institucional`
- `Usar backend Deligo staging`

Use esta pasta e esta conversa como a base de trabalho da Central para as
quatro plataformas.
