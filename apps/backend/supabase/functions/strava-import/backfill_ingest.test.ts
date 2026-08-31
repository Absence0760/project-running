/// What the page walk INGESTS, and what it tells the runner about it.
///
/// The sibling suite drives every exit of the loop, but every fixture activity
/// in it is a `Ride`, so no page it walks ever reaches `ingestActivity`: the
/// three counters the two clients render — imported, skipped, failed — are
/// returned by a code path that suite never enters, and neither is the
/// `privacy_default` resolution that decides whether an imported run is
/// published. Both are exercised here.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/strava-import/backfill_ingest.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { backfill } from './backfill.ts';

interface FakeActivity {
  id: number;
  sport_type?: string;
  type?: string;
  start_date: string;
  distance: number;
  moving_time?: number;
  elapsed_time?: number;
  name?: string;
  total_elevation_gain?: number;
  average_heartrate?: number;
}

interface StubOptions {
  prefs?: Record<string, unknown> | null;
  prefsThrows?: boolean;
  stravaIds?: string[];
  existingRuns?: Array<{ started_at: string | null; distance_m: number | null }>;
  failInsertFor?: (row: Record<string, unknown>) => boolean;
}

interface Stub {
  client: DbClient;
  inserted: Array<Record<string, unknown>>;
  integrationPatches: Array<Record<string, unknown>>;
}

function dbStub(opts: StubOptions = {}): Stub {
  const inserted: Array<Record<string, unknown>> = [];
  const integrationPatches: Array<Record<string, unknown>> = [];
  let insertSeq = 0;
  // deno-lint-ignore no-explicit-any
  const chain = (result: unknown): any => ({
    select: () => chain(result),
    eq: () => chain(result),
    order: () => chain(result),
    range: () => chain(result),
    maybeSingle: () => Promise.resolve(result),
    single: () => Promise.resolve(result),
    // deno-lint-ignore no-explicit-any
    then: (res: any, rej: any) => Promise.resolve(result).then(res, rej),
  });
  const client = {
    from(table: string) {
      if (table === 'user_settings') {
        if (opts.prefsThrows) {
          return {
            select: () => ({
              eq: () => ({
                maybeSingle: () => Promise.reject(new Error('prefs read failed')),
              }),
            }),
          };
        }
        return chain({ data: { prefs: opts.prefs ?? null }, error: null });
      }
      if (table === 'runs') {
        return {
          select: (cols: string) =>
            chain({
              data: cols.includes('metadata')
                ? (opts.stravaIds ?? []).map((id) => ({ metadata: { strava_id: id } }))
                : (opts.existingRuns ?? []),
              error: null,
            }),
          insert: (row: Record<string, unknown>) => {
            inserted.push(row);
            const fails = opts.failInsertFor?.(row) === true;
            return chain(
              fails
                ? { data: null, error: { code: '23505', message: 'duplicate' } }
                : { data: { id: `run_${++insertSeq}` }, error: null },
            );
          },
          update: () => chain({ data: null, error: null }),
        };
      }
      return {
        select: () => chain({ data: { sync_cursor: null }, error: null }),
        update: (patch: Record<string, unknown>) => {
          integrationPatches.push(patch);
          return chain({ data: null, error: null });
        },
      };
    },
  } as unknown as DbClient;
  return { client, inserted, integrationPatches };
}

const DAY_MS = 86400_000;
const BASE_MS = Date.now() - 30 * DAY_MS;
const iso = (offsetMs: number) => new Date(BASE_MS + offsetMs).toISOString();

const activity = (over: Partial<FakeActivity> & { id: number }): FakeActivity => ({
  sport_type: 'Run',
  start_date: iso(over.id * 60_000),
  distance: 5000,
  moving_time: 1800,
  elapsed_time: 1900,
  ...over,
});

/// Serve one page of activities, then an empty page that ends the window. The
/// activity-streams fetch answers 404, which is what Strava returns for a short
/// or indoor activity and the path `ingestActivity` treats as "no track".
async function walk(
  stub: Stub,
  activities: FakeActivity[],
  run: (result: Awaited<ReturnType<typeof backfill>>, urls: string[]) => void | Promise<void>,
): Promise<void> {
  const urls: string[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    urls.push(url);
    if (url.includes('/streams')) return Promise.resolve(new Response('{}', { status: 404 }));
    const first = urls.filter((u) => u.includes('athlete/activities')).length === 1;
    return Promise.resolve(
      new Response(JSON.stringify(first ? activities : []), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    );
  }) as typeof fetch;
  try {
    await run(await backfill(stub.client, 'u1', 'tok', 90), urls);
  } finally {
    globalThis.fetch = original;
  }
}

