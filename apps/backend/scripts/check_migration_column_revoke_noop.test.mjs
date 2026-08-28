import test from 'node:test';
import assert from 'node:assert/strict';

import { auditMigrations, parsePrivileges } from './check_migration_column_revoke_noop.mjs';

/** @param {readonly (readonly [string, string])[]} pairs */
function audit(pairs) {
  return auditMigrations(pairs.map(([filename, sql]) => ({ filename, sql })));
}

/** @type {readonly [string, string]} */
const CREATE = ['20260101_001_create.sql', 'create table donations (id uuid, secret text);'];

test('parsePrivileges separates a table-level privilege from a column-scoped one', () => {
  assert.deepEqual(parsePrivileges('select'), [{ privilege: 'SELECT', columns: null }]);
  assert.deepEqual(parsePrivileges('select (a, b)'), [{ privilege: 'SELECT', columns: ['a', 'b'] }]);
});

test('parsePrivileges expands `all` and `all privileges` to every DML verb', () => {
  const spelled = parsePrivileges('all privileges');
  assert.notEqual(spelled, null);
  assert.deepEqual(spelled?.map((p) => p.privilege), ['SELECT', 'INSERT', 'UPDATE', 'DELETE']);
  assert.equal(parsePrivileges('all')?.every((p) => p.columns === null), true);
});

test('parsePrivileges keeps a per-privilege column list in a mixed clause', () => {
  assert.deepEqual(parsePrivileges('select, update (archived_at)'), [
    { privilege: 'SELECT', columns: null },
    { privilege: 'UPDATE', columns: ['archived_at'] },
  ]);
});

test('parsePrivileges ignores privileges this guard does not model', () => {
  assert.equal(parsePrivileges('usage'), null);
  assert.equal(parsePrivileges('execute'), null);
});

test('a column revoke under a table-level grant is reported', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_grant.sql', 'grant select on donations to anon, authenticated;'],
    ['20260103_001_lock.sql', 'revoke select (secret) on donations from authenticated, anon;'],
  ]);
  assert.equal(violations.length, 2);
  assert.deepEqual(new Set(violations.map((v) => v.role)), new Set(['anon', 'authenticated']));
  assert.equal(violations[0].table, 'donations');
  assert.equal(violations[0].privilege, 'SELECT');
});

test('a table created and never granted still counts as granted (Supabase default privileges)', () => {
  const { violations } = audit([
    CREATE,
    ['20260103_001_lock.sql', 'revoke select (secret) on donations from authenticated;'],
  ]);
  assert.equal(violations.length, 1);
});

test('the prescribed shape — revoke the table, re-grant per column — is clean', () => {
  const { violations } = audit([
    CREATE,
    [
      '20260103_001_lock.sql',
      `revoke select on donations from anon, authenticated;
       grant select (id) on donations to anon, authenticated;`,
    ],
  ]);
  assert.deepEqual(violations, []);
});

test('a later table-level revoke repairs a shipped column revoke, with no allowlist', () => {
  const { violations } = audit([
    CREATE,
    ['20260103_001_lock.sql', 'revoke select (secret) on donations from authenticated;'],
    ['20260104_001_repair.sql', 'revoke select on donations from authenticated;'],
  ]);
  assert.deepEqual(violations, []);
});

test('a table-level grant after the repair puts the report back', () => {
  const { violations } = audit([
    CREATE,
    ['20260103_001_lock.sql', 'revoke select (secret) on donations from authenticated;'],
    ['20260104_001_repair.sql', 'revoke select on donations from authenticated;'],
    ['20260105_001_reopen.sql', 'grant select on donations to authenticated;'],
  ]);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].filename, '20260103_001_lock.sql');
});

test('repair is judged on the end state, not on file order in the directory listing', () => {
  const { violations } = audit([
    ['20260104_001_repair.sql', 'revoke select on donations from authenticated;'],
    ['20260103_001_lock.sql', 'revoke select (secret) on donations from authenticated;'],
    CREATE,
  ]);
  assert.deepEqual(violations, []);
});

test('a repair is matched across the 8-digit / 14-digit version forms', () => {
  const { violations } = audit([
    CREATE,
    ['20260103_001_lock.sql', 'revoke select (secret) on donations from authenticated;'],
    ['20260103000002_repair.sql', 'revoke select on public.donations from authenticated;'],
  ]);
  assert.deepEqual(violations, []);
});

test('`public.` qualification and quoted identifiers key to the same table', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_grant.sql', 'grant select on public.donations to authenticated;'],
    ['20260103_001_lock.sql', 'revoke select ("secret") on "donations" from authenticated;'],
  ]);
  assert.equal(violations.length, 1);
});

test('a revoked verb does not excuse a column revoke of a different verb', () => {
  const { violations } = audit([
    CREATE,
    ['20260103_001_lock.sql', 'revoke update on donations from authenticated;'],
    ['20260104_001_lock.sql', 'revoke select (secret) on donations from authenticated;'],
  ]);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].privilege, 'SELECT');
});

test('`revoke all` clears every verb, so a later column revoke of any of them is clean', () => {
  const { violations } = audit([
    CREATE,
    ['20260103_001_lock.sql', 'revoke all on donations from authenticated;'],
    ['20260104_001_lock.sql', 'revoke update (secret) on donations from authenticated;'],
  ]);
  assert.deepEqual(violations, []);
});

test('service_role and public are not tracked — only the two client roles', () => {
  const { violations } = audit([
    CREATE,
    ['20260103_001_lock.sql', 'revoke select (secret) on donations from service_role, public;'],
  ]);
  assert.deepEqual(violations, []);
});

test('function, schema and sequence grants are not table grants', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_fn.sql', 'revoke execute on function f(uuid) from anon, authenticated;'],
    ['20260103_001_lock.sql', 'revoke select on donations from anon, authenticated;'],
    ['20260104_001_seq.sql', 'grant usage on schema public to anon, authenticated;'],
    ['20260105_001_lock.sql', 'revoke select (secret) on donations from anon, authenticated;'],
  ]);
  assert.deepEqual(violations, []);
});

test('a column revoke inside a dollar-quoted body is not a statement', () => {
  const { violations } = audit([
    CREATE,
    [
      '20260103_001_fn.sql',
      `create function note() returns text language sql as $$
         select 'revoke select (secret) on donations from authenticated'
       $$;`,
    ],
  ]);
  assert.deepEqual(violations, []);
});

test('a comma-separated table list is expanded', () => {
  const { violations } = audit([
    CREATE,
    ['20260102_001_create2.sql', 'create table payouts (id uuid, secret text);'],
    ['20260103_001_lock.sql', 'revoke select (secret) on donations, payouts from authenticated;'],
  ]);
  assert.deepEqual(new Set(violations.map((v) => v.table)), new Set(['donations', 'payouts']));
});

test('the scanned list names every migration handed in', () => {
  const { scanned } = audit([CREATE, ['20260102_001_grant.sql', 'grant select on donations to anon;']]);
  assert.deepEqual(scanned, ['20260101_001_create.sql', '20260102_001_grant.sql']);
});
