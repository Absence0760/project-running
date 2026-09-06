import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import { MIGRATIONS_DIR } from './check_migration_versions.mjs';
import {
  SUITE_FILE,
  audit,
  countTuples,
  parseServerOnly,
  serverOnlyFamily,
} from './check_server_only_registry.mjs';

/** @returns {{ filename: string, sql: string }[]} */
function committedMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .map((filename) => ({
      filename,
      sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8'),
    }));
}

const FIXTURE = `
create temporary table server_only (fn name, keeps_service_role boolean);
insert into server_only (fn, keeps_service_role) values
  ('claim_next_job', true), ('auto_hide_target', false);
`;

test('parseServerOnly reads the fixture rows and their service_role intent', () => {
  assert.deepEqual(parseServerOnly(FIXTURE), [
    { fn: 'claim_next_job', keepsServiceRole: true },
    { fn: 'auto_hide_target', keepsServiceRole: false },
  ]);
});

test('parseServerOnly returns null rather than a short read', () => {
  // The row reader is a regex; a tuple it cannot match must refuse rather than
  // silently shrink the registry the guard then vouches for.
  const damaged = FIXTURE.replace("('auto_hide_target', false)", "(auto_hide_target, false)");
  assert.equal(parseServerOnly(damaged), null);
  assert.equal(parseServerOnly('select 1;'), null);
});

test('countTuples ignores parentheses inside string literals', () => {
  assert.equal(countTuples("('a', true), ('b (x)', false)"), 2);
  assert.equal(countTuples("('it''s (fine)', true)"), 1);
});

test('the family is every public routine a revoke names and no later grant restores', () => {
  const { family } = serverOnlyFamily([
    {
      filename: '20270101000001_a.sql',
      sql: `
        create function public.sweep() returns void language sql as $$ select 1 $$;
        revoke execute on function public.sweep() from public, anon, authenticated;
        grant execute on function public.sweep() to service_role;
      `,
    },
    {
      filename: '20270101000002_b.sql',
      sql: `
        create function public.reopened() returns void language sql as $$ select 1 $$;
        revoke execute on function public.reopened() from public, anon, authenticated;
      `,
    },
    {
      filename: '20270101000003_c.sql',
      sql: `grant execute on function public.reopened() to authenticated;`,
    },
  ]);
  assert.deepEqual([...family.entries()], [['public.sweep', true]]);
});

test('a trigger-returning routine is excluded, because no grant makes one callable', () => {
  const { family, unreadable } = serverOnlyFamily([
    {
      filename: '20270101000001_a.sql',
      sql: `
        create function public.notify_thing() returns trigger language plpgsql as $$ begin return new; end; $$;
        revoke execute on function public.notify_thing() from public, anon, authenticated;
      `,
    },
  ]);
  assert.deepEqual([...family.keys()], []);
  assert.deepEqual(unreadable, []);
});

test('a routine whose create statement was never seen refuses rather than being guessed', () => {
  const { unreadable } = serverOnlyFamily([
    {
      filename: '20270101000001_a.sql',
      sql: `revoke execute on function public.mystery() from public, anon, authenticated;`,
    },
  ]);
  assert.deepEqual(unreadable, ['public.mystery']);
});

test('a revoke that does not name authenticated is not a withholding from it', () => {
  const { family } = serverOnlyFamily([
    {
      filename: '20270101000001_a.sql',
      sql: `
        create function public.reader() returns void language sql as $$ select 1 $$;
        revoke execute on function public.reader() from public, anon;
      `,
    },
  ]);
  assert.deepEqual([...family.keys()], []);
});

test('a schema-wide revoke states nothing about which routines are server-only', () => {
  const { family } = serverOnlyFamily([
    {
      filename: '20270101000001_a.sql',
      sql: `
        create function public.reader() returns void language sql as $$ select 1 $$;
        revoke execute on all functions in schema public from authenticated;
      `,
    },
  ]);
  assert.deepEqual([...family.keys()], []);
});

