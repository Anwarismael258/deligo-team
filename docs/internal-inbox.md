# Inbox interna da Central HQ

Acessível a todos os trabalhadores com sessão activa, independentemente do cargo. A comunicação foi retirada do Centro de Notificações e colocada no menu Inbox interna. A caixa institucional de email mantém o seu funcionamento.

## Activação

1. No Supabase correspondente a `SUPABASE_URL` da Vercel, executar `supabase/migrations/486_hq_internal_messenger.sql` no SQL Editor. A migração cria as tabelas, as funções de conversas e o bucket privado `hq-internal-inbox`. Não inclui alterações destrutivas de dados existentes.
2. Publicar a branch `main` na Vercel. Mantém as variáveis `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SECRET_KEY` ou `SUPABASE_SERVICE_ROLE_KEY` já utilizadas pela Central.
3. Opcional: definir `HQ_MEET_BASE_URL` para a origem HTTPS de uma instância Jitsi própria. Sem configuração utiliza `https://meet.jit.si`; o organizador poderá ter de se autenticar no Jitsi para abrir a reunião. A sala tem um identificador aleatório e é partilhada com a conversa. A autorização da Central protege o convite; a admissão na chamada é controlada pelo Jitsi, não pela sessão da Central.

## Funcionamento

- Conversas individuais reutilizam a mesma conversa entre duas pessoas. Grupos podem reunir destinatários seleccionados ou todos os trabalhadores activos no momento da criação (até 500 participantes). Novas contratações não entram retroactivamente nos grupos.
- Mensagens persistentes, respostas a mensagens, histórico paginado, contagem de não lidas e confirmação de leitura por todos. Actualização a cada 5 segundos enquanto a página estiver visível, e ao recuperar o foco.
- Até 5 anexos por mensagem, 3 MB por ficheiro. Imagens JPG/PNG/WEBP, PDF, TXT, CSV, DOCX, XLSX, PPTX, MP3, OGG e MP4. O limite evita exceder o corpo permitido numa Function Vercel.
- Anexos no bucket privado; as ligações de download são emitidas só após verificar a participação na conversa e expiram em 60 segundos. Ficheiros enviados mas retirados do rascunho permanecem privados e não associados; a limpeza periódica desses órfãos pode ser acrescentada posteriormente.
- A aplicação não concede a administradores acesso automático às conversas alheias. Cada leitura, envio, resposta, anexo e reunião verifica a sessão e os participantes. Não há criação por cargo privilegiado: qualquer trabalhador activo pode conversar.
- Reuniões abrem por iframe com alternativa de nova janela, usam a câmara/microfone apenas após a autorização do navegador e permitem partilha de ecrã conforme o Jitsi e o navegador.

## Verificação após publicação

Com duas contas activas de cargos diferentes: criar conversa, enviar e responder, verificar não lidas, anexar e descarregar um PDF, tentar abrir o anexo com uma terceira conta não participante (deve falhar), criar grupo da equipa e iniciar reunião nos dois navegadores. A migração precisa de ser aplicada antes deste teste; o deploy de código não a executa automaticamente.
