-- A catch-all: every SECURITY DEFINER function a client may EXECUTE and that
-- WRITES must carry an authorization predicate in its own body.
--
-- A SECURITY DEFINER function runs as its owner, so RLS is not consulted for
-- anything it touches — the row-level guard that protects every other write in
-- the schema is simply absent. Whatever authorization exists has to be written
-- into the body. There are 45 such functions reachable by `anon` or
-- `authenticated` today, and the schema had no rule that said so: the named
-- hygiene suites (`rls_definer_hygiene_pt3_test`, `rls_function_hygiene_test`)
-- each pin the specific functions an audit pass happened to look at, and
-- `function_search_path_test` pins the hijack defence rather than the
-- authorization. A definer mutator shipped with no gate at all would fail none
-- of them.
--
-- The rule is deliberately about PRESENCE, not position. Most of these
-- functions authorize inside the mutation's own WHERE clause —
-- `update runs ... where r.user_id = auth.uid()` — which is authorization AT
-- the write, and a positional "the check must come first" rule flags five
-- correct functions and teaches the next author to move a predicate for the
-- guard's benefit. What cannot be argued with is a body that never names the
-- caller at all.
--
-- The vocabulary below is the full set of authorization primitives this schema
-- uses. It is spelled out rather than left to a loose pattern so that adding a
-- new one is a deliberate edit here, and so a body cannot satisfy the rule by
-- coincidence.
--
-- Scope, stated so it is not over-read: this proves each function ASKS about
-- its caller, not that the question it asks is the right one. Whether
-- `mark_attendance` should gate on the event's club rather than the event's
-- author is a judgement no catalogue sweep can make; it is what the per-RPC
-- suites are for. What this catches is the absence.

begin;

select plan(6);

-- Functions that authenticate by something other than the caller's identity.
-- Each needs the reason, and a stale entry fails assertion (4).
create temporary table definer_auth_exemptions (fname name, reason text);

insert into definer_auth_exemptions (fname, reason) values
  ('confirm_safety_contact_by_token',
   'the emailed confirm_token IS the credential — a trusted contact confirms '
   'from a link with no account, so there is no caller identity to check. The '
   'token is a gen_random_uuid and the UPDATE is single-use '
   '(confirmed_at is null). Registered as anon-reachable with the same reason '
   'in anon_execute_contract_test.');

create function pg_temp.definer_mutators()
returns table (fname name, gated boolean)
language sql stable as $fn$
  select p.proname,
         (p.prosrc ~* ('(auth\.uid|auth\.role|request\.jwt|is_admin|is_event_organiser'
                       || '|is_club_admin|is_challenge_visible|_visible_to'
                       || '|session_user|current_user)'))
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where p.prosecdef
     and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or has_function_privilege('anon', p.oid, 'EXECUTE'))
     and p.prosrc ~* '(^|[^a-z_])(insert into|update |delete from)';
$fn$;

-- ── operator validation ─────────────────────────────────────────────────────
-- A sweep that had stopped finding anything would satisfy assertion (3) for
-- free. Plant a definer mutator of exactly the shape this test exists to
-- catch — client-executable, writes, names no caller — and require the sweep
-- to report it ungated before asking the real schema anything. The function
-- lives inside this transaction and rolls back with it.
create function public.ungated_definer_probe(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update user_profiles set display_name = 'probe' where id = p_id;
end;
$$;
grant execute on function public.ungated_definer_probe(uuid) to authenticated;

select is(
  (select string_agg(fname::text, ',')
     from pg_temp.definer_mutators()
    where fname = 'ungated_definer_probe' and not gated),
  'ungated_definer_probe',
  'the sweep names a client-executable definer mutator that never mentions its caller'
);
select is(
  (select bool_and(gated)
     from pg_temp.definer_mutators()
    where fname = 'set_run_expected_return'),
  true,
  'and does NOT flag one that authorizes inside the WHERE clause of its own mutation'
);

drop function public.ungated_definer_probe(uuid);

-- ── population floor ────────────────────────────────────────────────────────
select cmp_ok(
  (select count(*)::int from pg_temp.definer_mutators()), '>=', 40,
  'the sweep is looking at the definer mutators it audits, not an empty set'
);

-- ── the rule ────────────────────────────────────────────────────────────────
select is(
  (select coalesce(string_agg(m.fname::text, ', ' order by m.fname), '')
     from pg_temp.definer_mutators() m
    where not m.gated
      and m.fname not in (select fname from definer_auth_exemptions)),
  '',
  'every client-executable SECURITY DEFINER function that writes names its '
  'caller somewhere in its body — RLS is not consulted for anything it touches'
);

-- ── the exemption registry cannot outlive what it excuses ───────────────────
select is(
  (select coalesce(string_agg(e.fname::text, ', ' order by e.fname), '')
     from definer_auth_exemptions e
    where not exists (
      select 1 from pg_temp.definer_mutators() m
       where m.fname = e.fname and not m.gated)),
  '',
  'no exemption names a function that is gone, or that has since grown a '
  'caller check and no longer needs excusing'
);

select is(
  (select coalesce(string_agg(e.fname::text, ', ' order by e.fname), '')
     from definer_auth_exemptions e
    where coalesce(length(e.reason), 0) < 40),
  '',
  'every exemption states why the function authenticates by something other '
  'than the caller identity'
);

select * from finish();
rollback;
