begin;

alter table hq.projects add column if not exists health_status text not null default 'on_track' check (health_status in ('on_track','at_risk','overdue','blocked'));
alter table hq.projects add column if not exists participating_department_ids jsonb not null default '[]'::jsonb;
alter table hq.projects add column if not exists committed_amount numeric(18,2) not null default 0 check (committed_amount >= 0);
alter table hq.projects add column if not exists paid_amount numeric(18,2) not null default 0 check (paid_amount >= 0);

insert into hq.permissions(code,module,action,data_class,description) values
 ('project.view','projects','view','internal','Consultar projetos'),
 ('project.create','projects','create','internal','Criar projetos'),
 ('project.manage','projects','manage','internal','Gerir projetos'),
 ('task.assign','projects','assign','internal','Atribuir tarefas'),
 ('project.budget.view','projects','budget_view','financial','Consultar orçamento de projetos'),
 ('project.admin','projects','admin','internal','Administrar portfólio de projetos')
on conflict(code) do update set description=excluded.description;

commit;
