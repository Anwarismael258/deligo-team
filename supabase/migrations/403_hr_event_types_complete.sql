-- Compatibility migration: complete labour event vocabulary before later HR patches.
alter table hq.hr_employee_events drop constraint if exists hr_employee_events_event_type_check;
alter table hq.hr_employee_events add constraint hr_employee_events_event_type_check check(event_type in ('admission','schedule','leave','payroll_benefit','benefit','performance_review','training','disciplinary','promotion','transfer','separation'));
notify pgrst, 'reload schema';
