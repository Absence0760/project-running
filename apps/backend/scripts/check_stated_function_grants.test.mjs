import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';

import {
  audit,
  blankComments,
  parseRegistry,
  readCallSites,
  statedGrants,
  qualify,
  REGISTRY_FILE,
  CALLER_TREES,
} from './check_stated_function_grants.mjs';

/** @param {readonly (readonly [string, string])[]} pairs */
function stated(pairs) {
  return statedGrants(pairs.map(([filename, sql]) => ({ filename, sql })));
}

/**
 * @param {Map<string, Set<string>>} acl
 * @param {string} routine
 * @returns {string[]} sorted, and [] rather than undefined when unknown
 */
function rolesOf(acl, routine) {
  return [...(acl.get(routine) ?? [])].sort();
}

/**
 * Lay a fake repo down on disk so the caller scan has something to walk.
 * @param {Record<string, string>} files path relative to the root -> contents
 * @returns {string} the root
 */
function fakeRepo(files) {
  const root = mkdtempSync(join(tmpdir(), 'stated-grants-'));
  for (const [path, contents] of Object.entries(files)) {
    const full = join(root, path);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, contents);
  }
  return root;
}

const REGISTRY_SQL = `
create temporary table stated (fn name, args text, caller name, why text);

insert into stated (fn, args, caller, why) values
  ('fundraiser_totals', 'uuid', 'service_role',
   'granted anon + authenticated only; donations_status_lock_test reads it as service_role');
`;

/** For the cases whose subject is the derived half, not the registered one. */
const NO_REGISTRY = 'select plan(8);';

// ---------------------------------------------------------------- the replay

test('a grant naming a role is stated; a PUBLIC grant is not', () => {
  const { stated: acl } = stated([
    ['20260101_001.sql', 'create function f() returns int language sql as $$ select 1 $$;'],
    [
      '20260102_001.sql',
      'grant execute on function f() to public; grant execute on function f() to authenticated;',
    ],
  ]);
  // PUBLIC is the image-dependent channel: it is what one image hands out free
  // and the other does not, so it can never stand in for a role grant.
  assert.deepEqual(rolesOf(acl, 'public.f'), ['authenticated']);
});

test('a later revoke takes the stated grant back', () => {
  const { stated: acl } = stated([
    ['20260101_001.sql', 'create function f() returns int language sql as $$ select 1 $$;'],
    ['20260102_001.sql', 'grant execute on function f() to authenticated, service_role;'],
    ['20260601_001.sql', 'revoke execute on function f(uuid, jsonb) from authenticated;'],
  ]);
  assert.deepEqual(rolesOf(acl, 'public.f'), ['service_role']);
});

test('the replay runs in version order, not directory order', () => {
  const out = stated([
    ['20260601_001.sql', 'revoke execute on function f() from authenticated;'],
    ['20260101_001.sql', 'create function f() returns int language sql as $$ select 1 $$;'],
    ['20260102_001.sql', 'grant execute on function f() to authenticated;'],
  ]);
  assert.deepEqual(rolesOf(out.stated, 'public.f'), []);
});

test('a drop clears the routine, so a caller of the dropped name is a violation', () => {
  const { stated: acl } = stated([
    ['20260101_001.sql', 'create function f() returns int language sql as $$ select 1 $$;'],
    ['20260102_001.sql', 'grant execute on function f() to authenticated;'],
    ['20260103_001.sql', 'drop function if exists f();'],
  ]);
  assert.equal(acl.has('public.f'), false);
});

test('a grant inside a dollar-quoted body is not a statement', () => {
  const { stated: acl } = stated([
    [
      '20260101_001.sql',
      `create function f() returns void language plpgsql as $$
       begin
         -- the text below is a comment in a body, not a grant
         raise notice 'grant execute on function g() to anon';
       end $$;`,
    ],
  ]);
  assert.equal(acl.has('public.g'), false);
});

test('an alter default privileges on functions is reported, not silently replayed past', () => {
  const { unmodelled } = stated([
    [
      '20260101_001.sql',
      'alter default privileges in schema public grant execute on functions to anon;',
    ],
  ]);
  assert.equal(unmodelled.length, 1);
});

test('a bulk schema grant reaches every routine created so far', () => {
  const { stated: acl } = stated([
    ['20260101_001.sql', 'create function f() returns int language sql as $$ select 1 $$;'],
    ['20260102_001.sql', 'grant execute on all functions in schema public to service_role;'],
  ]);
  assert.deepEqual(rolesOf(acl, 'public.f'), ['service_role']);
});

test('a grant of a privilege other than EXECUTE is ignored', () => {
  const { stated: acl } = stated([
    ['20260101_001.sql', 'create function f() returns int language sql as $$ select 1 $$;'],
    ['20260102_001.sql', 'grant usage on function f() to authenticated;'],
  ]);
  assert.deepEqual(rolesOf(acl, 'public.f'), []);
});

// ------------------------------------------------------------- the registry

