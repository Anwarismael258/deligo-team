CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;
CREATE OR REPLACE FUNCTION public.send_sms_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, extensions
AS $$
DECLARE
  api_key text;
  api_secret text;
  sender_id text;
  target_phone text;
  otp_code text;
  sms_body text;
  request_headers extensions.http_header[];
  response_record record;
  response_json jsonb;
BEGIN
  SELECT decrypted_secret INTO api_key
  FROM vault.decrypted_secrets
  WHERE name = 'mozesms_api_key'
  ORDER BY updated_at DESC LIMIT 1;

  SELECT decrypted_secret INTO api_secret
  FROM vault.decrypted_secrets
  WHERE name = 'mozesms_api_secret'
  ORDER BY updated_at DESC LIMIT 1;

  SELECT decrypted_secret INTO sender_id
  FROM vault.decrypted_secrets
  WHERE name = 'mozesms_sender_id'
  ORDER BY updated_at DESC LIMIT 1;

  target_phone := coalesce(event->'user'->>'phone', '');
  otp_code := coalesce(event->'sms'->>'otp', '');

  IF target_phone = '' OR otp_code = '' THEN
    RETURN jsonb_build_object(
      'error',
      jsonb_build_object(
        'http_code', 400,
        'message', 'Phone number or OTP payload is missing.'
      )
    );
  END IF;

  IF coalesce(api_key, '') = '' OR coalesce(api_secret, '') = '' THEN
    RETURN jsonb_build_object(
      'error',
      jsonb_build_object(
        'http_code', 500,
        'message', 'MozeSMS credentials are not configured.'
      )
    );
  END IF;

  request_headers := array[
    row('X-API-Key', api_key)::extensions.http_header,
    row('X-API-Secret', api_secret)::extensions.http_header
  ]::extensions.http_header[];

  sms_body := format('DeliGo: o seu codigo de verificacao e %s', otp_code);

  SELECT * INTO response_record
  FROM extensions.http(
    (
      'POST',
      'https://api.mozesms.com/sms/send',
      request_headers,
      'application/json',
      jsonb_build_object(
        'phone', replace(target_phone, '+', ''),
        'message', sms_body,
        'sender_id', coalesce(nullif(sender_id, ''), 'DeliGo')
      )::text
    )::extensions.http_request
  );

  IF response_record.status < 200 OR response_record.status >= 300 THEN
    RETURN jsonb_build_object(
      'error',
      jsonb_build_object(
        'http_code', 500,
        'message', format('MozeSMS request failed with status %s.', response_record.status)
      )
    );
  END IF;

  IF coalesce(response_record.content, '') <> '' THEN
    BEGIN
      response_json := response_record.content::jsonb;
      IF coalesce((response_json->>'success')::boolean, true) IS NOT TRUE THEN
        RETURN jsonb_build_object(
          'error',
          jsonb_build_object(
            'http_code', 500,
            'message', coalesce(response_json->>'error', 'MozeSMS returned an application error.')
          )
        );
      END IF;
    EXCEPTION WHEN others THEN
      NULL;
    END;
  END IF;

  RETURN event;
END;
$$;
GRANT EXECUTE ON FUNCTION public.send_sms_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.send_sms_hook(jsonb)
  FROM anon, authenticated, service_role, PUBLIC;
