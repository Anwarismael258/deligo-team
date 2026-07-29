# Auditoria read-only do backend central — migrations 289–315

Esta auditoria foi produzida apenas por leitura dos ficheiros locais em
`C:\Users\Administrator\deligo_app\supabase\migrations`. Nenhuma ligação,
consulta ou alteração foi feita no Supabase.

## Núcleo identificado

- Schemas: `core`, `payments`, `deligo`, `comunhao`, `sarca`, `taomoz`.
- Identidade: `core.profiles`, `core.apps`, memberships, roles e permissions.
- Segurança: `core.has_role`, `core.has_permission`, `core.can_access_app`,
  RLS e `core.audit_logs`.
- Serviços transversais: staff, Support, Marketing e Field em `core`.
- Financeiro: contas, métodos, transacções, escrow, payouts, refunds,
  reconciliação e ledger imutável em `payments`.
- TaoMoz: catálogo, variantes, carrinho, checkout multi-loja, comissões,
  logística e lotes de importação.

## Contrato de integração proposto

O HQ consumirá apenas APIs/RPCs aprovadas. Não consultará tabelas financeiras
directamente. Cada adapter exige contexto de utilizador, aplicação, permissão
e entidade jurídica.

| Área HQ | Fonte prevista | Estado |
|---|---|---|
| Identidade/RBAC | `core` | Contrato local, ligação bloqueada |
| Suporte | `core.support_*` | Contrato local, ligação bloqueada |
| Marketing | `core.marketing_*` | Contrato local, ligação bloqueada |
| Field | `core.field_*` | Contrato local, ligação bloqueada |
| Financeiro | API server-side sobre `payments` | Não ligar sem revisão |
| TaoMoz | API server-side sobre `taomoz` | Não ligar sem validação da 315 |

## Gates antes da ligação

1. Confirmar staging versus produção.
2. Versionar o repositório DeliGo e criar uma baseline.
3. Backup lógico e plano de rollback.
4. Testes de RLS por persona e aplicação.
5. Testes de idempotência, ledger e reconciliação.
6. Aprovação explícita das migrations financeiras.
7. Só então configurar secrets server-side no HQ.
