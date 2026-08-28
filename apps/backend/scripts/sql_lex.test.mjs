import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import { MIGRATIONS_DIR } from './check_migration_versions.mjs';
import { splitSqlStatements } from './sql_lex.mjs';

test('a dollar-quoted body is one statement, however many semicolons it holds', () => {
  const sql = [
    'create or replace function f() returns void language plpgsql as $$',
    'begin',
    '  perform 1;',
    '  perform 2;',
    'end;',
    '$$;',
    'select 1;',
  ].join('\n');
  const statements = splitSqlStatements(sql);
  assert.equal(statements.length, 2);
  assert.match(statements[0], /create or replace function/);
  assert.match(statements[0], /perform 2/);
  assert.equal(statements[1].trim(), 'select 1');
});

test('a tagged dollar quote closes only on its own tag', () => {
  const sql = "select $outer$ a $$ b; c $$ d $outer$; select 2;";
  assert.deepEqual(
    splitSqlStatements(sql).map((s) => s.trim()),
    ['select $outer$ a $$ b; c $$ d $outer$', 'select 2'],
  );
});

test('$1 is a positional parameter, not a dollar quote', () => {
  assert.deepEqual(
    splitSqlStatements('select $1, $2 from t; select 3;').map((s) => s.trim()),
    ['select $1, $2 from t', 'select 3'],
  );
});

test('a semicolon inside a string literal does not end the statement', () => {
  assert.deepEqual(
    splitSqlStatements("insert into t(note) values ('a; b'); select 1;").map((s) => s.trim()),
    ["insert into t(note) values ('a; b')", 'select 1'],
  );
});

test('a doubled quote is an escaped quote, not a close followed by an open', () => {
  assert.deepEqual(
    splitSqlStatements("select 'it''s; fine'; select 2;").map((s) => s.trim()),
    ["select 'it''s; fine'", 'select 2'],
  );
});

test('an E-string takes backslash escapes', () => {
  assert.deepEqual(
    splitSqlStatements("select e'a\\'; b'; select 2;").map((s) => s.trim()),
    ["select e'a\\'; b'", 'select 2'],
  );
  // Not an E-string: the `e` belongs to an identifier, so `\` is literal and
  // the quote before `;` closes.
  assert.equal(splitSqlStatements("select code'a\\'; select 2;").length, 2);
});

test('a quoted identifier hides a semicolon too', () => {
  assert.deepEqual(
    splitSqlStatements('alter table "we;ird" add column x int; select 1;').map((s) => s.trim()),
    ['alter table "we;ird" add column x int', 'select 1'],
  );
});

// The false NEGATIVE the naive `--` strip produced: eating to end of line
// before knowing whether the `--` was a comment swallows the statement's own
// terminator, so the next statement is glued on and its `not valid` vouches
// for the blocking ADD in front of it.
test('a `--` inside a string literal is not a comment', () => {
  const sql = [
    "alter table runs add constraint a check (note not like '%--%');",
    'alter table runs add constraint b check (v > 0) not valid;',
  ].join('\n');
  const statements = splitSqlStatements(sql);
  assert.equal(statements.length, 2);
  assert.equal(statements[0].includes('not valid'), false);
  assert.equal(statements[1].includes('not valid'), true);
});

test('block comments nest, as Postgres nests them', () => {
  assert.deepEqual(
    splitSqlStatements('/* a /* b */ still comment */ select 1;').map((s) => s.trim()),
    ['select 1'],
  );
});

test('comments are removed but leave a token separator behind', () => {
  assert.deepEqual(
    splitSqlStatements('select/* x */1;').map((s) => s.trim()),
    ['select 1'],
  );
  assert.deepEqual(
    splitSqlStatements('select 1 -- trailing\n;').map((s) => s.trim()),
    ['select 1'],
  );
});

test('blankLiterals empties the content and keeps the delimiters', () => {
  assert.deepEqual(
    splitSqlStatements("select 'a; b', $t$ c; d $t$, \"e\";", { blankLiterals: true }).map((s) =>
      s.trim(),
    ),
    ["select '', $t$$t$, \"\""],
  );
});

test('a trailing statement with no terminator is still returned', () => {
  assert.deepEqual(
    splitSqlStatements('select 1;\nselect 2').map((s) => s.trim()),
    ['select 1', 'select 2'],
  );
  assert.deepEqual(splitSqlStatements(';;\n  \n;'), []);
});

test('an unterminated construct throws rather than consuming to end of file', () => {
  for (const [sql, what] of [
    ["select 'x", 'string literal'],
    ['select "x', 'quoted identifier'],
    ['select $tag$ x', 'dollar-quoted body'],
    ['/* a /* b */', 'block comment'],
  ]) {
    assert.throws(() => splitSqlStatements(sql), new RegExp(`unterminated ${what}`), sql);
  }
});

test('every committed migration lexes, and into far fewer pieces than a `;` split', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql'));
  assert.ok(files.length > 400, `expected the committed tree, saw ${files.length} files`);
  let naive = 0;
  let lexed = 0;
  for (const f of files) {
    const sql = readFileSync(join(MIGRATIONS_DIR, f), 'utf8');
    naive += sql
      .replace(/--[^\n]*/g, ' ')
      .replace(/\/\*[\s\S]*?\*\//g, ' ')
      .split(';').length;
    lexed += splitSqlStatements(sql).length;
  }
  // Measured at the commit that introduced this lexer: 7366 naive fragments
  // against 3441 real statements. The assertion is the ORDER, not the figures:
  // the naive split invented over three thousand pieces of text that were
  // never statements, and a guard that grades those is grading nothing.
  assert.ok(naive > lexed * 1.5, `naive ${naive} vs lexed ${lexed}`);
});
