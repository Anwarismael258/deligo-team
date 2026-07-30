# Auditoria funcional do HQ

## Contas verificadas

Em 30/07/2026, as 16 contas de teste autenticaram com sucesso no Supabase staging e devolveram o role esperado: `SUPER_ADMIN`, `FINANCE`, `SUPERVISOR`, três contas `FIELD`, `MARKETING`, `CUSTOMER_SUPPORT`, `ACCOUNTING`, `HUMAN_RESOURCES`, `LEGAL`, `OPERATIONS`, `PARTNER_ACQUISITION`, `AMBASSADOR`, `PROCUREMENT` e `ASSETS_LOGISTICS`.

## Confirmado

- autenticação por telefone e password;
- correspondência telefone/role das 16 contas;
- sessão corporativa e protecção server-side dos endpoints;
- dados consolidados do dashboard;
- gestão de trabalhadores e auditoria;
- leitura real de Marketing, Suporte, Field e KYC transversal;
- assumir e resolver tickets de suporte;
- pesquisa nas colecções operacionais.

## Falhas ou trabalho pendente

- gráficos corporativos ainda não são todos calculados pelo backend;
- botões Exportar e vários atalhos da página inicial ainda não executam acções;
- abas internas dos módulos de plataforma ainda são apresentação visual;
- criação/edição de campanhas, chat, uploads, mapas e tempo real ainda precisam de adaptação;
- decisões KYC devem chamar o fluxo nativo de cada plataforma;
- Finanças, Contabilidade, Jurídico, Compras, Património, Tecnologia, Aquisição e Embaixadores ainda possuem áreas preparadas sem CRUD integral;
- 2FA, alteração de password e gestão de dispositivos continuam desactivados.

## Correcção de segurança resultante

O selector `Ver como` passa a existir apenas para `SUPER_ADMIN`. Qualquer outro role que tente abrir directamente uma rota não atribuída é redireccionado para a visão geral. A autorização no servidor continua obrigatória e não depende desta protecção visual.
