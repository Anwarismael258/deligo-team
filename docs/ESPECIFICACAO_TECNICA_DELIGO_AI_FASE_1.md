# Especificação Técnica — DeliGo AI Fase 1

## 1. Objetivo

Criar a **DeliGo Intelligence Layer (DIL)**, uma camada central de inteligência ligada à Central HQ e às plataformas DeliGo, SARCA, DeliGo Market, Mestre24 e Comunhão.

O produto visível será **✨ DeliGo AI**. Na Fase 1, a IA opera apenas em:

- Nível 1: leitura autorizada;
- Nível 2: preparação de respostas, relatórios e ações para revisão humana.

Não poderá aprovar KYC, movimentar dinheiro, suspender contas, alterar dados críticos ou executar operações sensíveis automaticamente.

## 2. Arquitetura

```text
Utilizador → Central HQ → DeliGo AI Gateway
                         → autenticação e RBAC
                         → seleção de ferramenta
                         → consulta controlada
                         → modelo de IA
                         → resposta ou rascunho
                         → auditoria
```

O modelo nunca recebe acesso direto ao Supabase. Cada consulta passa por uma ferramenta tipada, com âmbito de plataforma, departamento e classificação de dados.

## 3. Componentes

### 3.1 AI Gateway

Responsável por validar sessão, role, departamento, plataforma, nível de ação, limites e registo de auditoria.

Endpoints previstos:

- `POST /api/ai/chat` — pergunta e resposta controlada;
- `GET /api/ai/tools` — ferramentas disponíveis para a sessão;
- `POST /api/ai/drafts/:id/approve` — aprovação humana de um rascunho;
- `GET /api/ai/audit` — histórico autorizado de consultas;
- `GET /api/ai/brief/daily` — brief executivo diário.

### 3.2 Ferramentas de leitura

- `get_company_summary`
- `get_support_queue`
- `get_pending_approvals`
- `get_finance_summary`
- `get_platform_status`
- `get_overdue_tasks`
- `get_recent_incidents`
- `get_pending_kyc`
- `get_active_employees`
- `get_wallet_summary`

Cada ferramenta deve devolver dados mínimos, agregados quando possível, e nunca credenciais, OTPs, passwords, tokens ou chaves privadas.

## 4. Modelo de dados Supabase

Criar no schema administrativo canónico `hq`:

### `hq.ai_tool_registry`

- `id uuid primary key`
- `code text unique not null`
- `description text not null`
- `action_level text check (action_level in ('read','prepare','execute'))`
- `data_class text not null`
- `active boolean not null default true`
- `created_at timestamptz not null default now()`

### `hq.ai_role_tools`

- `role_id uuid references hq.roles(id)`
- `tool_id uuid references hq.ai_tool_registry(id)`
- `platform_id uuid references hq.platforms(id)`
- `allowed boolean not null default true`
- chave única `(role_id, tool_id, platform_id)`

### `hq.ai_requests`

- `id uuid primary key`
- `auth_user_id uuid not null`
- `employee_id uuid references hq.employees(id)`
- `role_code text not null`
- `department_code text`
- `platform_slug text`
- `session_id text`
- `request_source text not null`
- `question text not null`
- `tool_codes text[] not null default '{}'`
- `data_scope jsonb not null default '{}'`
- `model_used text`
- `tokens_used integer`
- `latency_ms integer`
- `status text not null`
- `created_at timestamptz not null default now()`

### `hq.ai_responses`

- `id uuid primary key`
- `request_id uuid references hq.ai_requests(id)`
- `response_text text not null`
- `confidence numeric`
- `citations jsonb not null default '[]'`
- `action_level text not null`
- `created_at timestamptz not null default now()`

### `hq.ai_drafts`

- `id uuid primary key`
- `request_id uuid references hq.ai_requests(id)`
- `draft_type text not null`
- `payload jsonb not null`
- `approved_payload jsonb`
- `status text not null default 'pending_review'`
- `reviewed_by uuid references hq.employees(id)`
- `reviewed_at timestamptz`
- `created_at timestamptz not null default now()`

## 5. RBAC e segurança

Antes de qualquer ferramenta existe uma camada obrigatória de **policy enforcement**. A seleção proposta pelo modelo nunca concede autorização.

```text
Modelo propõe ferramenta → Gateway valida → RBAC valida utilizador
→ Policy Engine valida data_class + scope → servidor executa
→ resultado reduzido/filtrado → modelo recebe apenas o necessário
```

Todas as ferramentas exigem timeouts, limites de linhas, paginação e filtros obrigatórios.

Ações proibidas na Fase 1: `approve_kyc`, `reject_kyc`, `transfer_funds`, `withdraw_funds`, `change_wallet`, `suspend_account`, `delete_user`, `change_role`, `change_permissions`, `approve_payroll`, `approve_expense` e `publish_sensitive_document`.

O Gateway deve aplicar, pela ordem:

1. sessão Auth válida;
2. trabalhador ativo;
3. role e departamento;
4. plataformas autorizadas;
5. ferramenta autorizada;
6. classificação de dados;
7. nível de ação permitido.

Super Admin não ignora auditoria. O acesso amplo permite consulta, mas cada ferramenta e resultado continuam registados.

## 6. Support AI

Funções iniciais:

- classificar ticket por plataforma, categoria e prioridade;
- resumir histórico;
- identificar sentimento e urgência como apoio, não decisão final;
- sugerir resposta;
- incluir assinatura automática do trabalhador após revisão;
- encaminhar para o departamento adequado.

Fluxo:

```text
Mensagem → classificação → resumo → resposta sugerida
         → trabalhador revê/edita → envia
         → assinatura → histórico e auditoria
```

## 7. Interface da Central

Adicionar no layout principal:

- botão permanente **✨ DeliGo AI**;
- painel de chat/copilot;
- seletor de âmbito: empresa, plataforma ou departamento;
- cartões de ferramentas disponíveis;
- respostas com fontes e data dos dados;
- área de rascunhos pendentes de revisão;
- indicação visual do nível: leitura ou preparação;
- ligação para auditoria.

O painel deve respeitar o baseline visual existente da Central: sidebar, header, cards, cores e espaçamento atuais.

## 8. AI Audit Log

Registar:

- `request_id`;
- utilizador e trabalhador;
- role, departamento e plataforma;
- pergunta normalizada;
- ferramentas usadas;
- âmbito de dados;
- modelo, tokens e latência;
- resposta ou referência ao rascunho;
- nível de ação;
- resultado e erro, se existir;
- data/hora.

Não registar passwords, OTPs, tokens, chaves, dados pessoais desnecessários ou conteúdo integral de documentos sensíveis.

## 9. Critérios de aceitação

- Uma pergunta sem permissão é recusada antes da chamada ao modelo.
- Uma ferramenta só consulta o âmbito autorizado.
- Toda resposta gera `ai_request` e `ai_response` auditáveis.
- Rascunhos exigem revisão humana.
- Nenhuma ação de Nível 3 é executável na Fase 1.
- O Support AI sugere respostas, mas o trabalhador confirma e assina.
- Anwar, Sara e um trabalhador comum obtêm resultados diferentes conforme os seus roles.
- Falhas do modelo não interrompem o suporte nem alteram dados.

## 10. Ordem de implementação

1. migração de tabelas e registo de ferramentas;
2. serviço Gateway e verificação RBAC;
3. endpoints de leitura;
4. interface Copilot na Central;
5. Support AI e respostas sugeridas;
6. auditoria, testes de segurança e validação ponta a ponta.
