#!/usr/bin/env node
// Mutation-check the pgtap suite's refusal assertions: prove each one can tell
// "denied" from "never there".
//
// decisions.md 732 found the same defect one layer up, in the Playwright
// suite: an assertion whose expectation is zero-or-empty is *satisfied* by a
// read that never happened, so the assertions whose whole job is to prove a
// refusal were the ones a broken read made vacuous. Under RLS the pgtap
// analogue is sharper, because a refused SELECT does not error at all - it
// returns no rows. So `is_empty(...)` / `is(<count>, 0, ...)` is what a
// refusal looks like AND what a fixture that never inserted looks like, what a
// WHERE clause matching nothing looks like, and what a typo'd uuid looks like.
//
// The discriminator is mutation, not inspection: run each such assertion again
// with row-level access control removed at that exact instant. Every public
// table is owned by `postgres`, which holds BYPASSRLS and which no table
// FORCEs RLS against, so `reset role` for the duration of one statement is a
// complete, lock-free bypass. If the rows exist and a policy was hiding them,
// the assertion turns red. If it stays green, nothing was hidden because
// nothing was there - the assertion is not testing access control and must
// either be given a subject or be listed below with the reason its zero is a
// real answer.
//
// Found by this guard at introduction: rls_route_conditions_test's non-owner
// and anon private-route reads, which asserted that an empty table reads
// empty.
//
// Two phases. The first is static and checks that every negative pins the
// error it expects, so a `throws_ok` cannot pass on a typo'd table name. The
// second is the mutation run and needs the local stack.

import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const TESTS_DIR = join(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  'supabase',
  'tests',
);

export const DB_URL =
  process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

const DOLLAR_TAG = /^\$[A-Za-z0-9_]*\$/;

// Offset just past the token starting at `i` when that token is a string,
// dollar-quoted body, quoted identifier or comment; null when it is code.
export function skipToken(text, i) {
  const n = text.length;
  const c = text[i];
  if (c === '$') {
    const tag = DOLLAR_TAG.exec(text.slice(i, i + 64))?.[0];
    if (tag) {
      const close = text.indexOf(tag, i + tag.length);
      return close === -1 ? n : close + tag.length;
    }
  }
  if (c === "'") {
    for (let j = i + 1; j < n; j += 1) {
      if (text[j] !== "'") continue;
      if (text[j + 1] === "'") { j += 1; continue; }
      return j + 1;
    }
    return n;
  }
  if (c === '"') {
    const close = text.indexOf('"', i + 1);
    return close === -1 ? n : close + 1;
  }
  if (c === '-' && text[i + 1] === '-') {
    const close = text.indexOf('\n', i);
    return close === -1 ? n : close;
  }
  if (c === '/' && text[i + 1] === '*') {
    const close = text.indexOf('*/', i + 2);
    return close === -1 ? n : close + 2;
  }
  return null;
}

// Byte map of which offsets are code rather than string/comment payload.
export function codeMask(text) {
  const mask = new Uint8Array(text.length);
  let i = 0;
  while (i < text.length) {
    const skip = skipToken(text, i);
    if (skip !== null) { i = skip; continue; }
    mask[i] = 1;
    i += 1;
  }
  return mask;
}

export function splitArgs(args) {
  const parts = [];
  let depth = 0;
  let last = 0;
  let i = 0;
  while (i < args.length) {
    const skip = skipToken(args, i);
    if (skip !== null) { i = skip; continue; }
    const c = args[i];
    if (c === '(' || c === '[') depth += 1;
    else if (c === ')' || c === ']') depth -= 1;
    else if (c === ',' && depth === 0) { parts.push(args.slice(last, i).trim()); last = i + 1; }
    i += 1;
  }
  parts.push(args.slice(last).trim());
  return parts;
}

export function findCalls(text, name) {
  const mask = codeMask(text);
  const re = new RegExp(`(?<![A-Za-z0-9_.])${name}\\s*\\(`, 'g');
  const out = [];
  for (const m of text.matchAll(re)) {
    if (!mask[m.index]) continue;
    let i = m.index + m[0].length;
    const argStart = i;
    let depth = 1;
    while (i < text.length && depth > 0) {
      const skip = skipToken(text, i);
      if (skip !== null) { i = skip; continue; }
      if (text[i] === '(') depth += 1;
      else if (text[i] === ')') depth -= 1;
      i += 1;
    }
    out.push({
      name,
      offset: m.index,
      line: text.slice(0, m.index).split('\n').length,
      argv: splitArgs(text.slice(argStart, i - 1)),
    });
  }
  return out;
}

// The text of a SQL literal argument (single-quoted or dollar-quoted), or null
// when the argument is an expression rather than a literal.
export function literalOf(arg) {
  const a = arg.trim();
  const single = /^'((?:[^']|'')*)'$/s.exec(a);
  if (single) return single[1].replaceAll("''", "'");
  const tag = DOLLAR_TAG.exec(a)?.[0];
  if (tag && a.endsWith(tag) && a.length >= 2 * tag.length) {
    return a.slice(tag.length, -tag.length);
  }
  return null;
}

