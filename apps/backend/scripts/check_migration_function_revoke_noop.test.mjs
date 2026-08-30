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
  'create or replace function enqueue_run_rematch(p_run_id uuid) returns void language sql as $$ select 1 $$;',
];

test('the shipped shape — grant to authenticated, revoke from anon — is reported', () => {
  const { violations } = audit([
    CREATE,
    [
      '20260102_001_lock.sql',
      `grant execute on function enqueue_run_rematch(uuid) to authenticated;
       revoke execute on function enqueue_run_rematch(uuid) from anon;`,
    ],
  ]);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].routine, 'public.enqueue_run_rematch');
  assert.equal(violations[0].role, 'anon');
  assert.equal(violations[0].filename, '20260102_001_lock.sql');
});

test('the house form `from public, anon` is clean', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from public, anon;'],
  ]);
  assert.deepEqual(violations, []);
});

test('`from public` alone is clean — it is the half that does the work', () => {
  const { violations } = audit([
    CREATE,
    [
      '20260102_001_lock.sql',
      `revoke execute on function enqueue_run_rematch(uuid) from public;
       grant execute on function enqueue_run_rematch(uuid) to authenticated;`,
    ],
  ]);
  assert.deepEqual(violations, []);
});

test('`from public` is never itself the violation, even where PUBLIC ends up holding', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from public;'],
    ['20260103_001_rebuild.sql', `drop function enqueue_run_rematch(uuid);\n${CREATE[1]}`],
  ]);
  assert.deepEqual(violations, []);
});

test('`revoke all` and `revoke all privileges` carry EXECUTE, so both are the class', () => {
  for (const clause of ['all', 'all privileges']) {
    const { violations } = audit([
      CREATE,
      ['20260102_001_lock.sql', `revoke ${clause} on function enqueue_run_rematch(uuid) from anon;`],
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
         ON FUNCTION   public.enqueue_run_rematch( uuid )
         FROM   anon ,   authenticated ;`,
    ],
  ]);
  assert.deepEqual(new Set(violations.map((v) => v.role)), new Set(['anon', 'authenticated']));
});

test('`grant option for` does not hide the verb', () => {
  const { violations } = audit([
    CREATE,
    [
      '20260102_001_lock.sql',
      'revoke grant option for execute on function enqueue_run_rematch(uuid) from anon;',
    ],
  ]);
  assert.equal(violations.length, 1);
});

test('a later revoke from PUBLIC repairs it forward, with no allowlist', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from anon;'],
    ['20260103_001_repair.sql', 'revoke execute on function public.enqueue_run_rematch(uuid) from public;'],
  ]);
  assert.deepEqual(violations, []);
});

test('a later grant to PUBLIC puts the report back', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from anon;'],
    ['20260103_001_repair.sql', 'revoke execute on function enqueue_run_rematch(uuid) from public;'],
    ['20260104_001_reopen.sql', 'grant execute on function enqueue_run_rematch(uuid) to public;'],
  ]);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].filename, '20260102_001_lock.sql');
});

test('repair is judged on the end state, not on directory order', () => {
  const { violations } = audit([
    ['20260103_001_repair.sql', 'revoke execute on function enqueue_run_rematch(uuid) from public;'],
    ['20260102_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from anon;'],
    CREATE,
  ]);
  assert.deepEqual(violations, []);
});

test('a repair is matched across the 8-digit / 14-digit version forms', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from anon;'],
    ['20260102000002_repair.sql', 'revoke execute on function enqueue_run_rematch(uuid) from public;'],
  ]);
  assert.deepEqual(violations, []);
});

test('`create or replace` preserves the ACL, so a lockdown survives it', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from public;'],
    ['20260103_001_rebuild.sql', CREATE[1]],
    ['20260104_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from anon;'],
  ]);
  assert.deepEqual(violations, []);
});

test('drop then create restores the built-in PUBLIC grant, and the next revoke is a no-op again', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from public;'],
    ['20260103_001_rebuild.sql', `drop function if exists enqueue_run_rematch(uuid);\n${CREATE[1]}`],
    ['20260104_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from anon;'],
  ]);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].filename, '20260104_001_lock.sql');
});

test('`public.` qualification and quoted identifiers key to the same routine', () => {
  const { violations } = audit([
    ['20260101_001_create.sql', 'create function public."f"(a uuid) returns void language sql as $$ select 1 $$;'],
    ['20260102_001_lock.sql', 'revoke execute on function "f"(uuid) from anon;'],
    ['20260103_001_repair.sql', 'revoke execute on function public.f(uuid) from public;'],
  ]);
  assert.deepEqual(violations, []);
});

test('a comma-separated routine list is expanded without splitting argument lists', () => {
  const { violations } = audit([
    ['20260101_001_create.sql', 'create function f(a uuid, b text) returns void language sql as $$ select 1 $$;'],
    ['20260101000002_create.sql', 'create function g(c int) returns void language sql as $$ select 1 $$;'],
    ['20260102_001_lock.sql', 'revoke execute on function f(uuid, text), g(int) from anon;'],
  ]);
  assert.deepEqual(
    new Set(violations.map((v) => v.routine)),
    new Set(['public.f', 'public.g']),
  );
});

test('the bulk `on all functions in schema` form is modelled in both directions', () => {
  const created = /** @type {readonly [string, string][]} */ ([
    ['20260101_001_a.sql', 'create function a() returns void language sql as $$ select 1 $$;'],
    ['20260101000002_b.sql', 'create function private.b() returns void language sql as $$ select 1 $$;'],
  ]);
  const flagged = audit([
    ...created,
    ['20260102_001_lock.sql', 'revoke execute on all functions in schema public from anon;'],
  ]);
  assert.deepEqual(flagged.violations.map((v) => v.routine), ['public.a']);

  const clean = audit([
    ...created,
    ['20260102_001_lock.sql', 'revoke execute on all functions in schema public, private from public;'],
    ['20260103_001_lock.sql', 'revoke execute on function a() from anon;'],
  ]);
  assert.deepEqual(clean.violations, []);
});

test('procedures and routines are the same object class', () => {
  const { violations } = audit([
    ['20260101_001_create.sql', 'create procedure p(a uuid) language sql as $$ select 1 $$;'],
    ['20260102_001_lock.sql', 'revoke execute on procedure p(uuid) from anon;'],
    ['20260103_001_lock.sql', 'revoke all on routine p(uuid) from authenticated;'],
  ]);
  assert.equal(violations.length, 2);
});

test('service_role and postgres are not client roles', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_lock.sql', 'revoke execute on function enqueue_run_rematch(uuid) from service_role, postgres;'],
  ]);
  assert.deepEqual(violations, []);
});

test('a table or column revoke is a different guard\'s business', () => {
  const { violations } = audit([
    CREATE,
    [
      '20260102_001_tables.sql',
      `revoke select on donations from anon, authenticated;
       revoke select (secret) on donations from anon;
       revoke select on function_logs from anon;
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
         select 'revoke execute on function enqueue_run_rematch(uuid) from anon'
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
  const { scanned } = audit([CREATE, ['20260102_001_grant.sql', 'grant execute on function enqueue_run_rematch(uuid) to authenticated;']]);
  assert.deepEqual(scanned, ['20260101_001_create.sql', '20260102_001_grant.sql']);
});
