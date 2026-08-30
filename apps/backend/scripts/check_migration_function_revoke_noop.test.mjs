import test from 'node:test';
import assert from 'node:assert/strict';

import { auditMigrations } from './check_migration_function_revoke_noop.mjs';

/** @param {readonly (readonly [string, string])[]} pairs */
function audit(pairs) {
  return auditMigrations(pairs.map(([filename, sql]) => ({ filename, sql })));
}

/** @type {readonly [string, string]} */
const CREATE = [
  '20260101_001_create.sql',
  'create or replace function coach_roster_summary() returns setof record language sql as $$ select 1 $$;',
];

test('`from public` alone is reported — anon keeps its own grant on the CI and prod image', () => {
  const { violations } = audit([
    CREATE,
    [
      '20260102_001_lock.sql',
      `revoke execute on function coach_roster_summary() from public;
       grant execute on function coach_roster_summary() to authenticated;`,
    ],
  ]);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].routine, 'public.coach_roster_summary');
  assert.equal(violations[0].named, 'public');
  assert.equal(violations[0].missing, 'anon');
});

test('`from anon` alone is reported — PUBLIC still reaches it on the workstation image', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from anon;'],
  ]);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].named, 'anon');
  assert.equal(violations[0].missing, 'public');
});

test('the portable form `from public, anon` is clean, in either order and any spacing', () => {
  for (const roles of ['public, anon', 'anon, public', 'PUBLIC ,  ANON', 'public, anon, authenticated']) {
    const { violations } = audit([
      CREATE,
      ['20260102_001_lock.sql', `revoke execute on function coach_roster_summary() from ${roles};`],
    ]);
    assert.deepEqual(violations, [], roles);
  }
});

test('the two halves may land in different migrations — a repair is forward, not an edit here', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from public;'],
    ['20260103_001_repair.sql', 'revoke execute on function public.coach_roster_summary() from anon;'],
  ]);
  assert.deepEqual(violations, []);
});

test('a deliberate grant discharges the obligation in either direction — it is portable too', () => {
  const openedToAnon = audit([
    CREATE,
    [
      '20260102_001_lock.sql',
      `revoke execute on function coach_roster_summary() from public;
       grant execute on function coach_roster_summary() to anon, authenticated;`,
    ],
  ]);
  assert.deepEqual(openedToAnon.violations, []);

  const openedToPublic = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from anon;'],
    ['20260103_001_open.sql', 'grant execute on function coach_roster_summary() to public;'],
  ]);
  assert.deepEqual(openedToPublic.violations, []);
});

test('`from authenticated` alone is reported, but an anon lockdown never obliges authenticated', () => {
  const alone = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from authenticated;'],
  ]);
  assert.equal(alone.violations.length, 1);
  assert.equal(alone.violations[0].named, 'authenticated');
  assert.equal(alone.violations[0].missing, 'public');

  const anonOnly = audit([
    CREATE,
    [
      '20260102_001_lock.sql',
      `revoke execute on function coach_roster_summary() from public, anon;
       grant execute on function coach_roster_summary() to authenticated;`,
    ],
  ]);
  assert.deepEqual(anonOnly.violations, []);
});

test('naming PUBLIC settles the authenticated obligation but not the anon one', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from public, authenticated;'],
  ]);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].named, 'public');
  assert.equal(violations[0].missing, 'anon');
});

test('`revoke all` and `revoke all privileges` carry EXECUTE, so both are the class', () => {
  for (const clause of ['all', 'all privileges']) {
    const { violations } = audit([
      CREATE,
      ['20260102_001_lock.sql', `revoke ${clause} on function coach_roster_summary() from public;`],
    ]);
    assert.equal(violations.length, 1, clause);
  }
});

test('a statement spanning lines, in any spacing or casing, is read the same', () => {
  const { violations } = audit([
    CREATE,
    [
      '20260102_001_lock.sql',
      `REVOKE   EXECUTE
         ON FUNCTION   public.coach_roster_summary( )
         FROM   PUBLIC ;`,
    ],
  ]);
  assert.equal(violations.length, 1);
});

test('`grant option for` does not hide the verb', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke grant option for execute on function coach_roster_summary() from public;'],
  ]);
  assert.equal(violations.length, 1);
});

test('a drop-and-recreate re-defaults both channels, and every unpaired revoke reports again', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from public;'],
    ['20260103_001_repair.sql', 'revoke execute on function coach_roster_summary() from anon;'],
    [
      '20260104_001_rebuild.sql',
      `drop function coach_roster_summary();\n${CREATE[1]}`,
    ],
    ['20260105_001_lock.sql', 'revoke execute on function coach_roster_summary() from public;'],
  ]);
  assert.deepEqual(
    violations.map((v) => v.filename),
    ['20260102_001_lock.sql', '20260105_001_lock.sql'],
  );
});

test('repair is judged on the end state, not on directory order', () => {
  const { violations } = audit([
    ['20260103_001_repair.sql', 'revoke execute on function coach_roster_summary() from anon;'],
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from public;'],
    CREATE,
  ]);
  assert.deepEqual(violations, []);
});

