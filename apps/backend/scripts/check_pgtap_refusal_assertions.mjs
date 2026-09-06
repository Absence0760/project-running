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
// with the mechanism that could be hiding a row taken away. There are two such
// mechanisms and therefore two operators, chosen per assertion by what it
// reads (decisions.md 745):
//
//   1. Row-level security, behind a base table read. RLS is a set of policy
//      expressions, so the operator is an extra PERMISSIVE policy on every
//      RLS-enabled table, armed for the span of one statement and revealing
//      only the rows THIS TRANSACTION wrote.
//
//   2. The relation's OWN predicate, behind a read through a view or an RPC. A
//      `security definer` view and a SECURITY DEFINER function already run as
//      their owner, so RLS was never what hid anything from them - and so does
//      a SECURITY INVOKER function whose body carries a `= auth.uid()`, which
//      the catalogue cannot tell you about. Dropping RLS leaves all of those
//      returning exactly what they returned. The operator for them is a
//      permissive replacement of the relation itself, inside a savepoint:
//      pgtap_definer_neutralisers.mjs holds one per relation, with a witness
//      proving it reveals a subject the real relation hides.
//
// Either operator can reveal a row the test never filed, and a kill over one of
// those says a subject exists in the database rather than that the test built
// one - 741's inversion one remove further out, deterministic here because the
// seed is committed rather than accumulated Playwright debris. So both are
// scoped to the rows this transaction wrote (decisions.md 751 for operator 2,
// 753 for operator 1). Without it `gym_exercise_set_history('Bench Press')` is
// killed by seed.sql's six committed `Bench press` sets whether or not the test
// inserted anything at all.
//
// If the rows exist and something was hiding them, the assertion turns red. If
// it stays green, nothing was hidden because nothing was there - the assertion
// is not testing access control and must either be given a subject or be
// listed below with the reason its zero is a real answer.
//
// Found by this guard at introduction: rls_route_conditions_test's non-owner
// and anon private-route reads, which asserted that an empty table reads
// empty. Found by the second operator: seven "owner-scoped" RPC refusals that
// the first operator could not have measured at all.
//
// Three phases. `--static-only` checks that every negative pins the error it
// expects, so a `throws_ok` cannot pass on a typo'd table name.
// `--validate-operators` proves each permissive replacement is not inert. The
// default is the mutation run, and needs the local stack.

import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  DEFINER_NEUTRALISERS,
  TRANSACTION_LOCAL,
  TRANSACTION_LOCAL_SQL,
  UNREGISTERED_DEFINER_RELATIONS,
} from './pgtap_definer_neutralisers.mjs';

export const TESTS_DIR = join(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  'supabase',
  'tests',
);

export const MIGRATIONS_DIR = join(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  'supabase',
  'migrations',
);

export const DB_URL =
  process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

const DOLLAR_TAG = /^\$[A-Za-z0-9_]*\$/;

/**
 * Which mutation operator reaches a relation: `base` is a table RLS hides rows
 * in, `invoker` a view or function that inherits the caller's RLS, `definer`
 * one that runs as its owner and filters in its own SQL.
 * @typedef {'base' | 'invoker' | 'definer'} RelationSecurity
 */

/** @typedef {Map<string, RelationSecurity>} RelationMap */

/** @typedef {{ name: string, offset: number, line: number, argv: string[] }} PgtapCall */

/**
 * @typedef {PgtapCall & {
 *   description: string,
 *   read: string[],
 *   neutralise: string[],
 *   unmeasurable: string[],
 *   selected: boolean,
 * }} ZeroOrEmptyAssertion
 */

// Offset just past the token starting at `i` when that token is a string,
// dollar-quoted body, quoted identifier or comment; null when it is code.
/**
 * @param {string} text
 * @param {number} i
 * @returns {number | null}
 */
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
/** @param {string} text */
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

/**
 * @param {string} args
 * @returns {string[]}
 */
