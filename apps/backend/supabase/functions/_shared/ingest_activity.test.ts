/// `ingestActivity` on its own — the one writer both Strava paths share.
///
/// `strava-import` reaches it through `backfill` and `strava-webhook` calls it
/// directly, so its defensive arms belong to neither suite and were exercised
/// by neither. The two that matter are a refusal and a default: it rejects a
/// non-run-family payload even though both callers pre-filter (a Strava-side
/// reclassification arriving mid-flight would otherwise ship ride load into
/// weekly mileage as a run), and `isPublic` defaults to private so a caller
/// that does not resolve the runner's `privacy_default` — which the webhook
/// path does not — cannot publish their history.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/_shared/ingest_activity.test.ts`.

import { assert, assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from './database.ts';
import { ingestActivity, type StravaActivity } from './strava.ts';

interface Recorded {
  client: DbClient;
  inserted: Array<Record<string, unknown>>;
}

function dbStub(insertFails = false): Recorded {
  const inserted: Array<Record<string, unknown>> = [];
  // deno-lint-ignore no-explicit-any
  const chain = (result: unknown): any => ({
    select: () => chain(result),
    eq: () => chain(result),
    single: () => Promise.resolve(result),
    // deno-lint-ignore no-explicit-any
    then: (res: any, rej: any) => Promise.resolve(result).then(res, rej),
  });
  const client = {
    from: () => ({
      insert: (row: Record<string, unknown>) => {
        inserted.push(row);
        return chain(
          insertFails
            ? { data: null, error: { code: '23505', message: 'duplicate key' } }
            : { data: { id: 'run_1' }, error: null },
        );
      },
      update: () => chain({ data: null, error: null }),
      select: () => chain({ data: [], error: null }),
    }),
  } as unknown as DbClient;
  return { client, inserted };
}

const act = (over: Partial<StravaActivity> = {}): StravaActivity => ({
  id: 12345,
  sport_type: 'Run',
  type: 'Run',
  start_date: '2026-06-01T06:00:00Z',
  distance: 5000,
  moving_time: 1500,
  elapsed_time: 1600,
  ...over,
} as StravaActivity);

/// Every activity here is under the 200 m threshold that triggers the stream
/// fetch, so no case reaches the network. The distance-bearing cases stub
/// `fetch` to a 404 instead, which is what Strava answers for an activity with
/// no stream and the branch `ingestActivity` treats as "no track".
async function withNoStreams(run: () => Promise<void>): Promise<void> {
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response('{}', { status: 404 }))) as typeof fetch;
  try {
    await run();
  } finally {
    globalThis.fetch = original;
  }
}

Deno.test('ingestActivity — a non-run-family payload is refused, and the row is never written', async () => {
  const rejected = ['Ride', 'Swim', 'AlpineSki', 'WeightTraining', 'Yoga', ''];
  for (const sport of rejected) {
    const db = dbStub();
    await assertRejects(
      () => ingestActivity(db.client, 'u1', 'tok', act({ sport_type: sport, type: sport, distance: 100 })),
      Error,
      'ingestActivity rejected non-run-family sport',
      sport,
    );
    assertEquals(db.inserted.length, 0, sport);
  }
});

Deno.test('ingestActivity — the refusal names the sport and the activity, so a log line is actionable', async () => {
  const db = dbStub();
  const err = await ingestActivity(db.client, 'u1', 'tok', act({ sport_type: 'Ride', type: 'Ride', distance: 100 }))
    .then(() => null, (e: unknown) => e as Error);
  assert(err !== null);
  assert(err.message.includes('Ride'), err.message);
  assert(err.message.includes('12345'), err.message);
  // An empty sport is reported as such rather than as a blank in the sentence.
  const blank = await ingestActivity(db.client, 'u1', 'tok', act({ sport_type: '', type: '', distance: 100 }))
    .then(() => null, (e: unknown) => e as Error);
  assert(blank !== null);
  assert(blank.message.includes('<empty>'), blank.message);
});

Deno.test('ingestActivity — the legacy `type` field is honoured when `sport_type` is absent', async () => {
  // Strava's modern field is `sport_type`; older payloads carry only `type`,
  // and a reader that looked at one of them would refuse half the corpus.
  const db = dbStub();
  await ingestActivity(
    db.client,
    'u1',
    'tok',
    { ...act({ distance: 100 }), sport_type: undefined } as StravaActivity,
  );
  assertEquals(db.inserted.length, 1);
  assertEquals(db.inserted[0].activity_type, 'run');
});

