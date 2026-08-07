-- Pins migration 20270503_001 (length caps on every remaining user-writable
-- free-text column, decisions §548).
--
-- The valuable assertion here is the third one, and it is deliberately not a
-- list. Every prior caps migration enumerated its columns, so the guard could
-- only ever prove that the columns someone remembered are capped — which is why
-- §545's own count of what remained was low by twelve. This test re-derives the
-- population from the CATALOGUE at run time and fails if anything is uncapped
-- outside a named allowlist, so a future migration that adds an unbounded text
-- column fails here rather than in a report two rounds later.
--
-- The derivation must be catalogue-based rather than a read of the migration
-- files, for the three reasons §548 records: the schema spells the predicate
-- both `length(...)` and `char_length(...)`, a multi-clause `add column` hides
-- its later clauses from a line-oriented parse, and a column named inside a
-- non-enum CHECK (`event_results`' either-user-or-bib rule) is not bounded by
-- it.

begin;

select plan(9);

-- 1. Every length CHECK in the schema is VALIDATED, not merely present.
--    `20261124_001` added three that were still `convalidated = false` when
--    this round read the catalogue, two rounds after the defect was named.
select is(
  (select count(*)::int from pg_constraint
     where contype = 'c' and conname like '%\_len\_chk' and not convalidated),
  0,
  'no length CHECK is left NOT VALID'
);

-- 2. Population: the set this migration added really is there. A minimum
--    rather than an equality — a later round adding more caps must not have to
--    edit this number, but an empty or truncated set must not pass (§534).
select cmp_ok(
  (select count(*)::int from pg_constraint
     where contype = 'c' and conname like '%\_len\_chk'),
  '>=',
  59,
  'the schema carries at least the 59 length CHECKs 20270503_001 leaves behind'
);

-- 3. The derivation. Any user-writable text column with no length bound, other
--    than the one allowlisted exception, fails this.
select is(
  (
    with txt as (
      select c.relname tbl, a.attname col
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
      where n.nspname = 'public' and c.relkind = 'r'
        and format_type(a.atttypid, a.atttypmod) in ('text', 'character varying', 'citext')
    ),
    chk as (
      select c.relname tbl, a.attname col, string_agg(pg_get_constraintdef(k.oid), ' | ') def
      from pg_constraint k
      join pg_class c on c.oid = k.conrelid
      join pg_namespace n on n.oid = c.relnamespace
      join unnest(k.conkey) ck(attnum) on true
      join pg_attribute a on a.attrelid = c.oid and a.attnum = ck.attnum
      where k.contype = 'c' and n.nspname = 'public'
      group by 1, 2
    )
    select coalesce(string_agg(t.tbl || '.' || t.col, ', ' order by t.tbl, t.col), '')
    from txt t
    left join chk on chk.tbl = t.tbl and chk.col = t.col
    where coalesce(chk.def, '') !~* 'length'
      -- An enum membership bounds the value by construction.
      and coalesce(chk.def, '') !~ '= ANY \(ARRAY'
      -- So does a regex with an explicit quantifier or a fixed character run.
      and coalesce(chk.def, '') !~ '\{[0-9]+(,[0-9]*)?\}'
      and coalesce(chk.def, '') !~ '\^\[.*\]\[.*\]'
      -- And so does an equality to a single literal (`event_pricing.modality`).
      and coalesce(chk.def, '') !~ ('\(' || t.col || ' = ''')
      -- URL / slug / token / id / hash columns carry a shape check, not a cap;
      -- they are § 545's stated exclusion and stay one.
      and t.col !~ '(_url$|_path$|^slug$|_token$|_id$|^id$|_hash$|_cursor$|^email$)'
      -- Operational tables nothing user-authored reaches.
      and t.tbl not in (
        'jobs', 'webhook_events', 'rate_limits', 'deletion_audit_log',
        'lifecycle_email_log', 'app_quota', 'run_matched_tracks', 'device_tokens',
        'email_suppressions', 'job_worker_heartbeat', 'account_deletion_receipts',
        'public_recaps', 'instructor_payout_accounts', 'event_orders', 'coach_messages'
      )
  ),
  '',
  'every user-writable free-text column carries a length cap'
);

-- 4. Population for the derivation: it must be scanning a real schema. Without
--    this, a typo in the CTE that returned zero rows would satisfy assertion 3
--    while proving nothing at all — the exact failure §534 records.
select cmp_ok(
  (select count(*)::int from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and a.attnum > 0
       and not a.attisdropped
       and format_type(a.atttypid, a.atttypmod) = 'text'),
  '>=',
  200,
  'the derivation is scanning a populated catalogue, not an empty one'
);

-- 5-9. Functional probes. A constraint that exists and validates can still be
--      written against the wrong column, so exercise both sides of two caps
--      picked from opposite ends of the ladder.
insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values ('bbbbbbbb-cccc-dddd-eeee-ffffffff0001', 'freetextcaps@example.com', '',
        now(), '00000000-0000-0000-0000-000000000000', 'authenticated',
        'authenticated')
on conflict (id) do nothing;

select throws_ok(
  $$ insert into routes (user_id, name, distance_m, waypoints)
     values ('bbbbbbbb-cccc-dddd-eeee-ffffffff0001', repeat('r', 121), 5000,
             '[]'::jsonb) $$,
  '23514',
  null,
  'a 121-character route name is rejected'
);

select lives_ok(
  $$ insert into routes (id, user_id, name, distance_m, waypoints)
     values ('bbbbbbbb-cccc-dddd-eeee-ffffffff0002',
             'bbbbbbbb-cccc-dddd-eeee-ffffffff0001', repeat('r', 120), 5000,
             '[]'::jsonb) $$,
  'a route name at exactly the 120-character cap is accepted'
);

select is(
  (select char_length(name) from routes
     where id = 'bbbbbbbb-cccc-dddd-eeee-ffffffff0002'),
  120,
  'the at-cap route really stored its 120-character name'
);

select throws_ok(
  $$ update routes set description = repeat('d', 2001)
     where id = 'bbbbbbbb-cccc-dddd-eeee-ffffffff0002' $$,
  '23514',
  null,
  'an UPDATE past the description cap is rejected, not only an INSERT'
);

select lives_ok(
  $$ update routes set description = null
     where id = 'bbbbbbbb-cccc-dddd-eeee-ffffffff0002' $$,
  'a null description is still allowed'
);

select * from finish();

rollback;
