# DeliGo Triunfal HQ — mapa de arquitectura

## Estado encontrado

O workspace recebido estava vazio. Não continha aplicações, schemas, migrations,
APIs, project references do Supabase, variáveis de ambiente ou histórico técnico
dos sistemas DeliGo, Comunhão, TaoMoz e SARCA. Por isso, nenhuma integração real
foi inventada e nenhuma base de dados foi alterada.

## Arquitectura alvo

```text
Central Web
  ├─ Central Auth / SSO
  ├─ RBAC (employee → roles → platforms → permissions)
  ├─ Audit / Login History
  ├─ People / Operations / Finance
  └─ Integration service layer
       ├─ DeliGo adapter
       ├─ Comunhão adapter
       ├─ TaoMoz adapter
       └─ SARCA adapter
```

Cada adapter deve consultar a fonte original através de uma API segura e
normalizar apenas as respostas necessárias. Dados operacionais não devem ser
copiados para a Central sem uma razão explícita. Autorização é validada no
servidor em cada pedido, incluindo plataforma e acção.

## Matriz de migração inicial

| Existing App | Existing Feature | New Web Module |
|---|---|---|
| DeliGo Admin | Customers, restaurants, couriers, orders, wallets | Platforms / DeliGo |
| DeliGo Field | Tasks, visits, verifications, acquisition | Field |
| DeliGo Marketing | Campaigns, content, promotions, analytics | Marketing |
| Customer Support | Tickets, chat, complaints, incidents | Support |
| Comunhão Admin | Churches, members, groups, events, finance | Platforms / Comunhão |
| TaoMoz Admin | Users, companies, services, transactions | Platforms / TaoMoz |
| SARCA | To be inventoried from source | Platforms / SARCA |

## Entregas incrementais

1. Foundation: SSO, RBAC, employees, platform access, dashboard, audit.
2. Transversal modules: Finance, Marketing, Field, Support.
3. Platform adapters: DeliGo, Comunhão, TaoMoz, SARCA.
4. Analytics, reports and advanced operations.
5. Performance, responsive refinements and automation.

## Pré-requisitos para integração

Fornecer os repositórios ou caminhos locais de cada aplicação e, por ambiente,
o inventário de Supabase/API (project reference, schema/migrations, Edge
Functions and API documentation). Secrets devem ser entregues apenas por um
gestor seguro de ambiente, nunca gravados no frontend ou neste documento.
