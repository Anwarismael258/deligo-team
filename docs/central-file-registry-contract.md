# Registo central de ficheiros

O HQ é o catálogo e ponto de auditoria dos documentos operacionais recebidos pelas quatro plataformas. O ficheiro continua no storage privado da aplicação de origem; o HQ guarda somente a referência imutável do objecto, metadados, classificação e ligação ao processo.

## Registar na Central

- KYC, documentos de empresa, condutor/driver, estafeta, vendedor e igreja.
- Anexos de tickets, disputas, fraude, incidentes, prova de entrega/viagem e logística.
- Contratos, documentos legais, comprovativos financeiros e evidências operacionais.
- Criativos de marketing publicados ou submetidos à aprovação.

## Não registar automaticamente

- Avatares, imagens temporárias de interface, cache e ficheiros sem ligação a processo.
- Conteúdo privado de conversa que não foi marcado como anexo de suporte, incidente ou disputa.
- URLs assinadas: o registo guarda `source_bucket` e `source_path`; a URL temporária é criada somente quando um funcionário autorizado pede acesso.

## Contrato de integração

Depois de concluir o upload privado, cada plataforma chama `hq.register_central_file_v1` com:

`platform_id`, origem, bucket, caminho, sujeito/processo, categoria, classificação, nome, tipo MIME, tamanho, hash e metadados.

O HQ usa o `platform_id` e a classificação para autorizar a listagem e gerar URL assinada pelo adaptador nativo da plataforma. Cada acesso deve criar um evento em `hq.central_file_access_events`.

## Classificação

- `operational`: prova de entrega/viagem, anexo de ticket e evidência de operação.
- `confidential`: contrato, ficheiro comercial, relatório financeiro e criativo não publicado.
- `restricted`: KYC, fraude, documento de identidade e material jurídico sensível.
