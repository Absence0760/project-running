/// A truncation a caller cannot detect is a lie about their history.
///
/// Both scrapers in this tier bound their result set and neither could say so.
/// `parkrun-import` stopped at `MAX_PARKRUN_ROWS` and answered
/// `{ imported, skipped }`, where `skipped` means "already had it".
/// `race-results-import`'s three extractors stop at `MAX_RESULTS_ROWS` and
/// answered `{ imported, skipped, enriched }`. The Strava side already litigates
/// this shape — `parseStravaSyncResult` treats an absent `complete` as PARTIAL
/// on purpose, because a false "complete" is what stops a runner syncing again
/// — and the same rule applies here: one transport, shipped alongside its
/// callers, and the same asymmetry of costs (decisions § 976).
///
/// The race-results half is the reachable one. `runSignUpResultsUrl` narrows
/// upstream by USER ID only, so a request scoped by bib alone fetches the whole
/// finisher field and `filterResultsByBib` narrows afterwards — a major with
/// 30,000 finishers truncates at 2,000 BEFORE the bib filter, and the runner is
/// told nothing was found.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/_shared/import_truncation.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  MAX_RESULTS_ROWS,
  extractRunSignUpResults,
  filterResultsByBib,
  mapRunSignUpResult,
  resultsPossiblyTruncated,
  type MappedRaceRun,
} from '../race-results-import/lib.ts';
import { MAX_PARKRUN_ROWS } from '../parkrun-import/lib.ts';

const PARKRUN_SRC = Deno.readTextFileSync(
  new URL('../parkrun-import/index.ts', import.meta.url),
);
const RACE_SRC = Deno.readTextFileSync(
  new URL('../race-results-import/index.ts', import.meta.url),
);

Deno.test('a field bigger than the cap is reported as possibly truncated', () => {
  assertEquals(resultsPossiblyTruncated(MAX_RESULTS_ROWS - 1), false);
  // Exactly at the cap reads as possibly truncated: a page carrying exactly
  // MAX_RESULTS_ROWS is indistinguishable from one that carried more, and a
  // false "possibly" costs a sentence where a false "complete" costs a runner
  // the belief that they were not in a race they finished.
  assertEquals(resultsPossiblyTruncated(MAX_RESULTS_ROWS), true);
  assertEquals(resultsPossiblyTruncated(MAX_RESULTS_ROWS + 1), true);
});

Deno.test('the bib a caller asked for can sit past the cap, and the fetch cannot see it', () => {
  // The reachable shape, driven rather than described: 30,000 finishers, the
  // caller is bib 25000, the request is bib-scoped (no RunSignUp user id) so
  // the API returned the whole field.
  const field = {
    results: Array.from({ length: 30_000 }, (_, i) => ({
      bib_num: String(i + 1),
      chip_time: '3:11:22',
    })),
  };
  const rows = extractRunSignUpResults(field);
  assertEquals(rows.length, MAX_RESULTS_ROWS);
  assertEquals(resultsPossiblyTruncated(rows.length), true);
  const mapped = rows
    .map((r) =>
      mapRunSignUpResult(r, {
        userId: 'u-1',
        listingId: 'L-1',
        raceName: 'Some Major',
        raceDate: '2026-04-20',
        distanceM: 42195,
        isPublic: false,
      })
    )
    .filter((r): r is MappedRaceRun => r !== null);
  assertEquals(filterResultsByBib(mapped, '25000').length, 0);
});

Deno.test('race-results refuses instead of reporting a successful import of nothing', () => {
  const zero = RACE_SRC.indexOf('if (mapped.length === 0) {');
  assert(zero !== -1, 'the empty-mapping branch is gone');
  const branch = RACE_SRC.slice(zero, zero + 900);
  assert(
    /if \(!complete\) \{[\s\S]*?upstream_results_truncated[\s\S]*?status: 502/.test(branch),
    'a truncated fetch that matched nothing must refuse, not answer imported: 0',
  );
  // And every success answer states the claim rather than leaving it inferred.
  for (const shape of [/enriched: 1, complete \}/, /enriched: 0, complete \}/]) {
    assert(shape.test(RACE_SRC), `a success response omits complete: ${shape}`);
  }
});

Deno.test('parkrun counts past its cap instead of stopping at it', () => {
  // The early `return false` bounded the result set AND destroyed the evidence
  // that it had been bounded. The bound now lives on the push alone.
  assert(
    !/if \(runs\.length >= MAX_PARKRUN_ROWS\) return false;/.test(PARKRUN_SRC),
    'the walk still stops dead at the cap, so nothing can count what it left',
  );
  const usable = PARKRUN_SRC.indexOf('usable++;');
  const cap = PARKRUN_SRC.indexOf('if (runs.length >= MAX_PARKRUN_ROWS) return;');
  assert(usable !== -1, 'nothing counts the usable results');
  assert(cap !== -1, 'the result set is no longer bounded at all');
  assert(usable < cap, 'the count must happen before the cap returns, or it counts nothing past it');
  assert(
    /return Response\.json\(\{ imported, skipped, total: usable, complete: usable <= MAX_PARKRUN_ROWS \}\);/
      .test(PARKRUN_SRC),
    'the parkrun response must state completeness and the total the page carried',
  );
  assert(MAX_PARKRUN_ROWS > 0, 'the cap is the subject; a zero cap makes every claim vacuous');
});
