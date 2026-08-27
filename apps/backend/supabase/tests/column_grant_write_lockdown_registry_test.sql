-- Class guard for the column-level WRITE lockdowns: which public tables
-- withhold which columns from a client's INSERT / UPDATE, why, and the two
-- ways that shape stops locking anything.
--
-- The write-side sibling of column_grant_lockdown_registry_test (SELECT,
-- decisions.md 759). Four tables revoke a table-level write verb and re-grant
-- it column by column — achievements 20270506_001 (UPDATE), coach_messages
-- 20260518_001 (UPDATE) + 20270616_001 (INSERT), challenge_participants
-- 20270209_001 (UPDATE) + 20270616_001 (INSERT), event_attendees 20270102_001
-- (UPDATE) + 20270520_001 (INSERT). Every withholding below is a decision with
-- a named alternative writer — a SECURITY DEFINER RPC, a trigger, or the
-- service role — not an accident of reaching for `grant update (a, b)`.
--
-- The shape has TWO failure modes and they point in opposite directions.
--
-- The first is the read side's, mirrored: a re-grant is CUMULATIVE, so a column
-- added to one of these tables after its lockdown is deny-by-default and
-- silently UNWRITABLE — 42501 on a PostgREST PATCH or POST. It has not fired
-- here (no column has been added to any of the four since its lockdown landed),
-- which is why it is worth pinning before it does: `clubs.is_verified` did
-- exactly this on the SELECT side and took down every non-service-role read of
-- `clubs` for a day.
--
-- The second has fired, on main, and it is the one this guard exists for. A
-- column-scoped UPDATE locks nothing while the same client holds a WIDER INSERT
-- on a table it may also DELETE from, because DELETE + re-INSERT reaches every
-- column the UPDATE grant withheld. decisions.md 584 found it on
-- event_attendees (a buyer self-writing `attendance`); 20270520_001 closed it
-- there; `challenge_participants` still carried it until 20270616_001, so
-- `completed_at` — the column challenge_participants_completed_lockdown_test
-- pins against a direct UPDATE — was writable in two statements by the
-- participant. Assertion (5) is that class: a column a client may INSERT but
-- not UPDATE has to say in this file why writing it once is safe.
--
-- Pinned in the direction that detects drift, per 759: the WITHHELD set, not
-- the granted one. A new column nobody granted enlarges the withheld set and
-- fails (1). Pinning the granted set would not move at all.
--
-- The same assertions close three more:
--   * a deliberate withholding granted away (completed_at, attendance,
--     order_id, a forged achievement tier),
--   * a table-wide `grant insert`/`grant update` landing on a locked table,
--     which empties the withheld set,
--   * a registry entry outliving its column.
--
-- Assertion (4) is 759's anon-vs-authenticated symmetry, generalised to every
-- column and every DML verb in the schema. It is here because the write side
-- had a live divergence the read side did not: `coach_messages` granted anon a
-- TABLE-level UPDATE against authenticated's column-scoped (archived_at,
-- reaction) — 20260518_001 revoked the table grant from `authenticated` only
-- and 20270408_001, generated from the drifted prod schema, version-controlled
-- the leftover. Inert (anon's auth.uid() is null, so the owner policy matches
-- no row) but that is RLS covering for a grant. Revoked by 20270616_001.

begin;

select plan(6);

-- Columns WITHHELD from a role on a table whose verb is column-scoped.
create temporary table write_lockdown_registry (role name, tbl name, verb text, col name, reason text);

