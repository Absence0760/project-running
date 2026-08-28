-- Class guard for the column-level SELECT lockdowns: which public tables
-- withhold which columns from anon + authenticated, and why.
--
-- Six tables revoke table-level SELECT from anon/authenticated and re-grant
-- column by column (user_profiles 20260707_001 + 20260810_001, clubs + events
-- 20260818_001 redoing 20260801_001 / 20260723_001 / 20260806_001,
-- checkpoint_crossings 20270201_001, donations + instructor_payout_accounts
-- 20270621_001, matrix re-asserted by 20270408_001). Every withholding below
-- is a security decision with a named replacement read path, not an accident
-- of reaching for `grant select (a, b, c)`.
--
-- The last two arrived seventeen months late because the shape has a third
-- failure mode, the one 20260707_001's own header warns about: writing the
-- revoke at COLUMN level. `revoke select (col) on t from authenticated` while
-- authenticated holds a table-level SELECT reports REVOKE, creates no column
-- ACL, and changes nothing — Postgres resolves a privilege from the broadest
-- grant. 20261229_001 and 20270213_001 both did that and both described it as
-- defence in depth; on instructor_payout_accounts, whose own-row SELECT policy
-- is permissive, the host could read their raw Stripe Connect account id for
-- as long as the table existed. Nothing detected it, because a no-op revoke
-- leaves attacl null and this registry's assertion (2) only sees tables that
-- DO carve columns out. What detects it now is a static guard over the
-- migrations tree, apps/backend/scripts/check_migration_column_revoke_noop.mjs
-- (decisions.md 779); the registry's job is the state, not the statement.
--
-- The shape has one real failure mode and it has fired in prod twice. A
-- re-grant is CUMULATIVE, so a column added to one of these tables after its
-- lockdown is deny-by-default until an explicit `grant select (col)` lands —
-- and nothing failed at CI when one did not. `clubs.is_verified` (20260909_001)
-- shipped ungranted and took down every non-service-role read of `clubs` with
-- 42501; it was caught by eleven api_client integration failures a day later
-- and repaired by 20260913_001, whose header records the same for
-- `search_clubs`. `20260817_001` had already reverted the whole lockdown once
-- for the sibling reason. The `select('*')` source scans
-- (architecture_guards_test.dart, select-star-discipline.spec.ts) catch the
-- call-site half of that class; nothing caught the grant half.
--
-- So the registry is pinned in the direction that detects it: the WITHHELD set,
-- not the granted set. A new column that nobody granted enlarges the withheld
-- set and fails here. Pinning the granted set instead would not move at all,
-- which is exactly how the defect stayed silent.
--
-- The same assertion closes three more:
--   * a deliberately withheld column being granted (invite_token, meet_lat,
--     date_of_birth, body_weight_kg leaking to every caller),
--   * a table-wide `grant select` landing on a locked table, which empties the
--     withheld set — the "fix" that reads as correct to anything reasoning from
--     `has_table_privilege(role, tbl, 'SELECT') = false` alone. That predicate
--     is false on all four tables while `select count(*)` succeeds, because
--     Postgres checks column privileges for the columns a query names. It is
--     not evidence of a defect,
--   * a registry entry left behind by a dropped or renamed column.
--
-- What column-level grants DO cost, measured rather than assumed: a direct
-- `select xmin/ctid/tableoid from <table>` by anon or authenticated raises
-- 42501, because a per-column grant enumerates user columns only. An RLS policy
-- USING expression referencing xmin is unaffected — policy expressions are not
-- column-privilege-checked, only the columns the caller's own query names are —
-- so the refusal-assertion mutation operator (decisions.md 751/753) reads these
-- four tables normally. Verified against this Postgres before this test was
-- written; see decisions.md 759.

begin;

select plan(4);

create temporary table lockdown_registry (tbl name, col name, reason text);

