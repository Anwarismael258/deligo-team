# Nominalia IMAP da Caixa de Entrada

O sincronizador usa apenas variáveis de ambiente do servidor. Nenhuma palavra-passe fica no código ou no browser.

## Variáveis de produção

```text
NOMINALIA_IMAP_HOST=pop.securemail.pro
NOMINALIA_IMAP_PORT=993
NOMINALIA_IMAP_GERAL_USER=geral@deligotriunfal.site
NOMINALIA_IMAP_GERAL_PASSWORD=<segredo da Vercel>
NOMINALIA_IMAP_COMERCIAL_USER=comercial@deligotriunfal.site
NOMINALIA_IMAP_COMERCIAL_PASSWORD=<segredo da Vercel>
NOMINALIA_IMAP_CARREIRAS_USER=carreiras@deligotriunfal.site
NOMINALIA_IMAP_CARREIRAS_PASSWORD=<segredo da Vercel>
```

Adicionar os valores pela Vercel CLI ou pelo painel, sempre no ambiente Production. Não guardar estes valores em `.env` versionado e não os enviar no chat.

A ação **Sincronizar email** chama o endpoint autenticado `/api/inbox/sync`, lê até 50 mensagens recentes de cada INBOX por TLS, importa apenas mensagens cujo `Message-ID` ainda não exista e grava-as em `inbox_messages` com a área correspondente. As mensagens enviadas pela Central continuam em `Enviadas`.