insert into write_lockdown_registry (role, tbl, verb, col, reason) values
  -- achievements — UPDATE narrowed to the owner's visibility toggle by
  -- 20270506_001. Awards are written only by award_achievements_for_user
  -- (SECURITY DEFINER). There is no INSERT row here because 20270616_001
  -- revoked client INSERT + DELETE outright: no client write path exists
  -- beyond the toggle, so there is no surface to carve.
  ('authenticated', 'achievements', 'UPDATE', 'id',          'row identity; renaming an award forges a badge (20270506_001)'),
  ('authenticated', 'achievements', 'UPDATE', 'user_id',     'award ownership; written by the definer awarder'),
  ('authenticated', 'achievements', 'UPDATE', 'badge_key',   'which badge was earned; the forge vector 20270506_001 names'),
  ('authenticated', 'achievements', 'UPDATE', 'tier',        'bronze->platinum is the forge vector 20270506_001 names'),
  ('authenticated', 'achievements', 'UPDATE', 'source_kind', 'award provenance'),
  ('authenticated', 'achievements', 'UPDATE', 'source_id',   'award provenance'),
  ('authenticated', 'achievements', 'UPDATE', 'value_num',   'the figure the badge claims'),
  ('authenticated', 'achievements', 'UPDATE', 'earned_at',   'when it was earned; orders every badge feed'),

  -- challenge_participants — 20270209_001 (UPDATE) + 20270616_001 (INSERT).
  -- completed_at is written only by recompute_challenge_completion
  -- (SECURITY DEFINER, caller-guarded by 20270306_001).
  ('authenticated', 'challenge_participants', 'UPDATE', 'challenge_id', 'row identity; a participant row is not re-targetable at another challenge'),
  ('authenticated', 'challenge_participants', 'UPDATE', 'user_id',      'row identity; the join is the caller''s own'),
  ('authenticated', 'challenge_participants', 'UPDATE', 'joined_at',    'defaults to now() at join; a client-set value backdates a joining'),
  ('authenticated', 'challenge_participants', 'UPDATE', 'completed_at', 'completion stamp; written only by recompute_challenge_completion'),
  ('authenticated', 'challenge_participants', 'INSERT', 'joined_at',    'ditto — insertable until 20270616_001, which is how leaving and rejoining backdated it'),
  ('authenticated', 'challenge_participants', 'INSERT', 'completed_at', 'ditto — insertable until 20270616_001, which is how DELETE + re-INSERT forged a completion (decisions.md 584 class)'),

  -- coach_messages — 20260518_001 (UPDATE) + 20270616_001 (INSERT). The two
  -- mutations the client issues are archive and react; everything else is the
  -- durable conversation log, and assistant turns are written by the
  -- service-role client in apps/web/src/lib/coach/handler.ts.
  ('authenticated', 'coach_messages', 'UPDATE', 'id',         'row identity'),
  ('authenticated', 'coach_messages', 'UPDATE', 'user_id',    'thread ownership'),
  ('authenticated', 'coach_messages', 'UPDATE', 'plan_id',    'which plan the thread hangs off'),
  ('authenticated', 'coach_messages', 'UPDATE', 'role',       'user vs assistant; flipping it forges coach advice (20260518_001)'),
  ('authenticated', 'coach_messages', 'UPDATE', 'content',    'the turn itself; immutability is the point of the lockdown'),
  ('authenticated', 'coach_messages', 'UPDATE', 'created_at', 'thread ordering'),
  ('authenticated', 'coach_messages', 'INSERT', 'id',         'defaults to gen_random_uuid(); a client-chosen id is not the client''s to pick'),
  ('authenticated', 'coach_messages', 'INSERT', 'created_at', 'defaults to now(); a client-set value backdates the log the lockdown exists to keep auditable'),
  ('authenticated', 'coach_messages', 'INSERT', 'archived_at', 'a turn is not archived at the moment it is written; archiving is the UPDATE the grant exists for'),
  ('authenticated', 'coach_messages', 'INSERT', 'reaction',    'a turn is not reacted to at the moment it is written; reacting is the UPDATE the grant exists for'),

  -- event_attendees — 20270102_001 (UPDATE) + 20270520_001 (INSERT), the
  -- decisions.md 584 pair. attendance is the organiser's word and order_id is
  -- the money link; both are service-role/definer-written.
  ('authenticated', 'event_attendees', 'UPDATE', 'joined_at',  'stamped at RSVP'),
  ('authenticated', 'event_attendees', 'UPDATE', 'order_id',   'the paid-order link; enforce_paid_order_for_priced_event validates it'),
  ('authenticated', 'event_attendees', 'UPDATE', 'attendance', 'the organiser''s attendance mark, not the attendee''s'),
  ('authenticated', 'event_attendees', 'INSERT', 'order_id',   'ditto — the 20270520_001 half of the 584 fix'),
  ('authenticated', 'event_attendees', 'INSERT', 'attendance', 'ditto — self-marking `attended` at INSERT was the 584 exploit');

-- Columns a client may set once, at row creation, and never change. Each needs
-- a reason why write-once is safe — this is the register assertion (5) reads.
create temporary table insert_only_registry (tbl name, col name, reason text);