insert into lockdown_registry (tbl, col, reason) values
  -- checkpoint_crossings — 20270201_001. Organiser reads go through
  -- fetch_checkpoint_crossings_for_organiser(), SECURITY DEFINER.
  ('checkpoint_crossings', 'body_weight_kg',       'Art 9 health data (weigh-in)'),
  ('checkpoint_crossings', 'body_weight_pct',      'Art 9 health data (weigh-in delta)'),
  ('checkpoint_crossings', 'medical_hold',         'Art 9 health data (medical hold flag)'),
  ('checkpoint_crossings', 'medical_note',         'Art 9 health data (free-text medical note)'),
  ('checkpoint_crossings', 'recorded_by',          'identifies the volunteer who logged the crossing; no client read site'),

  -- clubs — 20260801_001, redone by 20260818_001.
  ('clubs',                'invite_token',         'join secret; anon could enumerate every public club token and defeat join_policy=invite. Admin reads go through get_club_invite_token()'),

  -- events — 20260723_001 (anon) + 20260806_001 (authenticated), redone by
  -- 20260818_001; host_user_id arrived ungranted with 20261227_001/20261229_001.
  ('events',               'meet_lat',             'precise meet-point coordinate; read through get_event_meet_point() after a visibility check'),
  ('events',               'meet_lng',             'precise meet-point coordinate; read through get_event_meet_point() after a visibility check'),
  ('events',               'host_user_id',         'Stripe Connect payout recipient; no client read site (also pinned by event_gym_template_grants_test)'),

  -- donations — 20270621_001, making 20270213_001's column revoke real. The
  -- table carries NO permissive client SELECT policy: every client read is
  -- fundraiser_feed / fundraiser_totals, both SECURITY DEFINER, so nothing
  -- here has a client read site and the whole set is defence in depth against
  -- a permissive policy landing later. refunded_cents + client_request_id are
  -- withheld because they arrived after the lockdown was meant to exist and a
  -- re-grant is cumulative, and for the reasons below.
  ('donations',            'donor_user_id',        'donor identity; the feed serves a display name, never the account behind it'),
  ('donations',            'owner_user_id',        'the fundraiser owner receiving the money; joined from fundraisers where a client may read it'),
  ('donations',            'display_name',         'fundraiser_feed nulls this on an is_anonymous row and a column grant cannot be conditional on the row — granting it hands the client the name the feed exists to hide'),
  ('donations',            'stripe_checkout_session_id', 'Stripe object reference on the donor payment'),
  ('donations',            'stripe_payment_intent_id',   'Stripe object reference on the donor payment'),
  ('donations',            'platform_fee_cents',   'our cut of the donation; the feed reports what the charity kept'),
  ('donations',            'refunded_cents',       'the refund ledger figure; the feed reports the NET (amount - refunded) and never the components'),
  ('donations',            'client_request_id',    'the donor client''s per-attempt idempotency key; resolved only by donations-checkout under the service role'),

  -- instructor_payout_accounts — 20270621_001, making 20261229_001's column
  -- revoke real. The own-row SELECT policy stays; the capability boolean the
  -- payout UI needs is host_can_take_payment(), SECURITY DEFINER.
  ('instructor_payout_accounts', 'stripe_connect_account_id', 'identifies the host''s Stripe merchant account; 20261229_001 says even the own-row policy must not hand the client the raw id'),

  -- user_profiles — 20260707_001, narrowed by 20260810_001. Self-reads go
  -- through get_my_profile(), SECURITY DEFINER, which returns the full row.
  ('user_profiles',        'subscription_tier',    'billing discriminator; paywall reconnaissance'),
  ('user_profiles',        'subscription_at',      'billing state'),
  ('user_profiles',        'tier_updated_event_ts','billing state'),
  ('user_profiles',        'billing_issue_at',     'billing state'),
  ('user_profiles',        'parkrun_number',       'permanent real-world identity link'),
  ('user_profiles',        'preferred_unit',       'localisation reconnaissance — km/mi telegraphs a region (20260810_001)'),
  ('user_profiles',        'date_of_birth',        'Art 9 / special category; health use is separately consent-gated'),
  ('user_profiles',        'gender',               'Art 9 / special category'),
  ('user_profiles',        'height_cm',            'Art 9 / special category'),
  ('user_profiles',        'health_data_consent_at','consent state; self-read only'),
  ('user_profiles',        'coach_consent_at',     'consent state; self-read only'),
  ('user_profiles',        'ai_disclosure_version','consent state; self-read only'),
  ('user_profiles',        'terms_accepted_at',    'consent state; self-read only'),
  ('user_profiles',        'age_confirmed_at',     'age-gate state; self-read only'),
  ('user_profiles',        'onboarded_at',         'account lifecycle state; self-read only'),
  ('user_profiles',        'shadow_hidden',        'moderation state; disclosing it to the subject defeats shadow-hiding');