export function splitArgs(args) {
  /** @type {string[]} */
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

/**
 * @param {string} text
 * @param {string} name
 * @returns {PgtapCall[]}
 */
export function findCalls(text, name) {
  const mask = codeMask(text);
  const re = new RegExp(`(?<![A-Za-z0-9_.])${name}\\s*\\(`, 'g');
  /** @type {PgtapCall[]} */
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
/**
 * @param {string} arg
 * @returns {string | null}
 */
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
/** @param {string[]} argv */
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
//
// The selector is prose, so its reach is measured rather than argued
// (decisions.md 745). Both operators were run over all 294 zero-or-empty
// assertions in the suite, not just the ones worded as refusals. The regex as
// it stood selected 126 and 121 of them died under mutation, so it is
// precise. Of the 168 it did not select, 28 died too — a real recall gap, and
// the words behind it split in two:
//
//   - `never sees`, `unfindable`, `enumerate`, `exposes no`, `reads nothing`,
//     `gets nothing`, `absent from` — unambiguous refusal words the regex
//     simply lacked. Added here: every assertion they select dies under
//     mutation, so they cost nothing and reach tests not written yet.
//
//   - `excluded` / `excludes` — 21 assertions, about half access control (a
//     declared minor, a search opt-out, a block, a members-only event) and
//     about half ordinary filters (`byday=MO excludes it`, `free filter
//     excludes the priced class`). One word, two claims. No regex separates
//     them, and widening to catch the first half drags in the second, each
//     needing an EXPECTED_SURVIVORS entry to excuse a filter that was never a
//     security claim — the allowlist-that-rots this selector exists to avoid.
//     Those carry an explicit `-- refusal:` marker instead.
//
// Two of the 28 are not refusals at all and are deliberately still outside:
// `distance is returned as coarse bucket 0` and `a long-broken streak reports
// current = 0` expect a zero VALUE, not an empty result, and a widening
// mutation moves a value. A kill means "the mutation changed the answer",
// which is only evidence of access control when the zero was an emptiness.
export const REFUSAL_VOCABULARY =
  /(cannot (see|read|select|view|find)|can't (see|read|select|view)|not (see|read|visible|readable|exposed|returned)|never (see|sees|read|reads)|invisible|hidden|hides|no access|leak|denied|denies|sees no|sees none|returns nothing|reads nothing|gets nothing|exposes no|unfindable|enumerate|absent from|shadow)/i;

// An explicit "this zero is a refusal" marker in the test, for a claim whose
// own wording cannot carry it. It goes on its own comment line immediately
// above the assertion, inside the same statement span, and says why:
//
//   -- refusal: the under-18 floor is access control, not a search filter
//   select is((select count(*)::int from search_user_profiles('Minor')), 0, ...);
//
// The colon is load-bearing: prose wrapping onto a line that happens to open
// with `-- refusal,` is not a marker, and one such comment already exists.
//
// It is opt-IN only. Nothing here can take an assertion OUT of the
// population: a zero the vocabulary claims is a refusal and that survives
// mutation has to be argued for by name in EXPECTED_SURVIVORS, where the
// reason is reviewable and a stale entry fails as loudly as a new offender.
export const REFUSAL_MARKER = /--[ \t]*refusal:/i;

const ZERO_EXPECTATION = /^\s*0(::(bigint|int4|int|integer|numeric|smallint))?\s*$/i;
const RELATION_REF = /\b(?:from|join)\s+(?:only\s+)?([a-z_][a-z0-9_]*(?:\.[a-z_][a-z0-9_]*)?)/gi;

/**
 * @param {string} sql
 * @returns {Set<string>}
 */
export function relationsIn(sql) {
  return new Set(
    [...sql.matchAll(RELATION_REF)].map((m) => {
      const ref = m[1].toLowerCase();
      return ref.slice(ref.lastIndexOf('.') + 1);
    }),
  );
}

// Every zero-or-empty assertion in one file that reads at least one relation of
// this database, with the fields that decide what can be said about it:
// `selected` is whether its own prose (or an explicit marker) claims a
// refusal, `neutralise` is the relations a permissive replacement is
// registered for, and `unmeasurable` is the ones that run as their owner and
// have none — for which the widening policy is provably inert, so an assertion is
// not measured at all rather than scored on an operator that could not have
// changed it.
/**
 * @param {string} text
 * @param {RelationMap} relations
 * @returns {ZeroOrEmptyAssertion[]}
 */
export function zeroOrEmptyAssertions(text, relations) {
  /** @type {ZeroOrEmptyAssertion[]} */
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
      if (description === null) continue;
      const read = [...relationsIn(sql)].filter((r) => relations.has(r));
      if (read.length === 0) continue;
      const marked = REFUSAL_MARKER.test(text.slice(statementStart(text, call.offset), call.offset));
      const neutralise = read.filter((r) => DEFINER_NEUTRALISERS.has(r));
      const unmeasurable = read.filter(
        (r) => relations.get(r) === 'definer' && !DEFINER_NEUTRALISERS.has(r),
      );
      out.push({
        ...call,
        description,
        read,
        neutralise,
        unmeasurable,
        selected: marked || REFUSAL_VOCABULARY.test(description),
      });
    }
  }
  return out.sort((a, b) => a.offset - b.offset);
}

// The half of the above whose claim is a read refusal: what makes an empty
// result a security assertion rather than a statement about a trigger that
// correctly did not fire.
/**
 * @param {string} text
 * @param {RelationMap} relations
 */
export function refusalAssertions(text, relations) {
  return zeroOrEmptyAssertions(text, relations).filter((c) => c.selected);
}

/**
 * @param {string} text
 * @param {number} offset
 */
export function statementStart(text, offset) {
  const mask = codeMask(text);
  for (let i = offset - 1; i >= 0; i -= 1) if (mask[i] && text[i] === ';') return i + 1;
  return 0;
}

/**
 * @param {string} text
 * @param {number} offset
 */
export function statementEnd(text, offset) {
  const mask = codeMask(text);
  for (let i = offset; i < text.length; i += 1) if (mask[i] && text[i] === ';') return i + 1;
  return text.length;
}

// Operator 1, scoped the same way § 751 scoped operator 2.
//
// It used to be `set role` to the BYPASSRLS owner, and a role change has no
// query to hang a predicate off — so it revealed the whole table, and a kill
// said a subject existed in the DATABASE rather than that the test built one.
// But RLS is not only a role check: it is a set of policy expressions, and a
// policy IS a query to add a predicate to. So the operator is a permissive
// policy rather than a role change, the same shape the second operator already
// has, one layer down: every RLS-enabled table gains an extra permissive SELECT
// policy revealing only the rows THIS TRANSACTION wrote, and the assertion runs
// as the role the test gave it rather than as the owner.
//
// The policies are created once per file, immediately after its `begin;`, and
// go with the file's rollback. They are gated on a GUC so they are inert
// everywhere except inside a mutated span — creating them per span would be
// ~90 DDL statements per assertion, and leaving them ungated would widen the
// file's fixtures and its unmutated assertions too.
export const WIDEN_GUC = 'pgtap_guard.widen';
export const PREAMBLE =
  'create extension if not exists pgtap with schema extensions;\n' +
  TRANSACTION_LOCAL_SQL +
  `do $pgtap_guard$
declare t regclass;
begin
  for t in select c.oid::regclass from pg_class c
             join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r','p') and c.relrowsecurity
  loop
    execute format('create policy pgtap_guard_widen on %s as permissive for select'
      || ' to public using (current_setting(''${WIDEN_GUC}'', true) = ''on'''
      || ' and ${TRANSACTION_LOCAL}(xmin))', t);
  end loop;
end
$pgtap_guard$;
`;
const WIDEN_ON = `select set_config('${WIDEN_GUC}','on',true);\n`;
const WIDEN_OFF = `select set_config('${WIDEN_GUC}','off',true);\n`;

// `create or replace` needs the relation's owner, so the definer span drops the
// role for its own length. It does not need the widening: all 51 assertions this
// operator measures read the replaced relation and nothing else, so the
// replacement's own transaction-local scope is the whole of their subject
// selection, and running the read as the owner reaches no base table the
// assertion asked about.
const BECOME_OWNER = [
  "select set_config('pgtap_guard.role', current_setting('role'), true);",
  "select set_config('role','none',true);",
  '',
].join('\n');

// The definer span carries the owner bypass plus a permissive replacement of
// every definer relation the assertion reads, and rolls the whole thing back to
// a savepoint afterwards. `create or replace` is transactional, so the real view
// or function is restored before the next assertion runs — which is what keeps a
// whole file measurable in one pass even though this operator is a schema change
// and the first one is not.
/**
 * @param {string} sql
 * @param {string[]} definer
 */
export function definerSpan(sql, definer) {
  const mark = 'pgtap_guard_definer';
  const replacements = definer.map((name) => {
    const entry = DEFINER_NEUTRALISERS.get(name);
    if (!entry) throw new Error(`no permissive replacement registered for ${name}`);
    return entry.sql;
  });
  return (
    `savepoint ${mark};\n` +
    BECOME_OWNER +
    replacements.join('\n') +
    '\n' +
    sql +
    '\n' +
    `rollback to savepoint ${mark};\nrelease savepoint ${mark};\n`
  );
}

// One mutant per file: each candidate assertion runs with the widening policies
// armed for the span of its own statement and disarmed straight after. The
// assertions are read-only, so widening one changes nothing the next one sees,
// which is what lets a whole file's candidates be measured in a single run.
/**
 * @param {string} text
 * @param {{ offset: number, neutralise?: string[] }[]} candidates
 */
export function buildMutant(text, candidates) {
  const beginAt = /^begin;$/m.exec(text);
  if (!beginAt) throw new Error('test file does not open a transaction');
  const afterBegin = beginAt.index + beginAt[0].length + 1;
  const spans = candidates
    .map((c) => ({
      start: statementStart(text, c.offset),
      end: statementEnd(text, c.offset),
      neutralise: c.neutralise ?? [],
    }))
    .sort((a, b) => a.start - b.start);
  let out = '';
  let cursor = afterBegin;
  for (const span of spans) {
    const statement = text.slice(span.start, span.end);
    out +=
      text.slice(cursor, span.start) +
      '\n' +
      (span.neutralise.length > 0
        ? definerSpan(statement, span.neutralise)
        : WIDEN_ON + statement + '\n' + WIDEN_OFF);
    cursor = span.end;
  }
  return text.slice(0, afterBegin) + PREAMBLE + out + text.slice(cursor);
}

/// Every verdict the mutant emitted, keyed by description and kept as a LIST.
/// A `Map<description, boolean>` collapsed two assertions sharing a
/// description to whichever ran last, in both directions: `ok` then `not ok`
/// scored the surviving — vacuous — one as killed, and the reverse scored a
/// genuinely killed one as a survivor. The description is the only handle the
/// TAP stream offers on a call site, so a repeated one is a verdict this guard
/// cannot attribute, and `verdictFor` says so rather than picking. decisions
/// § 774.
/**
 * @param {string} output
 * @returns {Map<string, boolean[]>}
 */
export function parseTap(output) {
  /** @type {Map<string, boolean[]>} */
  const results = new Map();
  for (const line of output.split('\n')) {
    const m = /^(ok|not ok) (\d+) - (.*)$/.exec(line.trim());
    if (!m) continue;
    const description = m[3].trim();
    const verdicts = results.get(description) ?? [];
    verdicts.push(m[1] === 'ok');
    results.set(description, verdicts);
  }
  return results;
}

/**
 * @param {Map<string, boolean[]>} tap
 * @param {string} description
 * @returns {{ status: 'unreached' | 'survived' | 'killed' | 'ambiguous', count: number }}
 */
export function verdictFor(tap, description) {
  const verdicts = tap.get(description);
  if (verdicts === undefined || verdicts.length === 0) return { status: 'unreached', count: 0 };
  if (verdicts.length > 1) return { status: 'ambiguous', count: verdicts.length };
  return { status: verdicts[0] ? 'survived' : 'killed', count: 1 };
}

// Refusal assertions whose empty result is a real answer rather than a hidden
// row. Each needs the reason its subject genuinely does not exist; a stale
// entry, one that no longer exists or that the mutation now kills, fails the
// guard, so this list cannot quietly outlive what it excuses. "The subject is
// in the database but this transaction did not write it" is NOT a reason to
// add one: that is a fixture the test owes, and the entry would excuse exactly
// the vacuity the guard exists to find.
//
// An entry keys on `file + description`, which is one assertion only because
// `verdictFor` refuses a repeated description outright — two assertions
// sharing one would never reach the survivor list, so no entry can excuse a
// second assertion it was not written for.
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
  {
    file: 'segment_leaderboard_tiered_test.sql',
    description: 'no-demographics runner is invisible to age-band filters',
    reason:
      'an age band cannot contain a runner who has no age, so no access control is what excludes them and no operator can reveal them. The positive control is test 2 of the same file, which asserts by results_eq that this exact runner IS on the unfiltered board - the pair is what makes the zero mean something. The consent half of the same predicate (a runner with a date but no Art 9 stamp) is a real refusal and is measured in segment_leaderboard_age_band_consent_test',
  },
];