test('audit reports a routine the migrations withhold and the fixture omits', () => {
  const result = audit({
    migrations: [
      {
        filename: '20270101000001_a.sql',
        sql: `
          create function public.sweep() returns void language sql as $$ select 1 $$;
          revoke execute on function public.sweep() from public, anon, authenticated;
          create function public.other() returns void language sql as $$ select 1 $$;
          revoke execute on function public.other() from public, anon, authenticated;
        `,
      },
    ],
    suiteSql: `
      create temporary table server_only (fn name, keeps_service_role boolean);
      insert into server_only (fn, keeps_service_role) values ('sweep', false);
    `,
  });
  assert.equal(result.refusal, null);
  assert.deepEqual(result.missing, ['public.other']);
  assert.deepEqual(result.extra, []);
});

test('audit reports a fixture row no migration states a revoke for', () => {
  const result = audit({
    migrations: [
      {
        filename: '20270101000001_a.sql',
        sql: `
          create function public.sweep() returns void language sql as $$ select 1 $$;
          revoke execute on function public.sweep() from public, anon, authenticated;
        `,
      },
    ],
    suiteSql: `
      create temporary table server_only (fn name, keeps_service_role boolean);
      insert into server_only (fn, keeps_service_role) values ('sweep', false), ('ghost', false);
    `,
  });
  assert.deepEqual(result.extra, ['public.ghost']);
});

test('audit reports a keeps_service_role the migrations contradict', () => {
  const result = audit({
    migrations: [
      {
        filename: '20270101000001_a.sql',
        sql: `
          create function public.sweep() returns void language sql as $$ select 1 $$;
          revoke execute on function public.sweep() from public, anon, authenticated;
          grant execute on function public.sweep() to service_role;
        `,
      },
    ],
    suiteSql: `
      create temporary table server_only (fn name, keeps_service_role boolean);
      insert into server_only (fn, keeps_service_role) values ('sweep', false);
    `,
  });
  assert.equal(result.wrongServiceRole.length, 1);
  assert.match(result.wrongServiceRole[0], /^public\.sweep \(fixture says false, migrations state true\)$/);
});

test('audit refuses rather than reporting clean when it cannot see', () => {
  const migrations = [
    {
      filename: '20270101000001_a.sql',
      sql: `
        create function public.sweep() returns void language sql as $$ select 1 $$;
        revoke execute on function public.sweep() from public, anon, authenticated;
      `,
    },
  ];
  /** @param {string | null} refusal @returns {string} */
  const stated = (refusal) => {
    assert.notEqual(refusal, null, 'expected a refusal');
    return String(refusal);
  };
  assert.match(stated(audit({ migrations: [], suiteSql: FIXTURE }).refusal), /no migrations/);
  assert.match(stated(audit({ migrations, suiteSql: 'select 1;' }).refusal), /could not read/);
  assert.match(
    stated(
      audit({
        migrations: [
          ...migrations,
          {
            filename: '20270101000002_b.sql',
            sql: `alter default privileges in schema public grant execute on functions to authenticated;`,
          },
        ],
        suiteSql: FIXTURE,
      }).refusal,
    ),
    /alter default privileges/,
  );
});

test('the committed tree is clean, and the family it derives is not empty', () => {
  const result = audit({
    migrations: committedMigrations(),
    suiteSql: readFileSync(SUITE_FILE, 'utf8'),
  });
  assert.equal(result.refusal, null);
  assert.deepEqual(result.missing, []);
  assert.deepEqual(result.extra, []);
  assert.deepEqual(result.wrongServiceRole, []);
  // A guard whose derived population went empty would report clean forever.
  assert.ok(result.rows >= 40, `expected a non-trivial family, got ${result.rows}`);
});

test('the derivation agrees with the pgtap fixture on every row, in both directions', () => {
  const { family } = serverOnlyFamily(committedMigrations());
  const rows = parseServerOnly(readFileSync(SUITE_FILE, 'utf8'));
  assert.notEqual(rows, null, 'the committed fixture must parse');
  assert.deepEqual(
    (rows ?? []).map((r) => `public.${r.fn}`).sort(),
    [...family.keys()].sort(),
  );
});
