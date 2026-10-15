begin;

alter table hq.internal_requests add column if not exists service_category text;
alter table hq.internal_requests add column if not exists service_subcategory text;
alter table hq.internal_requests add column if not exists sla_first_response_at timestamptz;
alter table hq.internal_requests add column if not exists sla_due_at timestamptz;
alter table hq.internal_requests add column if not exists first_responded_at timestamptz;
alter table hq.internal_requests add column if not exists satisfaction_score integer check (satisfaction_score is null or satisfaction_score between 1 and 5);

insert into hq.permissions(code,module,action,data_class,description) values
 ('internal.support.view','internal_support','view','internal','Consultar pedidos internos autorizados'),
 ('internal.support.create','internal_support','create','internal','Abrir pedido interno'),
 ('internal.support.manage','internal_support','manage','internal','Gerir fila de pedidos internos'),
 ('internal.support.notes','internal_support','notes','confidential','Consultar notas internas'),
 ('internal.support.admin','internal_support','admin','internal','Administrar service desk interno')
on conflict(code) do update set description=excluded.description;

create index if not exists idx_internal_requests_sla on hq.internal_requests(status,sla_due_at);

commit;