// psql runs the whole mutant in one go and does NOT stop on the first error,
// because a statement that fails is a fact about the mutation rather than a
// reason to abandon the file. The consequence is that an early failure aborts
// the transaction and every later assertion silently produces no TAP line —
// which reads as "the guard could not measure it" with no clue why. So the
// errors are kept, and quoted back by whoever reports a missing assertion.
// spawnSync rather than execFileSync because only spawnSync hands back stderr
// on the runs that succeed, and those are exactly the runs this matters for.
/** @type {string[]} */
let lastPsqlErrors = [];

/** @param {string} sql */
function psql(sql) {
  const run = spawnSync(
    'psql',
    ['-X', '-q', '--no-psqlrc', '--no-align', '--tuples-only', '--pset', 'pager=off', '-f', '-', DB_URL],
    { input: sql, encoding: 'utf8', timeout: 180_000 },
  );
  if (run.error || run.status !== 0) {
    const why =
      run.error !== undefined && 'code' in run.error && run.error.code === 'ENOENT'
        ? 'psql is not on PATH'
        : `psql could not reach ${DB_URL}: ${String(run.stderr ?? run.error?.message ?? '').trim()}`;
    console.error(
      `pgtap refusal-assertion guard could not run its mutation phase: ${why}.\n` +
        'Start the local Supabase stack (apps/backend: supabase start), set SUPABASE_DB_URL,\n' +
        'or run with --static-only to check only that every negative pins its error.',
    );
    process.exit(1);
  }
  lastPsqlErrors = String(run.stderr ?? '')
    .split('\n')
    .filter((line) => line.includes('ERROR:'))
    .slice(0, 3);
  return run.stdout;
}