-- (1) The registry IS the withheld map, in both directions and for both roles.
select is(
  (with roles(role) as (values ('anon'::name), ('authenticated'::name)),
        withheld as (
          select r.role, cl.relname as tbl, a.attname as col
            from roles r
            join pg_class cl on cl.relkind in ('r', 'p')
            join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
            join pg_attribute a on a.attrelid = cl.oid and a.attnum > 0 and not a.attisdropped
           where cl.relname in (select distinct tbl from lockdown_registry)
             and not has_column_privilege(r.role, cl.oid, a.attnum, 'SELECT')
        ),
        registered as (
          select r.role, g.tbl, g.col from lockdown_registry g cross join roles r
        )
   select coalesce(string_agg(offence, ', ' order by offence), '')
     from (
       select coalesce(w.role, g.role) || ': '
              || coalesce(w.tbl, g.tbl) || '.' || coalesce(w.col, g.col)
              || case when g.col is null
                      then ' is withheld but not in the registry — a column added'
                           || ' after the lockdown is deny-by-default until an'
                           || ' explicit grant lands; grant it, or register the reason'
                      else ' is in the registry but readable — a deliberate'
                           || ' withholding was granted away, or a table-wide'
                           || ' `grant select` landed on a locked table' end as offence
         from withheld w
         full join registered g
           on g.role = w.role and g.tbl = w.tbl and g.col = w.col
        where w.col is null or g.col is null
     ) offences),
  '',
  'the column-SELECT lockdowns withhold exactly the registered columns from '
  'anon + authenticated — no column drifted in ungranted, and no registered '
  'withholding was granted away'
);

-- (2) No OTHER public table carries the per-column SELECT shape. A fifth table
-- reaching for `grant select (a, b, c)` has to declare itself here with the
-- reason each column is withheld, or it is an accident.
select is(
  (select coalesce(string_agg(distinct cl.relname || ' (' || r.role || ')', ', '), '')
     from pg_class cl
     join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
     join pg_attribute a on a.attrelid = cl.oid and a.attnum > 0 and not a.attisdropped
                        and a.attacl is not null
     cross join (values ('anon'::name), ('authenticated'::name)) r(role)
    where cl.relkind in ('r', 'p')
      and cl.relname not in (select distinct tbl from lockdown_registry)
      and exists (select 1 from aclexplode(a.attacl) ae
                   where ae.grantee = (select oid from pg_roles where rolname = r.role)
                     and ae.privilege_type = 'SELECT')),
  '',
  'no public table outside the registry grants SELECT per column — a new '
  'per-column grant is either a lockdown that belongs in the registry with '
  'its reason, or a table-wide grant written the long way'
);

-- (3) The lockdown itself is intact: table-level SELECT stays revoked, so the
-- per-column carve-out is what is actually gating reads.
select is(
  (select coalesce(string_agg(t.tbl || ' (' || r.role || ')', ', ' order by t.tbl, r.role), '')
     from (select distinct tbl from lockdown_registry) t
     cross join (values ('anon'::name), ('authenticated'::name)) r(role)
    where has_table_privilege(r.role, ('public.' || t.tbl)::regclass, 'SELECT')),
  '',
  'no column-locked table has regained table-level SELECT for anon or '
  'authenticated — that would grant every withheld column at once'
);

-- (4) The two roles are held identical on these tables. They have diverged
-- before (20260723_001 revoked the meet point from anon; 20260806_001 caught
-- authenticated up eleven weeks later), and a divergence is a leak on the
-- wider side rather than a variant worth carrying silently.
select is(
  (select coalesce(string_agg(cl.relname || '.' || a.attname, ', '
                              order by cl.relname, a.attname), '')
     from pg_class cl
     join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
     join pg_attribute a on a.attrelid = cl.oid and a.attnum > 0 and not a.attisdropped
    where cl.relname in (select distinct tbl from lockdown_registry)
      and has_column_privilege('anon', cl.oid, a.attnum, 'SELECT')
       <> has_column_privilege('authenticated', cl.oid, a.attnum, 'SELECT')),
  '',
  'anon and authenticated are granted the same columns on every '
  'column-locked table'
);

select * from finish();
rollback;
