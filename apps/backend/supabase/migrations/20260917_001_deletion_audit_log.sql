-- audit/account-deletion-completeness (May 2026) recommended an
-- evidence trail so a regulator's "did you delete user X on date Y"
-- question can be answered after the auth row is gone.
--
-- We store a salted SHA-256 of the user id (so the log isn't itself
-- a directory of deleted accounts), the timestamp, and a short
-- machine-readable result code. Service-role only — there is no
-- legitimate read path from a user JWT.

create table public.deletion_audit_log (
  hashed_user_id text primary key
    check (hashed_user_id ~ '^[0-9a-f]{64}$'),
  deleted_at timestamptz not null default now(),
  result text not null
    check (result in (
      'ok',
      'storage_drain_failed',
      'auth_delete_failed',
      'reports_cleanup_failed',
      'vault_cleanup_failed'
    )),
  notes text check (notes is null or length(notes) <= 200)
);

create index deletion_audit_log_deleted_at
  on public.deletion_audit_log (deleted_at desc);

alter table public.deletion_audit_log enable row level security;

-- No SELECT policy: no user-side reads. Service-role bypasses RLS.
-- No INSERT/UPDATE policy: only the delete-account Edge Function
-- (service-role) writes to this table.

-- Defence in depth: no anon / authenticated grants either.
revoke all on public.deletion_audit_log from public, anon, authenticated;
grant select, insert on public.deletion_audit_log to service_role;
