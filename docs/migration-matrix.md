# Migração dos painéis administrativos para o HQ

O HQ usa o mesmo backend DeliGo staging e não duplica dados. Cada painel é adaptado como módulo nativo, com autorização corporativa verificada no servidor.

| Origem | Módulo HQ | Fontes reais | Funcionalidades |
|---|---|---|---|
| DeliGo Admin | Operações / Direcção | `profiles`, `orders`, `wallets`, `order_disputes`, `admin_actions_log` | clientes, KYC, equipa, alertas, disputas, OTP, despacho e auditoria |
| Marketing | Marketing | `marketing_requests`, `marketing_campaigns`, `marketing_events` | pedidos, conteúdos, campanhas, publicidade, push, cupões, eventos e estatísticas |
| Field | Field | `profiles`, `restaurants`, `couriers`, `field_internal_notes` | mapa, tarefas, KYC, restaurantes, estafetas, visitas, notas e relatórios |
| Suporte | Apoio ao Cliente | `support_tickets`, `support_messages`, `order_disputes` | fila, chat, reclamações, incidentes, disputas, utilizadores e histórico |

Próximas etapas: formulários completos, decisão KYC, notas Field, chat, uploads, mapas, tempo real, notificações e painéis de Comunhão, SARCA e TaoMoz. Toda escrita valida actor, role, módulo e acção no servidor e deve gerar auditoria.

A primeira entrega operacional está identificada como versão 10 do HQ.

## Aprovação transversal de identidades operacionais

- DeliGo: estafetas e restaurantes seguem submissão, verificação Field e decisão Operações/Supervisor.
- SARCA: condutores seguem onboarding, documentos do condutor, veículo e decisão Operações/Supervisor.
- Comunhão: igrejas seguem candidatura, validação documental e decisão Operações/Supervisor; a activação deve chamar o fluxo nativo que cria igreja, código e subscrição.
- TaoMoz: vendedores submetem BI/NUIT, comprovativos e selfie; apenas após aprovação a loja fica activa e pode publicar produtos.
- O Super Admin não é a fila normal de aprovação: trata excepções, conflitos, fraude, alto risco e reversões protegidas.
- Field pode pedir correcções e recomendar uma decisão, mas não deve aprovar sozinho o trabalho que verificou.
