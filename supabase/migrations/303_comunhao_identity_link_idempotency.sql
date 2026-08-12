-- Allow a legacy UUID to be tracked independently for each source project
-- while preserving the original app-level uniqueness constraint.
CREATE UNIQUE INDEX IF NOT EXISTS
  legacy_user_links_app_project_user_uidx
ON core.legacy_user_links (
  source_app_slug,
  source_project_ref,
  legacy_user_id
);
