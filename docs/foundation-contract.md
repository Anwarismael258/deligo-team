# Contrato de fundação — Central Web

Este contrato prepara a integração sem activar qualquer backend.

## Identidade

- O identificador interno é imutável e segue `DG-0001`.
- O telefone em E.164 é o identificador de entrada actual, não a chave da pessoa.
- E-mail corporativo poderá ser acrescentado à mesma identidade.
- Não existe auto-registo: RH ou Super Administrador inicia o convite.
- Offboarding revoga o acesso sem apagar o histórico.

## Autenticação

1. Telefone e palavra-passe.
2. Segundo factor por Authenticator ou OTP autorizado.
3. Recuperação por OTP SMS ou códigos de recuperação.
4. Cargos críticos exigem política reforçada no servidor.

## Autorização

Cada decisão cruza:

`identidade + permissão + departamento + plataforma + entidade jurídica + validade`

O cargo nunca concede acesso sozinho. Conflitos de segregação de funções
bloqueiam a decisão mesmo quando existem grants individuais.

## Auditoria

Login, 2FA, decisões de acesso, alterações de permissões e aprovações geram
eventos correlacionados. O writer permanece congelado até existir armazenamento
de staging aprovado.

## Fora de escopo nesta fase

- tabelas e migrations;
- endpoints de autenticação;
- envio real de SMS;
- dados bancários, pagamentos e distribuição de lucros;
- ligação às bases de DeliGo, Comunhão, SARCA ou TaoMoz;
- secrets no frontend.