// Every relation an assertion can read from `public`, tagged with the operator
// that reaches it. Read from the live catalogue rather than from the migration
// text: a view's `security_invoker` and a function's `prosecdef` are exactly
// the fact that decides which mutation is not inert, and a list in this file
// would be one more thing to keep in step with the schema.
/**
 * The catalogue read's `name|kind` lines as a map, or the reason it cannot be
 * one. Split out from the psql call so the parse is unit-testable, and made to
 * REFUSE rather than degrade: every assertion in the suite is admitted to the
 * population by `relations.has(...)`, so a read that comes back empty, or with
 * a kind this file does not recognise, takes the whole population to zero and
 * the guard then measures nothing while reporting a count. That is § 741's
 * inversion pointed at the instrument itself.
 * @param {string} rows
 * @returns {{ relations: RelationMap, failure: string | null }}
 */
export function parseRelationSecurity(rows) {
  /** @type {RelationMap} */
  const out = new Map();
  for (const row of rows.split('\n')) {
    const [name, kind] = row.trim().split('|');
    if (!name) continue;
    if (kind !== 'base' && kind !== 'invoker' && kind !== 'definer') {
      return {
        relations: out,
        failure:
          `the catalogue read answered "${row.trim()}", whose second column is not one of ` +
          'base / invoker / definer. Which operator is not inert is decided by that column, so ' +
          'the guard cannot choose one until the query in fetchRelationSecurity() and this parse ' +
          'agree again.',
      };
    }
    // A table and a function of the same name resolve to the table in a FROM
    // clause, so the relation's answer wins over the routine's.
    if (out.has(name) && out.get(name) === 'base') continue;
    out.set(name, kind);
  }
  if (out.size === 0) {
    return {
      relations: out,
      failure:
        'the catalogue read returned no relations at all. Every zero-or-empty assertion is ' +
        'admitted to the population by the relations it reads, so an empty catalogue empties the ' +
        'population and the guard measures nothing. Check that SUPABASE_DB_URL points at a ' +
        'migrated database rather than an empty one.',
    };
  }
  return { relations: out, failure: null };
}

/** @returns {RelationMap} */
export function fetchRelationSecurity() {
  const rows = psql(
    "select c.relname, case when c.relkind in ('r','p') then 'base'" +
      " when array_to_string(coalesce(c.reloptions, '{}'), ',') ~ 'security_invoker=(true|on)'" +
      " then 'invoker' else 'definer' end" +
      ' from pg_class c join pg_namespace n on n.oid = c.relnamespace' +
      " where n.nspname = 'public' and c.relkind in ('r','p','v','m')" +
      ' union all ' +
      "select p.proname, case when p.prosecdef then 'definer' else 'invoker' end" +
      ' from pg_proc p join pg_namespace n on n.oid = p.pronamespace' +
      " where n.nspname = 'public' and p.prokind = 'f';",
  );
  const { relations, failure } = parseRelationSecurity(rows);
  if (failure !== null) {
    console.error(`pgtap refusal-assertion guard is blind: ${failure}`);
    process.exit(1);
  }
  return relations;
}

// The instrument checked end to end, on assertions written to have known
// verdicts. § 741's third vacuous refusal was scored *killed* on a dirty
// database, so "the guard ran and was green" is not evidence the guard works:
// they have to come back different. All go through the real classifier, the
// real mutant builder and the real TAP parse, and within each operator they
// differ only in WHERE the subject is:
//
//   known-good     a private route this transaction filed          must be KILLED
//   known-bad      no route at all                                 must SURVIVE
//   known-debris   a private route already committed to the DB     must SURVIVE
//
// The known-debris case is the only one that can tell a scoped operator from an
// unscoped one: before the scoping it was killed, which is a refusal scored
// healthy by a row the test never filed. Each operator needs its own set,
// because they are scoped by different mechanisms and neither proves the other
// — the definer trio reads a view whose replacement carries the scope, the base
// trio reads the table itself as a stranger and depends on the widening policy.
// The base trio's known-good is also filed inside a subtransaction, because
// pgtap's own `lives_ok` is how a test states that a write succeeded and a
// scope that misses those reports a survivor for every one of them.
/**
 * @param {RelationMap} relations
 * @returns {string[]}
 */