test('every row of the registry is parsed, including one whose reason holds a semicolon', () => {
  const rows = parseRegistry(`
    insert into stated (fn, args, caller, why) values
      ('a', 'uuid', 'service_role', 'first reason; with a semicolon in it'),
      ('b', 'uuid, integer', 'authenticated', 'second reason');
  `);
  assert.deepEqual(rows, [
    { fn: 'a', args: 'uuid', caller: 'service_role' },
    { fn: 'b', args: 'uuid, integer', caller: 'authenticated' },
  ]);
});

test('a registry whose tuples and parsed rows disagree yields nothing rather than a short list', () => {
  // The second tuple's function name is not a bare identifier, so the tuple
  // reader skips it. Returning one row would report a clean registry while
  // silently dropping a pair nobody would notice was gone.
  const rows = parseRegistry(`
    insert into stated (fn, args, caller, why) values
      ('a', 'uuid', 'service_role', 'ok'),
      (some_expression, 'uuid', 'authenticated', 'unreadable');
  `);
  assert.deepEqual(rows, []);
});

test('no insert into stated at all yields nothing', () => {
  assert.deepEqual(parseRegistry('select plan(8);'), []);
});

test('the shipped registry file parses to at least one row', () => {
  // The guard refuses on an empty parse, so this is the pin that a reshuffle of
  // the pgtap file is a loud failure here rather than a vacuous pass there.
  const rows = parseRegistry(readFileSync(REGISTRY_FILE, 'utf8'));
  assert.ok(rows.length >= 1);
  assert.ok(rows.every((row) => row.fn.length > 0 && row.caller.length > 0));
});

// ------------------------------------------------------------- call sites

test('a name on the line after `.rpc(` is read, and a comment between them is not', () => {
  const { names, unreadable } = readCallSites(
    `const x = supabase.rpc(
       // Not yet in database.types.ts; the RPC name is cast until then.
       'event_next_instance_going_counts' as never,
       { p: 1 } as never
     );`,
    'ts',
  );
  assert.deepEqual(names, ['event_next_instance_going_counts']);
  assert.deepEqual(unreadable, []);
});

test('an RPC named only in a comment is not a call site', () => {
  const { names, unreadable } = readCallSites(
    `// callers used to do supabase.rpc('clip_track_for_user', ...) here
     const y = 1;`,
    'ts',
  );
  assert.deepEqual(names, []);
  assert.deepEqual(unreadable, []);
});

test('a `//` inside a string literal does not eat the rest of the line', () => {
  const { names } = readCallSites(
    `const url = 'https://example.test'; const z = c.rpc('is_pro');`,
    'ts',
  );
  assert.deepEqual(names, ['is_pro']);
});

test('a non-literal callee is reported rather than skipped', () => {
  const { names, unreadable } = readCallSites('const r = await c.rpc(fnName, params);', 'dart');
  assert.deepEqual(names, []);
  assert.equal(unreadable.length, 1);
  assert.match(unreadable[0], /fnName/);
});

test('the Go worker is read through its helper and through a literal URL', () => {
  const { names, unreadable } = readCallSites(
    `if err := c.rpc(ctx, "claim_next_job", params, &rows); err != nil { return err }
     req, _ := http.NewRequest("POST", c.BaseURL+"/rest/v1/rpc/try_consume_strava_quota", body)`,
    'go',
  );
  assert.deepEqual(names.sort(), ['claim_next_job', 'try_consume_strava_quota']);
  assert.deepEqual(unreadable, []);
});

test('a Go helper call with a variable name is reported', () => {
  const { unreadable } = readCallSites('return c.rpc(ctx, fn, params, nil)', 'go');
  assert.equal(unreadable.length, 1);
});

test('blankComments keeps offsets so a following literal still reads', () => {
  const source = "a /* x */ b // y\nc";
  assert.equal(blankComments(source).length, source.length);
  assert.equal(blankComments(source).includes('x'), false);
});

// ------------------------------------------------------------------ the audit

test('a client-tree caller of a routine with no authenticated grant is a violation', () => {
  const root = fakeRepo({
    'packages/api_client/lib/src/api_client.dart': "await _client.rpc('clip_track_for_user');",
  });
  const { violations } = audit({
    migrations: [
      {
        filename: '20260101_001.sql',
        sql:
          'create function clip_track_for_user(target_user_id uuid, points jsonb) returns jsonb ' +
          'language sql as $$ select points $$;',
      },
      {
        filename: '20260102_001.sql',
        sql: 'grant execute on function clip_track_for_user(uuid, jsonb) to service_role;',
      },
    ],
    registrySql: NO_REGISTRY,
    root,
    trees: [{ dir: 'packages/api_client/lib', role: 'authenticated', kind: 'dart' }],
  });
  assert.equal(violations.length, 1);
  assert.equal(violations[0].routine, 'public.clip_track_for_user');
  assert.equal(violations[0].role, 'authenticated');
  assert.deepEqual(violations[0].held, ['service_role']);
  assert.match(violations[0].source, /api_client\.dart/);
});

