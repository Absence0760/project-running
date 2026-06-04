/**
 * Stable IDs for seed rows the e2e suite navigates to by URL.
 *
 * Most seed rows (the 12 runs runner has, the 12 alex has, the 13
 * morgan has) get auto-generated UUIDs at insert time — fine for
 * "list contains N rows" assertions but useless when a spec needs
 * `/runs/<id>` or `/share/run/<id>` deterministically.
 *
 * The IDs below are pinned in `apps/backend/supabase/seed.sql` so
 * tests can reference them as literals. Keep both files in lockstep
 * — a typo here surfaces as 404 in the test, not a confusing seed
 * failure.
 */

/** A public run owned by USER_A (runner@test.com). Most-recent so it
 *  sorts to the top of /history + /feed. Test title: "E2E demo public run". */
export const RUNNER_PUBLIC_RUN_ID = '11112222-3333-4444-5555-666677778888';

/** A private run owned by USER_B (alex@test.com). Used by the
 *  cross-user-isolation security tests to assert that USER_A
 *  navigating to /runs/<this> sees the not-found state, not the run. */
export const ALEX_PRIVATE_RUN_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

/** A public route owned by USER_A (runner@test.com). Used by anon
 *  /share/route/<id> tests so they don't have to scrape /routes for
 *  the first public id. Test name: "E2E demo public route". */
export const RUNNER_PUBLIC_ROUTE_ID = '22223333-4444-5555-6666-777788889999';