Deno.test('the three counters are what the walk actually did, one of each', async () => {
  // A helper that returned constants would satisfy any single-counter test.
  // One page produces one of every outcome at once.
  const stub = dbStub({
    stravaIds: ['200'],
    failInsertFor: (row) => String(row.external_id) === 'strava:300',
  });
  await walk(
    stub,
    [
      activity({ id: 100 }),
      activity({ id: 200 }),
      activity({ id: 300 }),
      activity({ id: 400, sport_type: 'Ride' }),
    ],
    (r) => {
      assertEquals(r.imported, 1, 'only the fresh run-family activity is imported');
      assertEquals(r.skipped, 1, 'the already-imported strava id is skipped');
      assertEquals(r.failed, 1, 'the refused insert is counted, not swallowed');
      assertEquals(r.complete, true);
      assertEquals(r.resumable, false);
    },
  );
  // The Ride never reached the insert, so it is in none of the three.
  assertEquals(stub.inserted.map((r) => r.external_id), ['strava:100', 'strava:300']);
});

Deno.test('a refused insert does not stop the rest of the page', async () => {
  const stub = dbStub({ failInsertFor: (row) => String(row.external_id) === 'strava:100' });
  await walk(stub, [activity({ id: 100 }), activity({ id: 101 }), activity({ id: 102 })], (r) => {
    assertEquals(r.failed, 1);
    assertEquals(r.imported, 2);
  });
  assertEquals(stub.inserted.length, 3);
});

Deno.test('an imported run is private unless the runner\'s default is literally public', async () => {
  // Publishing a runner's history because a preference could not be read is the
  // one direction that cannot be undone from here, so every unreadable answer
  // has to land on private.
  const publishes: Array<Record<string, unknown> | null> = [{ privacy_default: 'public' }];
  const withholds: Array<Record<string, unknown> | null> = [
    null,
    {},
    { privacy_default: 'followers' },
    { privacy_default: 'private' },
    { privacy_default: 'Public' },
    { privacy_default: 'PUBLIC' },
    { privacy_default: true },
    { privacy_default: null },
    { privacy_default: ['public'] },
  ];
  for (const prefs of publishes) {
    const stub = dbStub({ prefs });
    await walk(stub, [activity({ id: 1 })], () => {});
    assertEquals(stub.inserted[0].is_public, true, JSON.stringify(prefs));
  }
  for (const prefs of withholds) {
    const stub = dbStub({ prefs });
    await walk(stub, [activity({ id: 1 })], () => {});
    assertEquals(stub.inserted[0].is_public, false, JSON.stringify(prefs));
  }
});

Deno.test('a preference read that throws imports privately rather than failing the sync', async () => {
  const stub = dbStub({ prefsThrows: true });
  await walk(stub, [activity({ id: 1 })], (r) => {
    assertEquals(r.imported, 1);
    assertEquals(r.complete, true);
  });
  assertEquals(stub.inserted[0].is_public, false);
});

Deno.test('the same effort already present under another source is skipped, not re-inserted', async () => {
  // The `metadata.strava_id` set only catches a re-import of the same Strava
  // activity. A Garmin watch that auto-uploaded to Strava arrives here as a
  // different id for a run the database already has.
  const start = iso(60_000);
  const stub = dbStub({ existingRuns: [{ started_at: start, distance_m: 5000 }] });
  await walk(stub, [activity({ id: 1, start_date: start, distance: 5040 })], (r) => {
    assertEquals(r.skipped, 1);
    assertEquals(r.imported, 0);
  });
  assertEquals(stub.inserted.length, 0);
});

Deno.test('a different effort at a similar time is still imported', async () => {
  // The complement, so "skips everything" is not what makes the case above
  // pass: beyond the 5 % distance tolerance the two are different runs.
  const start = iso(60_000);
  const stub = dbStub({ existingRuns: [{ started_at: start, distance_m: 5000 }] });
  await walk(stub, [activity({ id: 1, start_date: start, distance: 9000 })], (r) => {
    assertEquals(r.imported, 1);
    assertEquals(r.skipped, 0);
  });
});

Deno.test('the run-family filter decides the activity_type, and a ride reaches nothing', async () => {
  const cases: Array<[Partial<FakeActivity>, string | null]> = [
    [{ sport_type: 'Run' }, 'run'],
    [{ sport_type: 'TrailRun' }, 'run'],
    [{ sport_type: 'VirtualRun' }, 'run'],
    [{ sport_type: 'Walk' }, 'walk'],
    [{ sport_type: 'Hike' }, 'hike'],
    [{ sport_type: undefined, type: 'Run' }, 'run'],
    [{ sport_type: 'Ride' }, null],
    [{ sport_type: 'Swim' }, null],
    [{ sport_type: 'AlpineSki' }, null],
    [{ sport_type: '' }, null],
  ];
  for (const [over, want] of cases) {
    const stub = dbStub();
    await walk(stub, [activity({ id: 1, ...over })], () => {});
    if (want === null) {
      assertEquals(stub.inserted.length, 0, JSON.stringify(over));
    } else {
      assertEquals(stub.inserted.length, 1, JSON.stringify(over));
      assertEquals(stub.inserted[0].activity_type, want, JSON.stringify(over));
    }
  }
});