export function validateOperatorEndToEnd(relations) {
  const present = '00000000-0000-0000-0000-0000000e2e01';
  const absent = '00000000-0000-0000-0000-0000000e2e02';
  const stranger = '00000000-0000-0000-0000-0000000e2e03';
  const failures = [];
  const [hiddenFromPublicRoutes, privateRoute] = psql(
    'select coalesce((select r.id::text from routes r' +
      ' where not exists (select 1 from public_routes pr where pr.id = r.id)' +
      " order by r.id limit 1), '')" +
      " || '|' || coalesce((select r.id::text from routes r" +
      " where r.is_public = false order by r.id limit 1), '');",
  )
    .trim()
    .split('|');
  if (!/^[0-9a-f-]{36}$/.test(hiddenFromPublicRoutes) || !/^[0-9a-f-]{36}$/.test(privateRoute)) {
    failures.push(
      'the end-to-end control found no COMMITTED route that public_routes hides, or none that RLS hides from a ' +
        'stranger, so its known-debris cases prove nothing. seed.sql is expected to leave at least one private ' +
        'route behind; without one, an unscoped operator would pass this validation.',
    );
    return failures;
  }
  const file = [
    'begin;',
    'select plan(6);',
    `insert into routes (id, user_id, name, waypoints, distance_m, is_public)
       values ('${present}', (select id from auth.users order by id limit 1),
               'guard control', '[]'::jsonb, 1000, false);`,
    `select lives_ok($$ update routes set name = 'guard control (subtransaction)'
       where id = '${present}' $$, 'control: the fixture is filed the way pgtap files one');`,
    `select is((select count(*)::int from public_routes where id = '${present}'), 0,
       'control: a stranger cannot see the private route');`,
    `select is((select count(*)::int from public_routes where id = '${absent}'), 0,
       'control: a stranger cannot see the route nobody filed');`,
    `select is((select count(*)::int from public_routes where id = '${hiddenFromPublicRoutes}'), 0,
       'control: a stranger cannot see the private route this transaction did not file');`,
    `select set_config('request.jwt.claims', '{"sub":"${stranger}"}', true);`,
    'set local role authenticated;',
    `select is((select count(*)::int from routes where id = '${present}'), 0,
       'control: RLS hides the private route from a stranger');`,
    `select is((select count(*)::int from routes where id = '${absent}'), 0,
       'control: RLS hides the route nobody filed from a stranger');`,
    `select is((select count(*)::int from routes where id = '${privateRoute}'), 0,
       'control: RLS hides from a stranger the private route this transaction did not file');`,
    'select * from finish();',
    'rollback;',
  ].join('\n');

  const candidates = refusalAssertions(file, relations);
  if (candidates.length !== 6) {
    failures.push(
      `the end-to-end control did not classify: ${candidates.length} of its 6 assertions were selected. The population filter, not the operator, is what changed.`,
    );
    return failures;
  }
  const tap = parseTap(psql(buildMutant(file, candidates)));
  /** @type {[string, boolean, string, 'KNOWN-GOOD' | 'KNOWN-BAD' | 'KNOWN-DEBRIS'][]} */
  const verdicts = [
    ['a stranger cannot see the private route', false, 'definer', 'KNOWN-GOOD'],
    ['a stranger cannot see the route nobody filed', true, 'definer', 'KNOWN-BAD'],
    [
      'a stranger cannot see the private route this transaction did not file',
      true,
      'definer',
      'KNOWN-DEBRIS',
    ],
    ['RLS hides the private route from a stranger', false, 'base', 'KNOWN-GOOD'],
    ['RLS hides the route nobody filed from a stranger', true, 'base', 'KNOWN-BAD'],
    [
      'RLS hides from a stranger the private route this transaction did not file',
      true,
      'base',
      'KNOWN-DEBRIS',
    ],
  ];
  const why = {
    'KNOWN-GOOD':
      'A refusal with a real hidden subject must go red under the mutation; if it does not, every survivor this guard reports is unproven.',
    'KNOWN-BAD':
      'A refusal with no subject at all must stay green under the mutation; if it goes red, the mutation is revealing rows the assertion never asked about and every kill this guard reports is unproven.',
    'KNOWN-DEBRIS':
      'Its subject is a route ALREADY IN THE DATABASE that this transaction never wrote, so a kill means the mutation is revealing rows on the strength of the seed rather than of the fixture — which is what the transaction-local scope exists to stop. Check that the operator still carries it: a `subject` alias on the permissive replacement, and the widening policy on the base table.',
  };
  for (const [description, expected, operator, role] of verdicts) {
    const { status } = verdictFor(tap, `control: ${description}`);
    if (status === (expected ? 'survived' : 'killed')) continue;
    failures.push(
      `the end-to-end control's ${operator}-operator ${role} assertion ` +
        (status === 'unreached'
          ? 'never ran'
          : status === 'ambiguous'
            ? 'reported more than once, so its verdict cannot be attributed — the control fixture built two assertions with one description'
            : `was ${status === 'survived' ? 'not killed' : 'killed'} where it must ${expected ? 'survive' : 'be killed'}`) +
        `. ${why[role]}`,
    );
  }
  return failures;
}

// Run every registered permissive replacement against a subject the real
// relation provably hides, and report the ones that reveal nothing. A
// replacement that does not widen what the caller sees is an inert mutation
// dressed as a working one: it would score every assertion over that relation
// as vacuous, which is the § 741 inversion pointed the other way.
/** @returns {string[]} */
export function validateNeutralisers() {
  /** @type {string[]} */
  const failures = [];
  for (const [name, entry] of DEFINER_NEUTRALISERS) {
    const probe = entry.witness.probe.trim().replace(/;$/, '');
    const out = psql(
      `begin;\n${TRANSACTION_LOCAL_SQL}${entry.witness.setup}\nselect 'before=' || (${probe});\n` +
        `${entry.sql}\nselect 'after=' || (${probe});\nrollback;`,
    );
    /** @param {string} key */
    const read = (key) => {
      const m = new RegExp(`^${key}=(-?\\d+)$`, 'm').exec(out);
      return m ? Number(m[1]) : null;
    };
    const before = read('before');
    const after = read('after');
    if (before === null || after === null) {
      failures.push(
        `${name}: the witness did not run to completion, so the replacement is unproven. psql said: ${out.trim().split('\n').join(' / ')}`,
      );
      continue;
    }
    if (before !== 0) {
      failures.push(
        `${name}: the witness subject is visible through the REAL relation (${before} rows), so it is not a subject the relation hides and it proves nothing about the replacement. Fix witness.setup.`,
      );
      continue;
    }
    if (after <= 0) {
      failures.push(
        `${name}: the permissive replacement reveals nothing (${after} rows) where the real relation hid a subject, so the mutation is INERT. Every assertion reading ${name} would be scored vacuous for a reason that says nothing. Widen the replacement, or fix the witness if the relation's filter has moved.`,
      );
    }
  }
  return failures;
}

