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