Deno.test('the inserted row carries the two dedupe keys the next sync reads back', async () => {
  // `metadata.strava_id` is what the next walk's `seen` set is built from and
  // `external_id` is the cross-source key. A row written without either is a
  // run that will be imported again on the very next sync.
  const stub = dbStub();
  await walk(stub, [activity({ id: 987654321, name: 'Hill reps', total_elevation_gain: 210.4 })], () => {});
  const row = stub.inserted[0];
  assertEquals(row.external_id, 'strava:987654321');
  assertEquals(row.source, 'strava');
  const metadata = row.metadata as Record<string, unknown>;
  assertEquals(metadata.strava_id, '987654321');
  assertEquals(typeof metadata.strava_id, 'string', 'a number here breaks every string reader');
  assertEquals(metadata.title, 'Hill reps');
  assertEquals(metadata.elevation_m, 210);
  // The promoted column the vert aggregates SUM, beside the jsonb key.
  assertEquals(row.elevation_gain_m, 210);
});

Deno.test('every page fetch carries the access token', async () => {
  // Nothing else in this suite reads the request headers, so a walk that
  // dropped the bearer would look identical to one that kept it until it met
  // Strava.
  const seen: Array<string | null> = [];
  const original = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    const headers = new Headers(init?.headers);
    seen.push(headers.get('Authorization'));
    if (url.includes('/streams')) return Promise.resolve(new Response('{}', { status: 404 }));
    return Promise.resolve(
      new Response(JSON.stringify(seen.length === 1 ? [activity({ id: 1 })] : []), { status: 200 }),
    );
  }) as typeof fetch;
  try {
    await backfill(dbStub().client, 'u1', 'tok-abc', 90);
  } finally {
    globalThis.fetch = original;
  }
  assert(seen.length >= 2, 'the walk made at least two requests');
  for (const value of seen) assertEquals(value, 'Bearer tok-abc');
});

Deno.test('resumable and complete are never both true, on every exit', async () => {
  // `resumable` is an instruction ("syncing again picks up where it stopped")
  // and `complete` is its opposite. A response claiming both is a client
  // choosing arbitrarily between two contradictory sentences.
  const responders: Array<[string, () => Response]> = [
    ['end of window', () => new Response('[]', { status: 200 })],
    ['short page', () => new Response(JSON.stringify([activity({ id: 1 })]), { status: 200 })],
    ['throttle', () => new Response('', { status: 429 })],
    ['upstream error', () => new Response('', { status: 500 })],
    ['not an array', () => new Response('{"error":"nope"}', { status: 200 })],
    ['not json at all', () => new Response('<html>502</html>', { status: 200 })],
  ];
  for (const [label, responder] of responders) {
    const original = globalThis.fetch;
    globalThis.fetch = ((input: string | URL | Request) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
      if (url.includes('/streams')) return Promise.resolve(new Response('{}', { status: 404 }));
      return Promise.resolve(responder());
    }) as typeof fetch;
    try {
      const r = await backfill(dbStub().client, 'u1', 'tok', 90);
      assert(!(r.complete && r.resumable), `${label} claimed both`);
      assert(!(r.rate_limited && r.complete), `${label} claimed a throttle and completeness`);
      if (label === 'throttle') assertEquals(r.rate_limited, true);
      else assertEquals(r.rate_limited, false, label);
    } finally {
      globalThis.fetch = original;
    }
  }
});

Deno.test('a transport failure keeps every run it had already ingested', async () => {
  // The activities are in the database either way; the only thing a thrown
  // fetch changes is whether the runner is told about them. Before § 768 this
  // exit propagated into `withSentry` and answered 500, so the counts were
  // discarded along with the report.
  const stub = dbStub();
  const original = globalThis.fetch;
  let page = 0;
  globalThis.fetch = ((input: string | URL | Request) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (url.includes('/streams')) return Promise.resolve(new Response('{}', { status: 404 }));
    page++;
    if (page === 1) {
      return Promise.resolve(
        new Response(
          JSON.stringify(Array.from({ length: 50 }, (_, i) => activity({ id: i + 1 }))),
          { status: 200 },
        ),
      );
    }
    return Promise.reject(new TypeError('connection reset'));
  }) as typeof fetch;
  try {
    const r = await backfill(stub.client, 'u1', 'tok', 90);
    assertEquals(r.imported, 50);
    assertEquals(r.complete, false);
    assertEquals(r.rate_limited, false);
  } finally {
    globalThis.fetch = original;
  }
  assertEquals(stub.inserted.length, 50);
});