// The declared set of definer relations left without a replacement, checked
// against the set the suite actually reads. Both directions fail: an entry that
// no assertion reads any more is a reason kept for nothing, and a relation the
// suite reads that nobody declared is the case § 745 filed — the guard used to
// meet it for the first time at merge, as "register a permissive replacement",
// with no record of whether that had already been considered and refused.
/**
 * @param {RelationMap} relations
 * @returns {string[]}
 */
export function validateUnregisteredDefinerRelations(relations) {
  /** @type {Map<string, string[]>} */
  const found = new Map();
  /** @type {Map<string, string[]>} */
  const claimed = new Map();
  for (const file of readdirSync(TESTS_DIR).filter((f) => f.endsWith('.sql')).sort()) {
    const text = readFileSync(join(TESTS_DIR, file), 'utf8');
    for (const c of zeroOrEmptyAssertions(text, relations)) {
      for (const r of c.unmeasurable) {
        const site = `${file}:${c.line} "${c.description}"`;
        found.set(r, [...(found.get(r) ?? []), site]);
        if (!c.selected) continue;
        claimed.set(r, [...(claimed.get(r) ?? []), site]);
      }
    }
  }
  /** @type {string[]} */
  const failures = [];
  const declared = new Set(UNREGISTERED_DEFINER_RELATIONS.map((e) => e.relation));
  for (const [relation, sites] of claimed) {
    if (!declared.has(relation)) continue;
    failures.push(
      `UNREGISTERED_DEFINER_RELATIONS declares ${relation} unreplaced on the grounds that none of its assertions is a refusal, and one now is (${sites.join(', ')}). Register a permissive replacement for it and delete the entry.`,
    );
  }
  for (const [relation, sites] of found) {
    if (declared.has(relation)) continue;
    failures.push(
      `${relation} runs as its own owner, has no permissive replacement, and is read by a zero-or-empty assertion (${sites.join(', ')}). ` +
        'Either register a replacement in pgtap_definer_neutralisers.mjs, or add it to UNREGISTERED_DEFINER_RELATIONS with the reason its empty result is not an access-control claim.',
    );
  }
  for (const entry of UNREGISTERED_DEFINER_RELATIONS) {
    if (found.has(entry.relation)) continue;
    failures.push(
      `UNREGISTERED_DEFINER_RELATIONS entry ${entry.relation} is stale: no zero-or-empty assertion reads it as an unreplaced definer relation any more. It was registered, renamed or deleted — remove the entry.`,
    );
  }
  return failures;
}


// ── Positive assertions a correcting BEFORE trigger has emptied ──────────────
//
// The mirror image of everything above, and it arrived the same way: adding
// the two exercise-key stamping triggers (20270711000001) broke ONE assertion
// loudly and silently emptied two more, whose whole content was "this
// client-supplied key satisfies the CHECK" (decisions 1287). A BEFORE trigger
// that assigns `new.<col>` unconditionally makes the supplied value
// unreachable: the row that meets the constraint is the row the TRIGGER built,
// so a `lives_ok` there survives a server that had stopped folding, or
// clipping, or blanking, entirely. It is not a refusal assertion, so nothing
// above measures it; it is not a zero-or-empty read, so widening RLS says
// nothing about it.
//
// Static, deliberately. The stronger instrument is the mutation one -- disable
// the trigger and require the assertion to change -- and `exercise_key_server_
// stamped_test`'s own assertion 11 does exactly that by hand. What generalises
// cheaply is the POPULATION: which positive assertions supply a value a trigger
// overwrites. That set was invisible, which is why the emptying went unnoticed,
// and it is small (4 of the suite's 224 `lives_ok` calls at introduction).
//
// Only UNCONDITIONAL assignments count. A `freeze_*_managed_columns` or a
// privacy-zone clipper assigns inside an `if`, so whether the supplied value
// survives depends on the fixture, and a caller may legitimately be asserting
// the branch does NOT fire. An assignment at the top of the body always fires,
// so the value is always discarded and the claim is always empty.

/**
 * The body of each `create [or replace] function` in [text], keyed by name,
 * lower-cased. Later definitions win, so replaying the migrations in order
 * leaves the body the database actually has.
 * @param {string} text
 * @returns {Map<string, string>}
 */
export function functionBodies(text) {
  /** @type {Map<string, string>} */
  const out = new Map();
  for (const m of text.matchAll(/create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi)) {
    const rest = text.slice(m.index ?? 0);
    const tag = /\$[A-Za-z0-9_]*\$/.exec(rest)?.[0];
    if (tag === undefined) continue;
    const start = rest.indexOf(tag) + tag.length;
    const end = rest.indexOf(tag, start);
    if (end < 0) continue;
    out.set(m[1].toLowerCase(), rest.slice(start, end));
  }
  return out;
}

/**
 * The columns a trigger function assigns at the TOP LEVEL of its body — outside
 * every `if` and `case`, so the assignment cannot be skipped.
 * @param {string} body
 * @returns {string[]}
 */
