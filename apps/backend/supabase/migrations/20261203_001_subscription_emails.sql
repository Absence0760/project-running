-- Transactional subscription emails: a Pro-purchase receipt and a
-- payment-failed dunning, on the existing `lifecycle_email` job kind
-- (decisions §121).
--
-- The welcome (20261202_001) fires from a user_profiles AFTER INSERT. These
-- two fire from an AFTER UPDATE on the same table, keyed off the columns the
-- RevenueCat webhook writes (20260729_001 billing_issue_at; subscription_tier
-- per 20260429_001):
--
--   * purchase  — subscription_tier enters a paid tier (free → pro/lifetime)
--                 → 'pro_welcome'. RENEWAL keeps tier=pro (no transition), so
--                 only the first purchase emails — renewal receipts are a
--                 later addition.
--   * dunning   — billing_issue_at goes null → non-null → 'payment_failed'.
--                 When the next RENEWAL clears it back to null, nothing fires.
--
-- A separate AFTER trigger from the BEFORE `lock_subscription_columns` guard
-- (20260624_001) — different phase, no conflict. RevenueCat (service_role) is
-- the only writer that can change these columns, so this fires exactly on
-- real billing transitions. Unlike the welcome, these are RECURRING (a
-- re-subscribe, a repeat billing failure), so the worker does NOT dedup them
-- via lifecycle_email_log — the trigger's transition guard is the dedupe.

create or replace function enqueue_subscription_emails()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Entered a paid tier from a non-paid one → purchase receipt.
  if new.subscription_tier in ('pro', 'lifetime')
     and (old.subscription_tier is null
          or old.subscription_tier not in ('pro', 'lifetime')) then
    insert into public.jobs (kind, payload)
    values ('lifecycle_email',
            jsonb_build_object('user_id', new.id::text, 'template', 'pro_welcome'));
  end if;

  -- Renewal failure newly flagged → dunning.
  if new.billing_issue_at is not null and old.billing_issue_at is null then
    insert into public.jobs (kind, payload)
    values ('lifecycle_email',
            jsonb_build_object('user_id', new.id::text, 'template', 'payment_failed'));
  end if;

  return new;
end;
$$;

revoke execute on function enqueue_subscription_emails() from public;

-- WHEN gates the trigger to rows where a relevant column actually changed, so
-- ordinary profile edits (name, prefs) never run the body.
create trigger user_profiles_enqueue_subscription_emails
  after update on user_profiles
  for each row
  when (
    old.subscription_tier is distinct from new.subscription_tier
    or old.billing_issue_at is distinct from new.billing_issue_at
  )
  execute function enqueue_subscription_emails();