Deno.test('ingestActivity — an imported run is private unless the caller says otherwise', async () => {
  // The default is what the deprecated `strava-webhook` rollback path gets: it
  // resolves no preference, so the parameter it omits must not publish.
  const withDefault = dbStub();
  await ingestActivity(withDefault.client, 'u1', 'tok', act({ distance: 100 }));
  assertEquals(withDefault.inserted[0].is_public, false);

  const explicitFalse = dbStub();
  await ingestActivity(explicitFalse.client, 'u1', 'tok', act({ distance: 100 }), false);
  assertEquals(explicitFalse.inserted[0].is_public, false);

  const explicitTrue = dbStub();
  await ingestActivity(explicitTrue.client, 'u1', 'tok', act({ distance: 100 }), true);
  assertEquals(explicitTrue.inserted[0].is_public, true, 'and the caller can still publish');
});

Deno.test('ingestActivity — a refused insert throws so the caller can count it as failed', async () => {
  // `backfill` counts a throw as `failed`. A resolve on an insert error would
  // report the run as imported and lose it silently.
  const db = dbStub(true);
  await assertRejects(() => ingestActivity(db.client, 'u1', 'tok', act({ distance: 100 })));
  assertEquals(db.inserted.length, 1, 'the write really was attempted');
});

Deno.test('ingestActivity — the duration falls back to elapsed time when nothing was moving', async () => {
  const cases: Array<[Partial<StravaActivity>, number]> = [
    [{ moving_time: 1500, elapsed_time: 1600 }, 1500],
    [{ moving_time: 0, elapsed_time: 1600 }, 1600],
    [{ moving_time: undefined, elapsed_time: 1600 }, 1600],
  ];
  for (const [over, want] of cases) {
    const db = dbStub();
    await ingestActivity(db.client, 'u1', 'tok', act({ ...over, distance: 100 }));
    assertEquals(db.inserted[0].duration_s, want, JSON.stringify(over));
  }
});

Deno.test('ingestActivity — the elevation is written to the column AND the metadata bag', async () => {
  // The vert challenge aggregate SUMs the promoted column, not the jsonb key,
  // so writing only the bag left every vert board at 0 m. Both, or neither.
  const db = dbStub();
  await ingestActivity(db.client, 'u1', 'tok', act({ total_elevation_gain: 210.6, distance: 100 }));
  const row = db.inserted[0];
  assertEquals(row.elevation_gain_m, 211);
  assertEquals((row.metadata as Record<string, unknown>).elevation_m, 211);

  // An activity Strava reported no elevation for writes neither, rather than a
  // zero that would read as a measured flat run.
  const missing = dbStub();
  await ingestActivity(missing.client, 'u1', 'tok', act({ total_elevation_gain: undefined, distance: 100 }));
  assert(!('elevation_gain_m' in missing.inserted[0]));
  assert(!('elevation_m' in (missing.inserted[0].metadata as Record<string, unknown>)));

  // A genuine zero IS written: the runner ran on the flat, which is a fact.
  const flat = dbStub();
  await ingestActivity(flat.client, 'u1', 'tok', act({ total_elevation_gain: 0, distance: 100 }));
  assertEquals(flat.inserted[0].elevation_gain_m, 0);
});

Deno.test('ingestActivity — the metadata carries only what the payload actually had', async () => {
  const full = dbStub();
  await ingestActivity(
    full.client,
    'u1',
    'tok',
    act({ name: 'Dawn patrol', average_heartrate: 154.6, distance: 100 }),
  );
  const meta = full.inserted[0].metadata as Record<string, unknown>;
  assertEquals(meta.title, 'Dawn patrol');
  assertEquals(meta.avg_bpm, 155);
  assertEquals(meta.imported_from, 'strava');
  assertEquals(meta.strava_id, '12345');

  const bare = dbStub();
  await ingestActivity(bare.client, 'u1', 'tok', act({ name: undefined, average_heartrate: undefined, distance: 100 }));
  const bareMeta = bare.inserted[0].metadata as Record<string, unknown>;
  assert(!('title' in bareMeta));
  assert(!('avg_bpm' in bareMeta));
});

