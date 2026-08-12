-- Remove legacy blueprint checks before installing live Comunhao rules.
BEGIN;
ALTER TABLE comunhao."church_subscriptions" DROP CONSTRAINT IF EXISTS "church_subscriptions_status_check";
ALTER TABLE comunhao."churches" DROP CONSTRAINT IF EXISTS "churches_status_check";
ALTER TABLE comunhao."donation_campaigns" DROP CONSTRAINT IF EXISTS "donation_campaigns_status_check";
ALTER TABLE comunhao."donation_campaigns" DROP CONSTRAINT IF EXISTS "donation_campaigns_target_amount_minor_check";
ALTER TABLE comunhao."donations" DROP CONSTRAINT IF EXISTS "donations_amount_minor_check";
ALTER TABLE comunhao."donations" DROP CONSTRAINT IF EXISTS "donations_status_check";
ALTER TABLE comunhao."event_registrations" DROP CONSTRAINT IF EXISTS "event_registrations_attendee_count_check";
ALTER TABLE comunhao."event_registrations" DROP CONSTRAINT IF EXISTS "event_registrations_status_check";
ALTER TABLE comunhao."events" DROP CONSTRAINT IF EXISTS "events_status_check";
ALTER TABLE comunhao."memberships" DROP CONSTRAINT IF EXISTS "memberships_status_check";
ALTER TABLE comunhao."ministry_members" DROP CONSTRAINT IF EXISTS "ministry_members_role_check";
ALTER TABLE comunhao."ministry_members" DROP CONSTRAINT IF EXISTS "ministry_members_status_check";
ALTER TABLE comunhao."subscription_plans" DROP CONSTRAINT IF EXISTS "subscription_plans_price_minor_check";
COMMIT;
