/// Pins buildTrackFromStreams — the input-sanitisation boundary for
/// untrusted third-party (Strava) GPS streams. Kept in lockstep with the Go
/// twin apps/job_worker/internal/handler_strava_event.go BuildTrackFromStreams.
///
/// Run with:
///   cd apps/backend && deno test --no-check supabase/functions/_shared/strava.test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { buildTrackFromStreams } from './strava.ts';

const START = '2026-01-01T10:00:00Z';
const streams = (o: Record<string, unknown[]>) =>
	Object.fromEntries(Object.entries(o).map(([k, v]) => [k, { data: v }]));

Deno.test('buildTrackFromStreams — drops out-of-range lat/lng (audit High #4)', () => {
	const t = buildTrackFromStreams(
		streams({ latlng: [[45, -120], [91, 0], [0, 181], [46, -121]] }),
		START,
	);
	assertEquals(t.map((p) => [p.lat, p.lng]), [[45, -120], [46, -121]]);
});

Deno.test('buildTrackFromStreams — rejects altitude + HR outside legal ranges', () => {
	const t = buildTrackFromStreams(
		streams({ latlng: [[45, -120], [45, -120]], altitude: [12000, 100], heartrate: [10, 150] }),
		START,
	);
	assertEquals(t[0].ele, undefined); // 12000 > 9000 rejected
	assertEquals(t[0].bpm, undefined); // 10 < 30 rejected
	assertEquals(t[1].ele, 100);
	assertEquals(t[1].bpm, 150);
});

Deno.test('buildTrackFromStreams — drops a >1s backward sample but tolerates 1s wobble', () => {
	const kept = buildTrackFromStreams(
		streams({ latlng: [[45, -120], [45, -120], [45, -120]], time: [0, 100, 99] }),
		START,
	);
	assertEquals(kept.length, 3); // 99 is within 1s of 100 → kept

	const dropped = buildTrackFromStreams(
		streams({ latlng: [[45, -120], [45, -120]], time: [100, 0] }),
		START,
	);
	assertEquals(dropped.length, 1); // 0 is >1s behind 100 → whole point dropped
});

Deno.test('buildTrackFromStreams — empty / missing latlng returns empty', () => {
	assertEquals(buildTrackFromStreams(streams({}), START), []);
	assertEquals(buildTrackFromStreams(streams({ latlng: [] }), START), []);
});

Deno.test('buildTrackFromStreams — an unparseable startIso omits timestamps but keeps points', () => {
	const t = buildTrackFromStreams(streams({ latlng: [[45, -120]], time: [0] }), 'not-a-date');
	assertEquals(t.length, 1);
	assertEquals(t[0].ts, undefined);
});

Deno.test('buildTrackFromStreams — a non-finite time entry does not throw away the whole track', () => {
	// Regression: a NaN time made `new Date(NaN).toISOString()` throw, which
	// ingestActivity's catch swallowed — dropping the ENTIRE track. The point
	// must be kept (untimed), the good samples timed, and lastTs unpoisoned so
	// the following sample still validates. Matches the Go twin.
	const t = buildTrackFromStreams(
		streams({ latlng: [[45, -120], [45, -120], [45, -120]], time: [0, Number.NaN, 20] }),
		START,
	);
	assertEquals(t.length, 3);
	assertEquals(typeof t[0].ts, 'string'); // 0s → timed
	assertEquals(t[1].ts, undefined); // NaN → kept, untimed, no throw
	assertEquals(typeof t[2].ts, 'string'); // 20s → still timed (lastTs not poisoned)
});