insert into insert_only_registry (tbl, col, reason) values
  ('challenge_participants', 'challenge_id', 'which challenge the row joins; the WITH CHECK gates visibility at insert and the row is not re-targetable afterwards'),
  ('challenge_participants', 'user_id',      'the joiner; the WITH CHECK pins it to auth.uid() at insert'),
  ('coach_messages',         'user_id',      'thread owner; the WITH CHECK pins it to auth.uid() at insert'),
  ('coach_messages',         'plan_id',      'which plan the turn belongs to; chosen when the turn is written'),
  ('coach_messages',         'role',         'the WITH CHECK confines a client insert to role = ''user'''),
  ('coach_messages',         'content',      'the turn itself — written once by definition; that it cannot then change IS the 20260518_001 lockdown'),
  ('event_attendees',        'joined_at',    'RSVP stamp, set at insert; the UPDATE grant deliberately omits it (20270102_001)');

-- Tables with NO client UPDATE grant at all — append-only by design, so every
-- column is trivially insert-only and enumerating them would be noise.
-- Assertion (6) checks the exemption is still true rather than trusting it.
create temporary table append_only_registry (tbl name, reason text);

insert into append_only_registry (tbl, reason) values
  ('global_segment_efforts', 'a catalogue effort is a record of a run that happened: insert + owner-delete policies only, no UPDATE policy and no UPDATE grant');

-- (1) The registry IS the withheld write map, in both directions, for both
-- roles and both verbs. "Column-scoped" means the role lacks the table-level
-- privilege but holds it on at least one column — a table the role cannot
-- write at all is not a lockdown, it is an absence, and has nothing to drift.
select is(
  (with roles(role) as (values ('anon'::name), ('authenticated'::name)),
        verbs(verb) as (values ('INSERT'), ('UPDATE')),
        scoped as (
          select r.role, cl.oid as tbloid, cl.relname as tbl, v.verb
            from roles r
            cross join verbs v
            join pg_class cl on cl.relkind in ('r', 'p')
            join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
           where not has_table_privilege(r.role, cl.oid, v.verb)
             and exists (
               select 1 from pg_attribute a
                where a.attrelid = cl.oid and a.attnum > 0 and not a.attisdropped
                  and has_column_privilege(r.role, cl.oid, a.attnum, v.verb))
        ),
        withheld as (
          select s.role, s.tbl, s.verb, a.attname as col
            from scoped s
            join pg_attribute a on a.attrelid = s.tbloid and a.attnum > 0 and not a.attisdropped
           where not has_column_privilege(s.role, s.tbloid, a.attnum, s.verb)
        )
   select coalesce(string_agg(offence, ', ' order by offence), '')
     from (
       select coalesce(w.role, g.role) || ': ' || coalesce(w.tbl, g.tbl) || '.'
              || coalesce(w.col, g.col) || ' (' || coalesce(w.verb, g.verb) || ')'
              || case when g.col is null
                      then ' is withheld but not in the registry — a column added'
                           || ' after the lockdown is deny-by-default and silently'
                           || ' unwritable (42501 on a PATCH/POST); grant it, or'
                           || ' register the reason it is withheld'
                      else ' is in the registry but writable — a deliberate'
                           || ' withholding was granted away, or a table-wide'
                           || ' grant landed on a write-locked table' end as offence
         from withheld w
         full join write_lockdown_registry g
           on g.role = w.role and g.tbl = w.tbl and g.verb = w.verb and g.col = w.col
        where w.col is null or g.col is null
     ) offences),
  '',
  'the column-level INSERT/UPDATE lockdowns withhold exactly the registered '
  'columns from anon + authenticated — no column drifted in ungranted, and no '
  'registered withholding was granted away'
);

-- (2) No OTHER public table carries the per-column write shape. A fifth table
-- reaching for `grant update (a, b)` declares itself here with a reason per
-- withheld column, or it is an accident.
select is(
  (select coalesce(string_agg(distinct cl.relname || ' (' || r.role || ', '
                              || ae.privilege_type || ')', ', '), '')
     from pg_class cl
     join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
     join pg_attribute a on a.attrelid = cl.oid and a.attnum > 0 and not a.attisdropped
                        and a.attacl is not null
     cross join lateral aclexplode(a.attacl) ae
     cross join (values ('anon'::name), ('authenticated'::name)) r(role)
    where cl.relkind in ('r', 'p')
      and cl.relname not in (select distinct tbl from write_lockdown_registry)
      and ae.privilege_type in ('INSERT', 'UPDATE')
      and ae.grantee = (select oid from pg_roles where rolname = r.role)),
  '',
  'no public table outside the write registry grants INSERT or UPDATE per '
  'column — a new per-column write grant is either a lockdown that belongs in '
  'the registry with its reason, or a table grant written the long way'
);

