begin;
-- Extend the provider taxonomy without storing credentials in the database.
alter table core.integration_providers
  drop constraint if exists integration_providers_category_check;
alter table core.integration_providers
  add constraint integration_providers_category_check
  check (category in (
    'maps', 'push', 'sms', 'mobile_money', 'edge_security',
    'object_storage', 'media', 'ai', 'content_api', 'gateway',
    'cache', 'queue', 'search', 'routing', 'geocoding',
    'observability', 'email', 'database_extension'
  ));
insert into core.integration_providers (
  code, category, provider_name, environment, status,
  secret_reference, capabilities, public_config, metadata
)
values
  ('gateway_kong', 'gateway', 'Kong Gateway', 'staging', 'planned',
   'KONG_GATEWAY_ADMIN_TOKEN',
   array['jwt_validation', 'api_keys', 'oauth', 'route_versioning', 'internal_rate_limits'],
   '{"role":"edge_gateway","cutover":"allowlisted_routes_only"}',
   '{"activation_gate":"custom_staging_domain_and_route_tests"}'),
  ('cache_redis', 'cache', 'Redis-compatible cache', 'staging', 'planned',
   'REDIS_URL',
   array['derived_cache', 'rate_limit_counters', 'short_lived_locks'],
   '{"tls_required":true,"authoritative_store":"postgres"}',
   '{"activation_gate":"ttl_eviction_and_fail_open_tests"}'),
  ('queue_cloudamqp', 'queue', 'CloudAMQP', 'staging', 'planned',
   'CLOUDAMQP_URL',
   array['async_jobs', 'outbox_consumers', 'retry_queues'],
   '{"financial_messages":"disabled"}',
   '{"activation_gate":"dead_letter_and_idempotency_tests"}'),
  ('search_algolia', 'search', 'Algolia', 'staging', 'planned',
   'ALGOLIA_ADMIN_API_KEY',
   array['restaurants', 'products', 'stores', 'churches', 'campaigns'],
   '{"indexing":"outbox_only","client_key":"search_only"}',
   '{"activation_gate":"tenant_isolation_and_delete_sync_tests"}'),
  ('routing_graphhopper', 'routing', 'GraphHopper', 'staging', 'planned',
   'GRAPHHOPPER_API_KEY',
   array['directions', 'eta', 'route_optimization'],
   '{"role":"secondary_routing"}',
   '{"activation_gate":"mozambique_coverage_and_cost_test"}'),
  ('routing_optimo_route', 'routing', 'OptimoRoute', 'staging', 'planned',
   'OPTIMOROUTE_API_KEY',
   array['fleet_optimization', 'multi_stop_planning'],
   '{"role":"batch_operations_only"}',
   '{"activation_gate":"dispatch_simulation_and_data_processing_review"}'),
  ('geocoding_nominatim', 'geocoding', 'Nominatim', 'staging', 'planned',
   null,
   array['geocoding', 'reverse_geocoding'],
   '{"role":"development_fallback","client_direct_access":false}',
   '{"activation_gate":"usage_policy_and_hosted_service_decision"}'),
  ('database_pgvector', 'database_extension', 'pgvector', 'staging', 'planned',
   null,
   array['embeddings', 'semantic_search'],
   '{"execution":"postgres_extension","external_api":false}',
   '{"activation_gate":"schema_review_embedding_retention_and_rls_tests"}'),
  ('observability_opentelemetry', 'observability', 'OpenTelemetry', 'staging', 'planned',
   'OTEL_EXPORTER_OTLP_ENDPOINT',
   array['traces', 'metrics', 'structured_logs'],
   '{"pii":"redacted","sampling":"staging_first"}',
   '{"activation_gate":"redaction_and_trace_correlation_tests"}'),
  ('observability_sentry', 'observability', 'Sentry', 'staging', 'planned',
   'SENTRY_DSN',
   array['errors', 'performance_traces', 'release_health'],
   '{"pii":"disabled_by_default"}',
   '{"activation_gate":"scrubbing_and_release_tag_tests"}'),
  ('observability_posthog', 'observability', 'PostHog', 'staging', 'planned',
   'POSTHOG_PROJECT_API_KEY',
   array['product_analytics', 'feature_flags', 'funnels'],
   '{"identity":"pseudonymous","financial_events":"excluded"}',
   '{"activation_gate":"event_taxonomy_and_consent_review"}'),
  ('observability_better_stack', 'observability', 'Better Stack', 'staging', 'planned',
   'BETTERSTACK_SOURCE_TOKEN',
   array['uptime', 'logs', 'alerts'],
   '{"logs":"redacted"}',
   '{"activation_gate":"alert_routing_and_redaction_tests"}'),
  ('observability_grafana', 'observability', 'Grafana Cloud', 'staging', 'planned',
   'GRAFANA_CLOUD_STACK_CREDENTIALS',
   array['dashboards', 'metrics', 'alerts'],
   '{"scope":"staging"}',
   '{"activation_gate":"least_privilege_service_account"}'),
  ('email_resend', 'email', 'Resend', 'staging', 'planned',
   'RESEND_API_KEY',
   array['transactional_email', 'templates'],
   '{"sender_domain":"verification_required"}',
   '{"activation_gate":"domain_verification_and_webhook_signature_tests"}')
on conflict (code) do update
set category = excluded.category,
    provider_name = excluded.provider_name,
    secret_reference = excluded.secret_reference,
    capabilities = excluded.capabilities,
    public_config = excluded.public_config,
    metadata = excluded.metadata,
    updated_at = now();
insert into core.app_integrations (
  app_id, integration_provider_id, enabled, priority, settings
)
select app.id, provider.id, false, 100, '{}'::jsonb
from core.apps app
cross join core.integration_providers provider
where app.slug in ('deligo', 'sarca', 'taomoz', 'comunhao')
  and provider.code in (
    'gateway_kong', 'cache_redis', 'queue_cloudamqp', 'search_algolia',
    'routing_graphhopper', 'routing_optimo_route', 'geocoding_nominatim',
    'database_pgvector', 'observability_opentelemetry', 'observability_sentry',
    'observability_posthog', 'observability_better_stack', 'observability_grafana',
    'email_resend'
  )
on conflict (app_id, integration_provider_id) do nothing;
comment on table core.integration_providers is
  'Central provider catalogue. Credentials are never stored here; secret_reference names a secret managed outside the database.';
commit;
