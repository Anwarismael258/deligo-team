# DeliGo Triunfal HQ v16

## Base visual

- Mantém o dashboard claro original e o login corporativo com painel escuro.
- Mantém a navegação por departamentos, cartões das quatro plataformas e layout responsivo.
- Não apresenta dados técnicos do gateway nem telas experimentais ao utilizador final.

## Operações

- Mantém autenticação, roles, auditoria e administração de colaboradores.
- Mantém a fila KYC transversal para DeliGo, Comunhão, SARCA e TaoMoz.
- Acrescenta galeria de documentos e fotos KYC com suporte a documentos privados.
- Disponibiliza gateway server-side para os backends das quatro plataformas.

## Configuração

As integrações usam `DELIGO_SUPABASE_URL`, `COMUNHAO_SUPABASE_URL`, `SARCA_SUPABASE_URL` e `TAOMOZ_SUPABASE_URL`. Se uma variável não existir, o HQ usa o backend de staging partilhado configurado em `SUPABASE_URL`.
