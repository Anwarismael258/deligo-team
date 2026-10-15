begin;

insert into hq.permissions(code,module,action,data_class,description) values
 ('field.kyc.review','field','kyc_review','confidential','Analisar documentos e checklist KYC'),
 ('field.kyc.decide','field','kyc_decide','confidential','Aprovar, corrigir ou rejeitar KYC')
on conflict(code) do update set description=excluded.description;

-- Operações de Campo autorizadas por plataforma, sem TaoMoz.
insert into hq.platforms (legal_entity_id,slug,name,schema_name)
values ('10000000-0000-0000-0000-000000000001','corporate','DeliGo Triunfal / Corporativo','corporate')
on conflict(slug) do update set name=excluded.name;

commit;