test('a repair is matched across the 8-digit / 14-digit version forms', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from public;'],
    ['20260102000002_repair.sql', 'revoke execute on function coach_roster_summary() from anon;'],
  ]);
  assert.deepEqual(violations, []);
});

test('`create or replace` preserves the ACL, so a portable lockdown survives a rebuild', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from public, anon;'],
    ['20260103_001_rebuild.sql', CREATE[1]],
  ]);
  assert.deepEqual(violations, []);
});

test('a well-formed revoke is never reported, even where a later rebuild re-opens the routine', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from public, anon;'],
    ['20260103_001_rebuild.sql', `drop function coach_roster_summary();\n${CREATE[1]}`],
  ]);
  assert.deepEqual(violations, []);
});

test('drop then create resets both channels, so the earlier pairing no longer covers', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from public, anon;'],
    ['20260103_001_rebuild.sql', `drop function if exists coach_roster_summary();\n${CREATE[1]}`],
    ['20260104_001_lock.sql', 'revoke execute on function coach_roster_summary() from anon;'],
  ]);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].filename, '20260104_001_lock.sql');
  assert.equal(violations[0].missing, 'public');
});

test('`public.` qualification and quoted identifiers key to the same routine', () => {
  const { violations } = audit([
    ['20260101_001_create.sql', 'create function public."f"(a uuid) returns void language sql as $$ select 1 $$;'],
    ['20260102_001_lock.sql', 'revoke execute on function "f"(uuid) from public;'],
    ['20260103_001_repair.sql', 'revoke execute on function public.f(uuid) from anon;'],
  ]);
  assert.deepEqual(violations, []);
});

test('a comma-separated routine list is expanded without splitting argument lists', () => {
  const { violations } = audit([
    ['20260101_001_create.sql', 'create function f(a uuid, b text) returns void language sql as $$ select 1 $$;'],
    ['20260101000002_create.sql', 'create function g(c int) returns void language sql as $$ select 1 $$;'],
    ['20260102_001_lock.sql', 'revoke execute on function f(uuid, text), g(int) from public;'],
  ]);
  assert.deepEqual(new Set(violations.map((v) => v.routine)), new Set(['public.f', 'public.g']));
});

test('the bulk `on all functions in schema` form is modelled in both directions', () => {
  const created = /** @type {readonly [string, string][]} */ ([
    ['20260101_001_a.sql', 'create function a() returns void language sql as $$ select 1 $$;'],
    ['20260101000002_b.sql', 'create function private.b() returns void language sql as $$ select 1 $$;'],
  ]);
  const flagged = audit([
    ...created,
    ['20260102_001_lock.sql', 'revoke execute on all functions in schema public from public;'],
  ]);
  assert.deepEqual(flagged.violations.map((v) => v.routine), ['public.a']);

  const clean = audit([
    ...created,
    ['20260102_001_lock.sql', 'revoke execute on all functions in schema public, private from public, anon;'],
  ]);
  assert.deepEqual(clean.violations, []);
});

test('procedures and routines are the same object class', () => {
  const { violations } = audit([
    ['20260101_001_create.sql', 'create procedure p(a uuid) language sql as $$ select 1 $$;'],
    ['20260102_001_lock.sql', 'revoke execute on procedure p(uuid) from public;'],
    ['20260103_001_lock.sql', 'revoke all on routine p(uuid) from anon;'],
  ]);
  assert.deepEqual(violations, []);
});

test('service_role and postgres are not client roles', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function coach_roster_summary() from service_role, postgres;'],
  ]);
  assert.deepEqual(violations, []);
});

test("a table or column revoke is a different guard's business", () => {
  const { violations } = audit([
    CREATE,
    [
      '20260102_001_tables.sql',
      `revoke select on donations from anon, authenticated;
       revoke select (secret) on donations from anon;
       revoke select on function_logs from anon;
       revoke all on public.public_runs from public, anon, authenticated;
       grant usage on schema public to anon;`,
    ],
  ]);
  assert.deepEqual(violations, []);
});

test('a revoke inside a dollar-quoted body is not a statement', () => {
  const { violations } = audit([
    CREATE,
    [
      '20260102_001_fn.sql',
      `create function note() returns text language sql as $$
         select 'revoke execute on function coach_roster_summary() from public'
       $$;`,
    ],
  ]);
  assert.deepEqual(violations, []);
});

test('an alter default privileges on routines is reported as unmodelled, not judged', () => {
  const { unmodelled, violations } = audit([
    CREATE,
    [
      '20260102_001_defaults.sql',
      'alter default privileges in schema public revoke execute on functions from public;',
    ],
  ]);
  assert.equal(unmodelled.length, 1);
  assert.equal(unmodelled[0].filename, '20260102_001_defaults.sql');
  assert.deepEqual(violations, []);
});

test('the scanned list names every migration handed in', () => {
  const { scanned } = audit([
    CREATE,
    ['20260102_001_grant.sql', 'grant execute on function coach_roster_summary() to authenticated;'],
  ]);
  assert.deepEqual(scanned, ['20260101_001_create.sql', '20260102_001_grant.sql']);
});