Deno.test('ingestActivity — the walk and hike categories survive the trip to the column', async () => {
  const cases: Array<[string, string]> = [
    ['Run', 'run'],
    ['TrailRun', 'run'],
    ['VirtualRun', 'run'],
    ['Walk', 'walk'],
    ['Hike', 'hike'],
    ['walk', 'walk'],
    ['HIKE', 'hike'],
  ];
  for (const [sport, want] of cases) {
    const db = dbStub();
    await ingestActivity(db.client, 'u1', 'tok', act({ sport_type: sport, distance: 100 }));
    assertEquals(db.inserted[0].activity_type, want, sport);
  }
});

Deno.test('ingestActivity — a stream fetch that fails leaves the row standing', async () => {
  // The track is best-effort: a 404, a throw, or a body that is not a stream
  // must not undo an insert that already succeeded.
  await withNoStreams(async () => {
    const db = dbStub();
    await ingestActivity(db.client, 'u1', 'tok', act({ distance: 5000 }));
    assertEquals(db.inserted.length, 1);
    assertEquals(db.inserted[0].distance_m, 5000);
  });

  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.reject(new TypeError('connection reset'))) as typeof fetch;
  try {
    const db = dbStub();
    await ingestActivity(db.client, 'u1', 'tok', act({ distance: 5000 }));
    assertEquals(db.inserted.length, 1);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test('ingestActivity — a track that cannot be stored is logged, never swallowed silently', async () => {
  // The arm is best-effort by design, and the case above pins that the row
  // survives it. What nothing asked is whether the failure leaves any trace:
  // an indoor activity's 404 and a systematic breakage — a changed streams
  // endpoint, a revoked Storage grant, a quota — both reached the same
  // `catch (_) {}`, so a fault losing the GPS trace of every run imported
  // while it lasted was indistinguishable from normal operation.
  const original = globalThis.fetch;
  const originalError = console.error;
  const lines: unknown[][] = [];
  globalThis.fetch = ((url: string | URL | Request) => {
    const href = typeof url === 'string' ? url : url.toString();
    if (href.includes('/streams')) {
      return Promise.resolve(
        new Response(
          JSON.stringify({
            latlng: { data: [[1, 2], [1.0001, 2.0001]] },
            time: { data: [0, 1] },
          }),
          { status: 200, headers: { 'content-type': 'application/json' } },
        ),
      );
    }
    return Promise.resolve(new Response('{}', { status: 404 }));
  }) as typeof fetch;
  console.error = (...args: unknown[]) => {
    lines.push(args);
  };
  try {
    const db = dbStub();
    // The Storage upload is what fails here: `dbStub` has no `storage`, so
    // `uploadTrack` throws on the first property read — the shape of any
    // upload-side fault, from a revoked grant to a quota.
    await ingestActivity(db.client, 'u1', 'tok', act({ distance: 5000 }));
    assertEquals(db.inserted.length, 1, 'the row must still stand');
    assertEquals(lines.length, 1, 'exactly one line, for one failure');
    const [message, detail] = lines[0] as [string, Record<string, unknown>];
    assert(
      message.includes('track'),
      `the line must name what was lost, got: ${message}`,
    );
    assertEquals(detail.activityId, 12345, 'the line must name the activity to be actionable');
    assert(
      typeof detail.error === 'string' && detail.error.length > 0,
      'the line must carry the failure, not just the fact of one',
    );
    // PostgREST errors travel with `details` / `hint` that can echo row
    // values into the shared log aggregator; only the message may ship.
    assertEquals(detail.details, undefined);
    assertEquals(detail.hint, undefined);
  } finally {
    globalThis.fetch = original;
    console.error = originalError;
  }
});

Deno.test('ingestActivity — a stream that yields no track logs nothing', async () => {
  // The positive control beside the case above: the common, expected outcome
  // for an indoor activity must not page anyone. A log on every treadmill run
  // is the same as no log at all.
  const original = globalThis.fetch;
  const originalError = console.error;
  const lines: unknown[][] = [];
  globalThis.fetch = (() =>
    Promise.resolve(new Response('{}', { status: 404 }))) as typeof fetch;
  console.error = (...args: unknown[]) => {
    lines.push(args);
  };
  try {
    const db = dbStub();
    await ingestActivity(db.client, 'u1', 'tok', act({ distance: 5000 }));
    assertEquals(db.inserted.length, 1);
    assertEquals(lines, [], 'an activity with no stream is not a failure');
  } finally {
    globalThis.fetch = original;
    console.error = originalError;
  }
});