export function unconditionalAssignments(body) {
  // One ordered pass rather than a per-line count: `end if` has to be read
  // before the bare `if` inside it, and a whole `if ... end if` written on one
  // line has to close before the next assignment is judged. `elsif` carries no
  // word boundary before its `if`, so it never opens a second block.
  const clean = body.replace(/--[^\n]*/g, '').toLowerCase();
  /** @type {Set<string>} */
  const out = new Set();
  let depth = 0;
  const tokens = /\bend\s+if\b|\bend\s+case\b|\bcase\b|\bif\b|\bnew\.([a-z0-9_]+)\s*:=/g;
  for (const m of clean.matchAll(tokens)) {
    if (m[1] !== undefined) {
      if (depth === 0) out.add(m[1]);
      continue;
    }
    if (/^end/.test(m[0])) depth = Math.max(0, depth - 1);
    else depth += 1;
  }
  return [...out];
}

/**
 * Every `<table>.<column>` a live BEFORE INSERT/UPDATE trigger stamps
 * unconditionally, mapped to the trigger that stamps it. Built by replaying the
 * migrations in version order, so a `drop trigger` retires its entry and a
 * `create or replace function` re-reads the body.
 * @param {{ name: string, text: string }[]} migrations
 * @returns {Map<string, string>}
 */
export function stampedColumns(migrations) {
  /** @type {Map<string, string>} */
  const bodies = new Map();
  /** @type {Map<string, { table: string, fn: string }>} */
  const triggers = new Map();
  for (const { text } of migrations) {
    for (const [name, body] of functionBodies(text)) bodies.set(name, body);
    for (const m of text.matchAll(
      /drop\s+trigger\s+(?:if\s+exists\s+)?([a-z0-9_]+)\s+on\s+(?:public\.)?([a-z0-9_]+)/gi,
    )) {
      triggers.delete(`${m[2].toLowerCase()}.${m[1].toLowerCase()}`);
    }
    for (const m of text.matchAll(
      /create\s+trigger\s+([a-z0-9_]+)\s+(before[^;]*?)\s+on\s+(?:public\.)?([a-z0-9_]+)([^;]*?)execute\s+(?:function|procedure)\s+(?:public\.)?([a-z0-9_]+)/gi,
    )) {
      if (!/insert|update/i.test(m[2])) continue;
      triggers.set(`${m[3].toLowerCase()}.${m[1].toLowerCase()}`, {
        table: m[3].toLowerCase(),
        fn: m[5].toLowerCase(),
      });
    }
  }
  /** @type {Map<string, string>} */
  const out = new Map();
  for (const [key, { table, fn }] of triggers) {
    const body = bodies.get(fn);
    if (body === undefined) continue;
    for (const col of unconditionalAssignments(body)) {
      out.set(`${table}.${col}`, key.slice(table.length + 1));
    }
  }
  return out;
}

/** Read the migrations off disk in version order. */
export function readMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((name) => ({ name, text: readFileSync(join(MIGRATIONS_DIR, name), 'utf8') }));
}

/**
 * The stamped columns a statement supplies a value for. An INSERT is read off
 * its column list, an UPDATE off its SET list.
 * @param {string} sql
 * @param {Map<string, string>} stamped
 * @returns {{ table: string, column: string, trigger: string }[]}
 */
export function stampedValueWrites(sql, stamped) {
  /** @type {{ table: string, column: string, trigger: string }[]} */
  const out = [];
  /** @param {string} table @param {string[]} cols */
  const collect = (table, cols) => {
    for (const col of cols) {
      const trigger = stamped.get(`${table}.${col}`);
      if (trigger !== undefined) out.push({ table, column: col, trigger });
    }
  };
  for (const m of sql.matchAll(/insert\s+into\s+(?:public\.)?([a-z0-9_]+)\s*\(([^)]*)\)/gi)) {
    collect(
      m[1].toLowerCase(),
      m[2].split(',').map((c) => c.trim().toLowerCase()),
    );
  }
  for (const m of sql.matchAll(
    /update\s+(?:public\.)?([a-z0-9_]+)\s+set\s+([\s\S]*?)(?:\bwhere\b|;|$)/gi,
  )) {
    collect(
      m[1].toLowerCase(),
      [...m[2].matchAll(/([a-z0-9_]+)\s*=/gi)].map((x) => x[1].toLowerCase()),
    );
  }
  return out;
}

/**
 * Positive assertions that deliberately supply a stamped column, with why the
 * claim survives the stamping. The staleness test below fails when an entry
 * stops naming a real one, so an exemption cannot outlive its site.
 * @type {{ file: string, description: string, reason: string }[]}
 */
export const STAMPED_VALUE_ASSERTIONS = [
  {
    file: 'exercise_key_server_stamped_test.sql',
    description: "a stale client's exercise_key is accepted rather than refused",
    reason:
      'The claim IS the acceptance -- that a key the server disagrees with no longer raises 23514 -- ' +
      'and it is deliberately paired: the very next assertion reads the stored key back and requires ' +
      "the server's fold, so the pair together says accepted AND corrected. Assertion 11 then disables " +
      'the trigger and requires the 23514 to return, which is the mutation this static scan cannot do.',
  },
  {
    file: 'exercise_key_server_stamped_test.sql',
    description: "a stale client's name_key is accepted rather than refused",
    reason:
      'The catalogue half of the entry above, paired with the same read-back and covered by the same ' +
      'trigger-disabling mutation.',
  },
];