-- (3) The lockdown itself is intact: the locked verb stays revoked at table
-- level, so the per-column carve-out is what is actually gating writes.
select is(
  (select coalesce(string_agg(x.tbl || ' (' || x.role || ', ' || x.verb || ')',
                              ', ' order by x.tbl, x.role, x.verb), '')
     from (select distinct role, tbl, verb from write_lockdown_registry) x
    where has_table_privilege(x.role, ('public.' || x.tbl)::regclass, x.verb)),
  '',
  'no write-locked table has regained a table-level INSERT or UPDATE for the '
  'verb it locks — that would grant every withheld column at once'
);

-- (4) anon is never WIDER than authenticated, on any column of any public
-- table, for any DML verb. They diverged once in this direction
-- (coach_messages UPDATE, 20260518_001 -> 20270616_001) and a divergence is a
-- hole on the wider side, not a variant worth carrying silently.
select is(
  (select coalesce(string_agg(cl.relname || '.' || a.attname || ' (' || p.priv || ')',
                              ', ' order by cl.relname, a.attname, p.priv), '')
     from pg_class cl
     join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
     join pg_attribute a on a.attrelid = cl.oid and a.attnum > 0 and not a.attisdropped
     cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('REFERENCES')) p(priv)
    where cl.relkind in ('r', 'p')
      and has_column_privilege('anon', cl.oid, a.attnum, p.priv)
      and not has_column_privilege('authenticated', cl.oid, a.attnum, p.priv)),
  '',
  'anon holds no column privilege authenticated lacks — an anon-wider grant '
  'is reachable by every caller, signed in or not'
);

-- (5) The decisions.md 584 class. A column a client may INSERT but not UPDATE
-- is only locked down while the client cannot DELETE and re-INSERT the row, so
-- every such column has to be registered as deliberately write-once with the
-- reason. Both directions: a stale entry whose column became updatable (or
-- stopped being insertable) fails too.
select is(
  (with ins_not_upd as (
     select cl.relname as tbl, a.attname as col
       from pg_class cl
       join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
       join pg_attribute a on a.attrelid = cl.oid and a.attnum > 0 and not a.attisdropped
      where cl.relkind in ('r', 'p')
        and cl.relname not in (select tbl from append_only_registry)
        and has_column_privilege('authenticated', cl.oid, a.attnum, 'INSERT')
        and not has_column_privilege('authenticated', cl.oid, a.attnum, 'UPDATE')
   )
   select coalesce(string_agg(offence, ', ' order by offence), '')
     from (
       select coalesce(i.tbl, r.tbl) || '.' || coalesce(i.col, r.col)
              || case when r.col is null
                      then ' is insertable but not updatable and is not registered'
                           || ' write-once — while the client can DELETE its own'
                           || ' row, a column-scoped UPDATE locks nothing (584);'
                           || ' withhold it from INSERT too, or register why'
                           || ' writing it exactly once is safe'
                      else ' is registered write-once but is not insertable-and-'
                           || 'not-updatable any more — the entry is stale' end as offence
         from ins_not_upd i
         full join insert_only_registry r on r.tbl = i.tbl and r.col = i.col
        where i.col is null or r.col is null
     ) offences),
  '',
  'every column a client may INSERT but not UPDATE is registered write-once '
  'with the reason writing it once is safe'
);

-- (6) The append-only exemption assertion (5) leans on is still true. An
-- UPDATE grant appearing on one of these tables — table-level or per-column —
-- turns the exemption into a silent hole, so it is checked rather than trusted.
select is(
  (select coalesce(string_agg(t.tbl, ', ' order by t.tbl), '')
     from append_only_registry t
     join pg_class cl on cl.relname = t.tbl and cl.relkind in ('r', 'p')
     join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
    where exists (
      select 1 from pg_attribute a
       where a.attrelid = cl.oid and a.attnum > 0 and not a.attisdropped
         and (has_column_privilege('authenticated', cl.oid, a.attnum, 'UPDATE')
              or has_column_privilege('anon', cl.oid, a.attnum, 'UPDATE')))),
  '',
  'every append-only table really holds no client UPDATE grant — the '
  'exemption assertion (5) leans on cannot go stale silently'
);

select * from finish();
rollback;