// pgTAP reads a 5-character second argument as a SQLSTATE and anything else as
// an expected message; either is a pin. A `null` in both slots pins nothing, so
// the assertion passes on ANY error, including one raised by a typo rather
// than by the policy under test.
export function throwsPinsItsError(argv) {
  for (const arg of argv.slice(1, 3)) {
    if (arg === undefined) continue;
    if (arg.trim().toLowerCase() === 'null') continue;
    if (literalOf(arg) !== null) return true;
    if (!/^['$]/.test(arg.trim())) return true;
  }
  return false;
}

// A description claiming a principal is denied SIGHT of data. This is what
// makes an empty result a security claim rather than a statement about a
// trigger that correctly did not fire.
export const REFUSAL_VOCABULARY =
  /(cannot (see|read|select|view|find)|can't (see|read|select|view)|not (see|read|visible|readable|exposed|returned)|invisible|hidden|hides|no access|leak|denied|denies|sees no|sees none|returns nothing|shadow)/i;

const ZERO_EXPECTATION = /^\s*0(::(bigint|int4|int|integer|numeric|smallint))?\s*$/i;
const RELATION_REF = /\b(?:from|join)\s+(?:only\s+)?([a-z_][a-z0-9_]*(?:\.[a-z_][a-z0-9_]*)?)/gi;

export function relationsIn(sql) {
  return new Set([...sql.matchAll(RELATION_REF)].map((m) => m[1].toLowerCase().split('.').pop()));
}

// Every zero-or-empty assertion in one file whose claim is a read refusal and
// whose query reads a base table, so RLS is the mechanism that could hide it.
export function refusalAssertions(text, baseTables) {
  const out = [];
  for (const kind of ['is_empty', 'is', 'results_eq']) {
    for (const call of findCalls(text, kind)) {
      const [sql, expected] = call.argv;
      if (sql === undefined) continue;
      const zeroish =
        kind === 'is_empty' ||
        (kind === 'is' && expected !== undefined && ZERO_EXPECTATION.test(expected)) ||
        (kind === 'results_eq' && expected !== undefined && /values\s*\(\s*0\s*\)/i.test(expected));
      if (!zeroish) continue;
      const description = literalOf(call.argv.at(-1) ?? '');
      if (description === null || !REFUSAL_VOCABULARY.test(description)) continue;
      if (![...relationsIn(sql)].some((r) => baseTables.has(r))) continue;
      out.push({ ...call, description });
    }
  }
  return out.sort((a, b) => a.offset - b.offset);
}

export function statementStart(text, offset) {
  const mask = codeMask(text);
  for (let i = offset - 1; i >= 0; i -= 1) if (mask[i] && text[i] === ';') return i + 1;
  return 0;
}

export function statementEnd(text, offset) {
  const mask = codeMask(text);
  for (let i = offset; i < text.length; i += 1) if (mask[i] && text[i] === ';') return i + 1;
  return text.length;
}

const CREATE_PGTAP = 'create extension if not exists pgtap with schema extensions;\n';
const BYPASS = [
  "select set_config('pgtap_guard.role', current_setting('role'), true);",
  "select set_config('role','none',true);",
  '',
].join('\n');
const RESTORE = "select set_config('role', current_setting('pgtap_guard.role'), true);\n";

// One mutant per file: each candidate assertion runs with the role dropped to
// the BYPASSRLS owner for the span of its own statement and restored straight
// after. The assertions are read-only, so bypassing one changes nothing the
// next one sees, which is what lets a whole file's candidates be measured in a
// single run.
export function buildMutant(text, candidates) {
  const beginAt = /^begin;$/m.exec(text);
  if (!beginAt) throw new Error('test file does not open a transaction');
  const afterBegin = beginAt.index + beginAt[0].length + 1;
  const spans = candidates
    .map((c) => ({ start: statementStart(text, c.offset), end: statementEnd(text, c.offset) }))
    .sort((a, b) => a.start - b.start);
  let out = '';
  let cursor = afterBegin;
  for (const span of spans) {
    out +=
      text.slice(cursor, span.start) +
      '\n' + BYPASS + text.slice(span.start, span.end) + '\n' + RESTORE;
    cursor = span.end;
  }
  return text.slice(0, afterBegin) + CREATE_PGTAP + out + text.slice(cursor);
}

export function parseTap(output) {
  const results = new Map();
  for (const line of output.split('\n')) {
    const m = /^(ok|not ok) (\d+) - (.*)$/.exec(line.trim());
    if (m) results.set(m[3].trim(), m[1] === 'ok');
  }
  return results;
}

// Refusal assertions whose empty result is a real answer rather than a hidden
// row. Each needs the reason its subject genuinely does not exist; a stale
// entry, one that no longer exists or that the mutation now kills, fails the
// guard, so this list cannot quietly outlive what it excuses.
export const EXPECTED_SURVIVORS = [
  {
    file: 'auto_hide_reports_test.sql',
    description: 'no content_hidden notification before the threshold',
    reason:
      'the claim is that the auto-hide trigger did NOT fire below its report threshold, so an absent notification row is the subject rather than a hidden one',
  },
  {
    file: 'rls_live_run_pings_trigger_test.sql',
    description:
      'in-zone ping never stores its precise coordinates (Realtime sees no exact point)',
    reason:
      'the privacy trigger blanks the coordinate before INSERT, so the precise point is absent from the row rather than filtered out of the read',
  },
  {
    file: 'rls_race_pings_trigger_test.sql',
    description:
      'in-zone race ping never stores its precise coordinates (spectator feed sees no exact point)',
    reason: 'same write-time blanking as rls_live_run_pings_trigger_test',
  },
  {
    file: 'safety_contacts_test.sql',
    description:
      'the same read scoped to owner_id returns nothing — a contact owns no list of their own',
    reason:
      'the assertion above it (an UNFILTERED read returning the owner row) carries the policy claim; this one states the data shape that makes the union surprising, and a contact genuinely owns no rows',
  },
];

function psql(sql) {
  try {
    return execFileSync(
      'psql',
      ['-X', '-q', '--no-psqlrc', '--no-align', '--tuples-only', '--pset', 'pager=off', '-f', '-', DB_URL],
      { input: sql, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], timeout: 180_000 },
    );
  } catch (error) {
    const why =
      error.code === 'ENOENT'
        ? 'psql is not on PATH'
        : `psql could not reach ${DB_URL}: ${String(error.stderr ?? error.message).trim()}`;
    console.error(
      `pgtap refusal-assertion guard could not run its mutation phase: ${why}.\n` +
        'Start the local Supabase stack (apps/backend: supabase start), set SUPABASE_DB_URL,\n' +
        'or run with --static-only to check only that every negative pins its error.',
    );
    process.exit(1);
  }
}

function fetchBaseTables() {
  const rows = psql(
    'select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace' +
      " where n.nspname = 'public' and c.relkind in ('r','p');",
  );
  return new Set(rows.split('\n').map((r) => r.trim()).filter(Boolean));
}

function report(failures, summary) {
  if (failures.length > 0) {
    console.error('pgtap refusal-assertion guard failed:\n');
    for (const f of failures) console.error(`  - ${f}\n`);
    process.exit(1);
  }
  console.log(`pgtap refusal-assertion guard: ${summary}`);
}

function main() {
  const files = readdirSync(TESTS_DIR).filter((f) => f.endsWith('.sql')).sort();
  const failures = [];

  for (const file of files) {
    const text = readFileSync(join(TESTS_DIR, file), 'utf8');
    for (const call of findCalls(text, 'throws_ok')) {
      if (throwsPinsItsError(call.argv)) continue;
      failures.push(
        `${file}:${call.line}  throws_ok pins neither a SQLSTATE nor an error message, so it passes on ANY error: a typo'd table name, or a refusal at a different layer than the policy under test, satisfies it just as well.`,
      );
    }
  }

  if (process.argv.includes('--static-only')) {
    report(failures, `${files.length} test files scanned for unpinned negatives`);
    return;
  }

  const baseTables = fetchBaseTables();
  const survivors = [];
  let population = 0;

  for (const file of files) {
    const text = readFileSync(join(TESTS_DIR, file), 'utf8');
    const candidates = refusalAssertions(text, baseTables);
    if (candidates.length === 0) continue;
    population += candidates.length;
    const tap = parseTap(psql(buildMutant(text, candidates)));
    for (const candidate of candidates) {
      const passed = tap.get(candidate.description);
      if (passed === undefined) {
        failures.push(
          `${file}:${candidate.line}  the mutant run never reached "${candidate.description}", so the guard could not measure it.`,
        );
        continue;
      }
      if (passed) survivors.push({ file, line: candidate.line, description: candidate.description });
    }
  }

  const excused = new Set(EXPECTED_SURVIVORS.map((e) => `${e.file} ${e.description}`));
  for (const s of survivors) {
    if (excused.has(`${s.file} ${s.description}`)) continue;
    failures.push(
      `${s.file}:${s.line}  "${s.description}" still passes with row-level access control removed, so it cannot tell a hidden row from a row that was never inserted. Give it a subject (file the row the refusal is about, and read it back from a session that may see it), or add it to EXPECTED_SURVIVORS with the reason its empty result is a real answer.`,
    );
  }

  const seen = new Set(survivors.map((s) => `${s.file} ${s.description}`));
  for (const entry of EXPECTED_SURVIVORS) {
    if (seen.has(`${entry.file} ${entry.description}`)) continue;
    failures.push(
      `EXPECTED_SURVIVORS entry ${entry.file} / "${entry.description}" no longer matches a surviving refusal assertion. It was renamed, deleted, or is now killed by the mutation: remove the entry rather than leaving it to excuse something that no longer exists.`,
    );
  }

  report(
    failures,
    `${population} refusal assertions mutation-checked across ${files.length} test files; ` +
      `${survivors.length} survived, all ${EXPECTED_SURVIVORS.length} of them expected`,
  );
}

if (import.meta.url === `file://${process.argv[1]}`) main();