/**
 * @param {string[]} failures
 * @param {string} summary
 */
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
  /** @type {string[]} */
  const failures = [];

  const stamped = stampedColumns(readMigrations());
  const registered = new Set(STAMPED_VALUE_ASSERTIONS.map((e) => `${e.file}\u0000${e.description}`));
  /** @type {Set<string>} */
  const matched = new Set();

  for (const file of files) {
    const text = readFileSync(join(TESTS_DIR, file), 'utf8');
    for (const call of findCalls(text, 'throws_ok')) {
      if (throwsPinsItsError(call.argv)) continue;
      failures.push(
        `${file}:${call.line}  throws_ok pins neither a SQLSTATE nor an error message, so it passes on ANY error: a typo'd table name, or a refusal at a different layer than the policy under test, satisfies it just as well.`,
      );
    }
    for (const call of findCalls(text, 'lives_ok')) {
      const sql = literalOf(call.argv[0]);
      if (sql === null) continue;
      const writes = stampedValueWrites(sql, stamped);
      if (writes.length === 0) continue;
      const description = call.argv[1] === undefined ? '' : (literalOf(call.argv[1]) ?? '');
      const key = `${file}\u0000${description}`;
      if (registered.has(key)) {
        matched.add(key);
        continue;
      }
      failures.push(
        `${file}:${call.line}  "${description}" supplies ${writes
          .map((w) => `${w.table}.${w.column}`)
          .join(', ')}, which ${writes
          .map((w) => w.trigger)
          .join(' / ')} assigns unconditionally BEFORE the row is checked — so the value this assertion supplies never reaches the constraint and the assertion survives a server that stopped deriving it at all (decisions 1324). Stop supplying the column, read the stored value back through \`returning\`, or register the assertion in STAMPED_VALUE_ASSERTIONS with the reason its claim is unaffected.`,
      );
    }
  }

  for (const entry of STAMPED_VALUE_ASSERTIONS) {
    const key = `${entry.file}\u0000${entry.description}`;
    if (matched.has(key)) continue;
    failures.push(
      `STAMPED_VALUE_ASSERTIONS entry ${entry.file} / "${entry.description}" is stale: no lives_ok there supplies a stamped column any more. It was rewritten, renamed or deleted, or its trigger is gone — remove the entry so the next one cannot hide behind it.`,
    );
  }

  if (process.argv.includes('--static-only')) {
    report(
      failures,
      `${files.length} test files scanned for unpinned negatives and for positives emptied by ` +
        `one of the ${stamped.size} unconditionally stamped columns`,
    );
    return;
  }

  if (process.argv.includes('--validate-operators')) {
    const relations = fetchRelationSecurity();
    report(
      [
        ...validateNeutralisers(),
        ...validateOperatorEndToEnd(relations),
        ...validateUnregisteredDefinerRelations(relations),
      ],
      `all ${DEFINER_NEUTRALISERS.size} permissive replacements reveal a subject their real relation hides that ` +
        `THIS transaction filed, both operators' end-to-end controls kill their known-good assertion while leaving ` +
        `their known-bad and their known-debris one standing, and the ${UNREGISTERED_DEFINER_RELATIONS.length} ` +
        `declared unreplaced definer relations are still exactly the ones the suite reads`,
    );
    return;
  }

  const relations = fetchRelationSecurity();
  /** @type {{ file: string, line: number, description: string, neutralise: string[] }[]} */
  const survivors = [];
  let population = 0;
  let definerPopulation = 0;

  for (const file of files) {
    const text = readFileSync(join(TESTS_DIR, file), 'utf8');
    const candidates = refusalAssertions(text, relations);
    if (candidates.length === 0) continue;
    const unmeasurable = candidates.filter((c) => c.unmeasurable.length > 0);
    for (const c of unmeasurable) {
      failures.push(
        `${file}:${c.line}  "${c.description}" reads ${c.unmeasurable.join(', ')}, which runs as its own owner and filters in its own SQL — widening row-level security leaves its result identical, so no operator here can tell this assertion's refusal from an empty fixture. Register a permissive replacement in pgtap_definer_neutralisers.mjs.`,
      );
    }
    const measurable = candidates.filter((c) => c.unmeasurable.length === 0);
    if (measurable.length === 0) continue;
    population += measurable.length;
    definerPopulation += measurable.filter((c) => c.neutralise.length > 0).length;
    const tap = parseTap(psql(buildMutant(text, measurable)));
    for (const candidate of measurable) {
      const { status, count } = verdictFor(tap, candidate.description);
      if (status === 'unreached') {
        failures.push(
          `${file}:${candidate.line}  the mutant run never reached "${candidate.description}", so the guard could not measure it.` +
            (lastPsqlErrors.length > 0 ? ` psql said: ${lastPsqlErrors.join(' / ')}` : ''),
        );
        continue;
      }
      if (status === 'ambiguous') {
        failures.push(
          `${file}:${candidate.line}  ${count} assertions in this file report under the description "${candidate.description}", and the TAP stream offers no other handle on a call site — so the guard cannot tell which verdict belongs to this one, and a vacuous refusal would be scored on its twin's result. Give each assertion a description of its own. EXPECTED_SURVIVORS keys on the same string, so a duplicate would also let one entry excuse two assertions.`,
        );
        continue;
      }
      if (status === 'survived') {
        survivors.push({
          file,
          line: candidate.line,
          description: candidate.description,
          neutralise: candidate.neutralise,
        });
      }
    }
  }

  const excused = new Set(EXPECTED_SURVIVORS.map((e) => `${e.file} ${e.description}`));
  for (const s of survivors) {
    if (excused.has(`${s.file} ${s.description}`)) continue;
    failures.push(
      `${s.file}:${s.line}  "${s.description}" still passes with ` +
        (s.neutralise.length > 0
          ? `${s.neutralise.join(', ')} replaced by a permissive definition over the rows THIS TRANSACTION wrote`
          : 'row-level access control widened to every row THIS TRANSACTION wrote') +
        `, so it cannot tell a hidden row from a row that was never inserted. Give it a subject (file the row the refusal is about, and read it back from a session that may see it) — a row the test only SELECTs is not one it filed, and the permissive replacement is deliberately scoped so a committed seed row cannot stand in for a missing fixture; if the relation it reads filters in its own SQL, register a permissive replacement for it; or add it to EXPECTED_SURVIVORS with the reason its empty result is a real answer.`,
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
    `${population} refusal assertions mutation-checked across ${files.length} test files ` +
      `(${population - definerPopulation} under a permissive policy over the rows this transaction wrote, ` +
      `${definerPopulation} under a ` +
      `permissive replacement of the relation they read); ` +
      `${survivors.length} survived, all ${EXPECTED_SURVIVORS.length} of them expected`,
  );
}

if (import.meta.url === `file://${process.argv[1]}`) main();
