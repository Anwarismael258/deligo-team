BEGIN;
CREATE OR REPLACE FUNCTION public.notify_marketing_request_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id UUID;
  v_restaurant_name TEXT;
  v_marketing_user RECORD;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT owner_id, name
  INTO v_owner_id, v_restaurant_name
  FROM public.restaurants
  WHERE id = NEW.restaurant_id;

  IF v_owner_id IS NOT NULL AND NEW.status IN ('revision_requested', 'rejected', 'published') THEN
    PERFORM public.create_app_notification(
      p_user_id := v_owner_id,
      p_type := CASE NEW.status
        WHEN 'revision_requested' THEN 'MARKETING_EVENT_CHANGES_REQUESTED'
        WHEN 'rejected' THEN 'MARKETING_EVENT_REJECTED'
        ELSE 'MARKETING_EVENT_PUBLISHED'
      END,
      p_title := CASE NEW.status
        WHEN 'revision_requested' THEN 'O evento precisa de alteracoes'
        WHEN 'rejected' THEN 'Evento rejeitado pelo Marketing'
        ELSE 'Evento aprovado e publicado'
      END,
      p_body := CASE NEW.status
        WHEN 'revision_requested' THEN
          'O evento "' || NEW.event_name || '" precisa de ajustes. ' || COALESCE(NEW.revision_notes, '')
        WHEN 'rejected' THEN
          'O evento "' || NEW.event_name || '" foi rejeitado. Motivo: ' || COALESCE(NEW.revision_notes, 'Nao informado')
        ELSE
          'O evento "' || NEW.event_name || '" ja esta disponivel no DeliGo App.'
      END,
      p_action := 'OPEN_RESTAURANT_MARKETING',
      p_entity_id := NEW.id::text,
      p_priority := 'HIGH',
      p_channel := 'marketing',
      p_metadata := jsonb_build_object(
        'request_id', NEW.id,
        'restaurant_id', NEW.restaurant_id,
        'status', NEW.status,
        'revision_notes', NEW.revision_notes
      ),
      p_dispatch_key := 'marketing_request:' || NEW.id::text || ':' || NEW.status
    );
  END IF;

  IF NEW.status = 'received'
     AND OLD.status IN ('revision_requested', 'rejected') THEN
    FOR v_marketing_user IN
      SELECT id FROM public.profiles WHERE role = 'marketing_agent'
    LOOP
      PERFORM public.create_app_notification(
        p_user_id := v_marketing_user.id,
        p_type := 'MARKETING_EVENT_RESUBMITTED',
        p_title := 'Evento corrigido e reenviado',
        p_body := COALESCE(v_restaurant_name, 'Restaurante') ||
          ' reenviou o evento "' || NEW.event_name || '" para revisao.',
        p_action := 'OPEN_MARKETING_REQUEST',
        p_entity_id := NEW.id::text,
        p_priority := 'HIGH',
        p_channel := 'marketing',
        p_metadata := jsonb_build_object(
          'request_id', NEW.id,
          'restaurant_id', NEW.restaurant_id,
          'status', NEW.status
        ),
        p_dispatch_key := 'marketing_request:' || NEW.id::text || ':resubmitted:' || NEW.updated_at::text
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_marketing_request_status ON public.marketing_requests;
CREATE TRIGGER trg_notify_marketing_request_status
  AFTER UPDATE OF status ON public.marketing_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_marketing_request_status_change();
COMMIT;
