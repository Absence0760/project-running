/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/_shared/external_id_batch.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { reconcileImportBatch } from './external_id_batch.ts';

const row = (id: string, tag = '') => ({ external_id: id, tag });

Deno.test('reconcileImportBatch — a repeat inside the batch is dropped, not inserted twice', () => {
  // The bug this exists for: `runs_user_external_id` is a per-user unique
  // index and the importers insert in ONE statement, so a second row with the
  // same id raises 23505 and loses the whole batch. RunSignUp reaches this by
  // flattening `individual_results_sets[]`, where one runner's bib appears in
  // every set the race posted.
  const out = reconcileImportBatch(
    [row('race:X:2026-04-15:101', 'set-a'), row('race:X:2026-04-15:101', 'set-b')],
    [],
  );
  assertEquals(out.fresh.length, 1);
  assertEquals(out.fresh[0].tag, 'set-a', 'first occurrence wins — the callers build in upstream order');
  assertEquals(out.skipped, 1);
});

Deno.test('reconcileImportBatch — three copies of one id still yield one row', () => {
  const out = reconcileImportBatch(
    [row('parkrun:Bushy:15/04/2026'), row('parkrun:Bushy:15/04/2026'), row('parkrun:Bushy:15/04/2026')],
    [],
  );
  assertEquals(out.fresh.map((r) => r.external_id), ['parkrun:Bushy:15/04/2026']);
  assertEquals(out.skipped, 2);
});

Deno.test('reconcileImportBatch — an already-stored id is dropped, as it always was', () => {
  const out = reconcileImportBatch(
    [row('race:X:2026-04-15:101'), row('race:X:2026-04-15:102')],
    ['race:X:2026-04-15:101'],
  );
  assertEquals(out.fresh.map((r) => r.external_id), ['race:X:2026-04-15:102']);
  assertEquals(out.skipped, 1);
});

Deno.test('reconcileImportBatch — a stored id and a batch repeat are counted the same way', () => {
  // Both are "not imported, and not lost either". The caller reports one
  // `skipped` number and it has to mean that for both reasons.
  const rows = [
    row('a', 'stored'),
    row('b', 'new'),
    row('b', 'repeat-of-new'),
    row('a', 'repeat-of-stored'),
  ];
  const out = reconcileImportBatch(rows, ['a']);
  assertEquals(out.fresh.map((r) => r.tag), ['new']);
  assertEquals(out.skipped, 3);
});

Deno.test('reconcileImportBatch — skipped is always the arithmetic complement of fresh', () => {
  // The subtraction used to be written out at each call site, so the two
  // could disagree about what a duplicate meant. It is returned here so it
  // cannot.
  for (const [rows, stored] of [
    [[], []],
    [[row('a')], []],
    [[row('a'), row('a')], []],
    [[row('a'), row('b')], ['a', 'b']],
    [[row('a'), row('b'), row('a')], ['b']],
  ] as [ReturnType<typeof row>[], string[]][]) {
    const out = reconcileImportBatch(rows, stored);
    assertEquals(
      out.skipped,
      rows.length - out.fresh.length,
      `skipped disagreed with fresh for ${JSON.stringify(rows.map((r) => r.external_id))}`,
    );
  }
});

Deno.test('reconcileImportBatch — order is the input order, unshuffled', () => {
  const out = reconcileImportBatch(
    [row('c'), row('a'), row('b'), row('a')],
    [],
  );
  assertEquals(out.fresh.map((r) => r.external_id), ['c', 'a', 'b']);
});

Deno.test('reconcileImportBatch — nothing stored and nothing repeated passes everything through', () => {
  // The positive control beside the negatives above: the helper must not be a
  // filter that happens to empty the batch.
  const rows = [row('a'), row('b'), row('c')];
  const out = reconcileImportBatch(rows, []);
  assertEquals(out.fresh.length, 3);
  assertEquals(out.skipped, 0);
  assert(out.fresh[0] === rows[0], 'the rows themselves are passed through, not copies');
});

Deno.test('reconcileImportBatch — an empty batch is not an error', () => {
  const out = reconcileImportBatch([], ['a', 'b']);
  assertEquals(out.fresh, []);
  assertEquals(out.skipped, 0);
});

Deno.test('reconcileImportBatch — the stored set may be any iterable, and is not mutated', () => {
  // The callers pass a mapped array off a PostgREST read; the helper builds
  // its own Set so a later read of that array still sees what came back.
  const stored = ['a'];
  const out = reconcileImportBatch([row('a'), row('b')], stored);
  assertEquals(out.fresh.map((r) => r.external_id), ['b']);
  assertEquals(stored, ['a'], 'the caller-supplied stored ids must survive the call');
});

// ── the two call sites ───────────────────────────────────────────────────────
//
// The helper is only worth having if both importers actually go through it.
// Each of them reached the bug by writing the reconciliation out inline, so the
// guard is on the shape, not merely on the import: an index.ts that re-derives
// `fresh` from a `Set` of its own is the pre-fix code back again.

const IMPORTERS = ['../parkrun-import/index.ts', '../race-results-import/index.ts'] as const;

Deno.test('both run importers reconcile through this helper, not inline', async () => {
  for (const rel of IMPORTERS) {
    const src = await Deno.readTextFile(new URL(rel, import.meta.url));
    assert(
      src.includes("from '../_shared/external_id_batch.ts'"),
      `${rel} no longer imports the batch reconciliation`,
    );
    assert(
      src.includes('reconcileImportBatch('),
      `${rel} imports the helper but never calls it`,
    );
    assert(
      !/const fresh = \w+\s*\n?\s*\.?filter\(\(r\) => !seen\.has\(/.test(src),
      `${rel} still derives its insert batch from a local Set — that is the shape ` +
        'that could not see a duplicate inside its own batch',
    );
  }
});

Deno.test('neither importer inserts before it has reconciled', async () => {
  // Order is the whole point: reconciling AFTER the insert would leave the
  // 23505 exactly where it was.
  for (const rel of IMPORTERS) {
    const src = await Deno.readTextFile(new URL(rel, import.meta.url));
    const reconcile = src.indexOf('reconcileImportBatch(');
    const insert = src.indexOf(".from('runs').insert(");
    assert(reconcile !== -1, `${rel}: no reconciliation`);
    assert(insert !== -1, `${rel}: the runs insert is gone — has the importer moved?`);
    assert(
      reconcile < insert,
      `${rel}: the batch must be reconciled before the single-statement insert`,
    );
  }
});
