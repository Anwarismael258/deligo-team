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

Os conceitos `legal_entity`, `platform`, `brand` e `business_unit` são
entidades distintas. Consolidação financeira só pode ocorrer entre entidades
juridicamente autorizadas.

## Modelo corporativo e RBAC

O controlo de acesso segue:

```text
person → employment/collaboration → roles → platform access → permissions
```

Ownership é armazenado separadamente, com histórico e controlo reforçado. Os
roles adicionais previstos são `ACCOUNTANT`, `HR`, `LEGAL_COUNSEL`,
`TECHNOLOGY` e `EXTERNAL_COLLABORATOR`. Colaboradores externos têm validade
de acesso e são revogados sem apagar o histórico.

## Separação financeira

Os ledgers devem distinguir, sem agregação implícita:

- dinheiro da empresa;
- contas bancárias e caixa;
- saldos de carteiras de utilizadores;
- dinheiro de terceiros;
- contas a pagar e receber;
- impostos, reservas e valores pendentes;
- lucro contabilístico, lucro retido e lucro distribuível.

`bank balance` nunca é derivado como `profit`. Distribuição de lucros exige:

```text
Draft → Prepared → Finance Review → Shareholder Approval
      → Payment Pending → Paid → Reconciled
```

Quem prepara não pode, sozinho, rever, aprovar, pagar e reconciliar a mesma
operação.

## Domínios corporativos

| Domain | Scope |
|---|---|
| Finance | Treasury, bank accounts, cash, budgets, payables/receivables |
| Accounting | Journal, chart of accounts, reconciliation, tax, statements |
| Human Resources | Contracts, attendance, leave, payroll, lifecycle |
| Legal | Contracts, corporate records, compliance, licences and policies |
| Shareholders | Ownership history, resolutions and approved distributions |
| Technology / IT | APIs, databases, integrations, backups, incidents and monitoring |
| Procurement | Purchase requests, approvals, suppliers, invoices and payment handoff |
| Assets | Asset register, assignments, lifecycle, value and return tracking |
| Compliance & Risk | Policies, risk register, incidents, reviews and controls |
| Internal Helpdesk | Employee requests routed to authorised departments |
| Projects & Tasks | Objectives, deadlines, assignments, dependencies and progress |

Payroll, documentos pessoais, dados bancários, fiscais e jurídicos exigem
permissões específicas, auditoria e least privilege.

## Hierarquia administrativa

`ADMIN` não é um role global. A hierarquia é Super Admin, administradores
limitados por domínio, gestores de departamento, supervisores, trabalhadores e
colaboradores externos. Autoridade efectiva resulta sempre da intersecção entre
permissão, módulo, plataforma, entidade jurídica e validade de acesso.

Technology/IT não recebe acesso financeiro por defeito. Procurement não pode
aprovar e pagar a própria compra. Assets mantém histórico de atribuição e
devolução sem apagar registos anteriores.

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
