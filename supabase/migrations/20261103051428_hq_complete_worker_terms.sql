begin;

update hq.worker_terms_versions
set body = jsonb_build_object(
  'intro', 'Estes termos definem a utilização profissional da Central HQ DeliGo Triunfal. Aplicam-se sem prejuízo do contrato, da legislação laboral e das regras de proteção de dados aplicáveis em Moçambique.',
  'sections', jsonb_build_array(
    jsonb_build_object('title','Identidade e missão','text','A DeliGo Triunfal coordena a operação de plataformas digitais e serviços integrados através da Central HQ. O trabalhador deve atuar de forma profissional, segura, rastreável e dentro do cargo que lhe foi atribuído.'),
    jsonb_build_object('title','Departamentos e responsabilidades','text','O CEO define a direção e toma decisões finais; Finanças trata receitas, despesas e reconciliação; o Supervisor distribui trabalho e acompanha a equipa; Apoio ao Cliente atende e responde aos utilizadores; Marketing prepara campanhas, conteúdos e comunicação institucional; Campo realiza visitas, recolhe documentos e submete verificações KYC.'),
    jsonb_build_object('title','Benefícios, remuneração e direitos','text','Remuneração, benefícios, horários, férias e demais direitos dependem do vínculo profissional, dos documentos aplicáveis e da legislação vigente. Estes termos não substituem contrato de trabalho, prestação de serviços ou qualquer obrigação legal.'),
    jsonb_build_object('title','Confidencialidade e proteção de dados','text','Informações de clientes, trabalhadores, parceiros, documentos, operações, finanças e credenciais são confidenciais. O acesso deve limitar-se à finalidade profissional autorizada e aos dados necessários para a função.'),
    jsonb_build_object('title','Contas e credenciais','text','É proibido partilhar palavras-passe, códigos OTP, sessões, tokens ou links internos. O trabalhador não pode consultar, copiar, exportar ou alterar dados sem autorização e deve comunicar imediatamente qualquer acesso suspeito.'),
    jsonb_build_object('title','Operações administrativas e financeiras','text','Cada cargo responde pelas operações da sua área. Movimentos financeiros, levantamentos, aprovações, alterações de permissões e ações críticas seguem os fluxos de dupla aprovação, auditoria e segregação de funções configurados na Central.'),
    jsonb_build_object('title','Atendimento, reclamações e incidentes','text','Pedidos, reclamações, incidentes e alertas devem ser registados nos canais oficiais, encaminhados ao responsável e tratados com informação fiel. Não se devem apagar provas, ocultar falhas ou prometer resultados que não estejam confirmados.'),
    jsonb_build_object('title','Promoção, suspensão e cessação de acesso','text','Promoções, despromoções, suspensões e encerramentos são decisões autorizadas e ficam registados. No encerramento, a Central revoga os acessos sob controlo da empresa, preserva o histórico e produz o documento oficial de encerramento.'),
    jsonb_build_object('title','Investigação e resolução de conflitos','text','A empresa pode conservar registos de auditoria, acessos, tarefas e operações necessários para investigar incidentes e resolver conflitos. O acesso a esses registos é limitado aos responsáveis autorizados e às finalidades legítimas.'),
    jsonb_build_object('title','Denúncias e direitos do trabalhador','text','Irregularidades podem ser comunicadas ao Supervisor, ao CEO ou ao canal interno indicado pela empresa. O trabalhador pode exercer os direitos aplicáveis sobre os seus dados pessoais e solicitar esclarecimentos sobre decisões que lhe digam respeito.'),
    jsonb_build_object('title','Aceitação expressa','text','A leitura deve ser concluída até ao último parágrafo. Chegar ao fim não constitui aceitação automática: a aceitação só é registada depois de o trabalhador marcar a confirmação expressa e clicar em “Aceitar termos”.')
  )
)
where version = '1.0';

commit;
