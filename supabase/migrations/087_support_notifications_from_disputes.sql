BEGIN;
CREATE OR REPLACE FUNCTION public.trg_notify_support_updates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_client_id uuid;
  v_body text;
BEGIN
  SELECT COALESCE(client_id, customer_id)
  INTO v_client_id
  FROM public.orders
  WHERE id = COALESCE(NEW.order_id, OLD.order_id);

  IF v_client_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.opened_by_role, '') <> 'client' THEN
      PERFORM public.create_app_notification(
        p_user_id := v_client_id,
        p_type := 'SUPPORT_UPDATED',
        p_title := 'Suporte atualizado 💬',
        p_body := 'Existe uma nova atualização no suporte do seu pedido.',
        p_action := 'OPEN_SUPPORT',
        p_entity_id := NEW.order_id::text,
        p_priority := 'HIGH',
        p_channel := 'support',
        p_metadata := jsonb_build_object(
          'order_id', NEW.order_id,
          'dispute_id', NEW.id,
          'status', NEW.status,
          'dispute_type', NEW.dispute_type
        )
      );
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF COALESCE(NEW.status, '') IN ('resolved', 'closed') AND COALESCE(OLD.status, '') <> COALESCE(NEW.status, '') THEN
      v_body := CASE
        WHEN COALESCE(NEW.resolution, '') <> '' THEN 'O seu ticket foi resolvido: ' || NEW.resolution
        ELSE 'O seu ticket de suporte foi resolvido.'
      END;

      PERFORM public.create_app_notification(
        p_user_id := v_client_id,
        p_type := 'TICKET_RESOLVED',
        p_title := 'Ticket resolvido ✅',
        p_body := v_body,
        p_action := 'OPEN_SUPPORT',
        p_entity_id := NEW.order_id::text,
        p_priority := 'HIGH',
        p_channel := 'support',
        p_metadata := jsonb_build_object(
          'order_id', NEW.order_id,
          'dispute_id', NEW.id,
          'status', NEW.status,
          'resolution', NEW.resolution
        )
      );
    ELSIF (
      COALESCE(NEW.status, '') <> COALESCE(OLD.status, '')
      OR COALESCE(NEW.resolution, '') <> COALESCE(OLD.resolution, '')
      OR COALESCE(NEW.updated_at, NOW()) <> COALESCE(OLD.updated_at, NOW())
    ) THEN
      PERFORM public.create_app_notification(
        p_user_id := v_client_id,
        p_type := 'SUPPORT_UPDATED',
        p_title := 'Suporte atualizado 💬',
        p_body := 'Existe uma nova atualização no suporte do seu pedido.',
        p_action := 'OPEN_SUPPORT',
        p_entity_id := NEW.order_id::text,
        p_priority := 'HIGH',
        p_channel := 'support',
        p_metadata := jsonb_build_object(
          'order_id', NEW.order_id,
          'dispute_id', NEW.id,
          'status', NEW.status,
          'resolution', NEW.resolution
        )
      );
    END IF;

    RETURN NEW;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_support_updates_ins ON public.order_disputes;
CREATE TRIGGER trg_notify_support_updates_ins
AFTER INSERT ON public.order_disputes
FOR EACH ROW
EXECUTE FUNCTION public.trg_notify_support_updates();
DROP TRIGGER IF EXISTS trg_notify_support_updates_upd ON public.order_disputes;
CREATE TRIGGER trg_notify_support_updates_upd
AFTER UPDATE ON public.order_disputes
FOR EACH ROW
EXECUTE FUNCTION public.trg_notify_support_updates();
COMMIT;