test('a server-tree caller demands service_role, not authenticated', () => {
  const migrations = [
    {
      filename: '20260101_001.sql',
      sql: 'create function host_can_take_payment(p_user_id uuid) returns boolean language sql as $$ select true $$;',
    },
    {
      filename: '20260102_001.sql',
      sql: 'grant execute on function host_can_take_payment(uuid) to authenticated;',
    },
  ];
  const root = fakeRepo({
    'apps/backend/supabase/functions/checkout/index.ts':
      "await service.rpc(\n  'host_can_take_payment',\n  { p_user_id: id },\n);",
  });
  const { violations } = audit({
    migrations,
    registrySql: NO_REGISTRY,
    root,
    trees: [{ dir: 'apps/backend/supabase/functions', role: 'service_role', kind: 'ts' }],
  });
  assert.equal(violations.length, 1);
  assert.equal(violations[0].role, 'service_role');
  assert.deepEqual(violations[0].held, ['authenticated']);
});

test('a caller of a routine no migration creates reports held as null, not as an empty grant', () => {
  const root = fakeRepo({
    'packages/api_client/lib/src/api_client.dart': "await _client.rpc('publish_plan_as_template');",
  });
  const { violations } = audit({
    migrations: [{ filename: '20260101_001.sql', sql: 'select 1;' }],
    registrySql: NO_REGISTRY,
    root,
    trees: [{ dir: 'packages/api_client/lib', role: 'authenticated', kind: 'dart' }],
  });
  assert.equal(violations.length, 1);
  assert.equal(violations[0].held, null);
});

test('a stated grant clears the demand', () => {
  const root = fakeRepo({
    'packages/api_client/lib/src/api_client.dart': "await _client.rpc('is_pro');",
  });
  const { violations } = audit({
    migrations: [
      {
        filename: '20260101_001.sql',
        sql: 'create function is_pro() returns boolean language sql as $$ select true $$;',
      },
      { filename: '20260102_001.sql', sql: 'grant execute on function is_pro() to authenticated;' },
    ],
    registrySql: NO_REGISTRY,
    root,
    trees: [{ dir: 'packages/api_client/lib', role: 'authenticated', kind: 'dart' }],
  });
  assert.deepEqual(violations, []);
});

test('a registered pair with no source caller is still demanded', () => {
  const root = fakeRepo({ 'packages/api_client/lib/x.dart': 'const a = 1;' });
  const { violations } = audit({
    migrations: [
      {
        filename: '20260101_001.sql',
        sql: 'create function fundraiser_totals(p_fundraiser_id uuid) returns json language sql as $$ select null::json $$;',
      },
      {
        filename: '20260102_001.sql',
        sql: 'grant execute on function fundraiser_totals(uuid) to anon, authenticated;',
      },
    ],
    registrySql: REGISTRY_SQL,
    root,
    trees: [{ dir: 'packages/api_client/lib', role: 'authenticated', kind: 'dart' }],
  });
  assert.equal(violations.length, 1);
  assert.equal(violations[0].role, 'service_role');
  assert.match(violations[0].source, /anon_execute_registry_test\.sql/);
});

test('a test file is not a call site', () => {
  const root = fakeRepo({
    'packages/api_client/lib/x.dart': 'const a = 1;',
    'packages/api_client/lib/x_test.dart': "expect(src, contains(\"rpc('never_granted'\"));",
  });
  const { violations } = audit({
    migrations: [{ filename: '20260101_001.sql', sql: 'select 1;' }],
    registrySql: NO_REGISTRY,
    root,
    trees: [{ dir: 'packages/api_client/lib', role: 'authenticated', kind: 'dart' }],
  });
  assert.deepEqual(violations, []);
});

test('a caller tree with no source files of its kind is reported, not read as clean', () => {
  const root = fakeRepo({ 'packages/api_client/lib/x.dart': 'const a = 1;' });
  const { emptyTrees } = audit({
    migrations: [{ filename: '20260101_001.sql', sql: 'select 1;' }],
    registrySql: REGISTRY_SQL,
    root,
    trees: [{ dir: 'apps/moved_away/lib', role: 'authenticated', kind: 'dart' }],
  });
  assert.deepEqual(emptyTrees, ['apps/moved_away/lib']);
});

test('every configured caller tree exists in this repo', () => {
  // A tree renamed out from under CALLER_TREES stops demanding anything, which
  // the main() path refuses on; this pins it without running the whole scan.
  const { emptyTrees } = audit({
    migrations: [{ filename: '20260101_001.sql', sql: 'select 1;' }],
    registrySql: REGISTRY_SQL,
    root: join(REGISTRY_FILE, '..', '..', '..', '..', '..'),
    trees: CALLER_TREES,
  });
  assert.deepEqual(emptyTrees, []);
});

test('qualify keys an unqualified name into public', () => {
  assert.equal(qualify('f(uuid, jsonb)'), 'public.f');
  assert.equal(qualify('private.g'), 'private.g');
});
