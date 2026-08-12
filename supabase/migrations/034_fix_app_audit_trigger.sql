-- Fix app.audit_trigger to populate mandatory audit_log.entity
CREATE OR REPLACE FUNCTION app.audit_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  v_actor uuid;
  v_entity text;
  v_record uuid;
BEGIN
  BEGIN
    v_actor := current_setting('audit.actor', true)::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_actor := NULL;
  END;

  v_entity := TG_TABLE_NAME;
  v_record := COALESCE(NEW.id, OLD.id)::uuid;

  INSERT INTO app.audit_log(
    entity,
    entity_id,
    action,
    actor,
    payload,
    table_name,
    record_id,
    old_data,
    new_data
  )
  VALUES (
    v_entity,
    v_record,
    TG_OP,
    v_actor,
    jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW)),
    TG_TABLE_NAME,
    v_record,
    to_jsonb(OLD),
    to_jsonb(NEW)
  );

  RETURN COALESCE(NEW, OLD);
END;
$function$;
