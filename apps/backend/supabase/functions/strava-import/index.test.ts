// Pure-helper tests for the `strava-import` fixes. The dedupe + embedded-best
// logic lives in `../_shared/strava.ts` (materialising the Strava stream +
// building the run row happens there, shared with `strava-webhook`); these
// pin the two correctness bugs:
//   1. cross-provider near-duplicate detection (`isCrossProviderDuplicate`)
//   2. embedded best efforts on imported tracks (`computeEmbeddedBests`)
//
// Importing `../_shared/strava.ts` pulls its esm.sh deps, which the CI
// "Warm the Deno dependency cache" step pre-fetches, so the recursive
// `deno test --allow-read --allow-env` run resolves them offline.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	CROSS_PROVIDER_DISTANCE_FRACTION,
	CROSS_PROVIDER_START_TOLERANCE_S,
	collectRunIdentities,
	computeEmbeddedBests,
	fastestWindowSeconds,
	isCrossProviderDuplicate,
	type RawRunRow,
	type RunIdentity,
} from '../_shared/strava.ts';

const ms = (iso: string) => Date.parse(iso);

// ---- BUG 1: cross-provider near-duplicate ----

Deno.test('isCrossProviderDuplicate — exact same start + distance matches', () => {
	const existing: RunIdentity[] = [{ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }];
	assert(
		isCrossProviderDuplicate({ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }, existing),
	);
});

Deno.test('isCrossProviderDuplicate — start within a few min + distance within % matches', () => {
	// A Garmin watch auto-uploaded to Strava, then re-imported from a Garmin
	// ZIP: same effort, slightly different start stamp + distance across
	// providers.
	const existing: RunIdentity[] = [{ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }];
	assert(
		isCrossProviderDuplicate(
			{ startedAtMs: ms('2026-01-01T09:02:00Z'), distanceM: 10250 },
			existing,
		),
	);
});

Deno.test('isCrossProviderDuplicate — start beyond the tolerance is distinct', () => {
	const existing: RunIdentity[] = [{ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }];
	// 4 minutes apart (> 180 s): a genuinely separate back-to-back effort.
	assertEquals(
		isCrossProviderDuplicate(
			{ startedAtMs: ms('2026-01-01T09:04:00Z'), distanceM: 10000 },
			existing,
		),
		false,
	);
});

Deno.test('isCrossProviderDuplicate — distance beyond the fraction is distinct', () => {
	const existing: RunIdentity[] = [{ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }];
	// Same-ish start but 20 % longer — not the same run.
	assertEquals(
		isCrossProviderDuplicate(
			{ startedAtMs: ms('2026-01-01T09:00:30Z'), distanceM: 12000 },
			existing,
		),
		false,
	);
});

Deno.test('isCrossProviderDuplicate — empty history + non-finite start never matches', () => {
	assertEquals(isCrossProviderDuplicate({ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }, []), false);
	assertEquals(
		isCrossProviderDuplicate({ startedAtMs: NaN, distanceM: 10000 }, [
			{ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 },
		]),
		false,
	);
});

Deno.test('cross-provider tolerances are the documented values', () => {
	assertEquals(CROSS_PROVIDER_START_TOLERANCE_S, 180);
	assertEquals(CROSS_PROVIDER_DISTANCE_FRACTION, 0.05);
});

// ---- BUG 3: the dedupe fetch must page past PostgREST's 1000-row cap ----

Deno.test('collectRunIdentities — 1200 runs are all collected across two pages', async () => {
	const rows: RawRunRow[] = Array.from({ length: 1200 }, (_, i) => ({
		started_at: new Date(Date.UTC(2026, 0, 1, 0, 0, i)).toISOString(),
		distance_m: 5000 + i,
	}));
	const calls: Array<[number, number]> = [];
	const ids = await collectRunIdentities(async (from, to) => {
		calls.push([from, to]);
		return rows.slice(from, to + 1);
	});
	assertEquals(ids.length, 1200);
	assertEquals(calls.length, 2);
	assertEquals(calls[0], [0, 999]);
	assertEquals(calls[1], [1000, 1999]);
});

Deno.test('collectRunIdentities — a page error stops the loop without throwing', async () => {
	let call = 0;
	const ids = await collectRunIdentities(async () => {
		call++;
		return call === 1 ? [{ started_at: '2026-01-01T09:00:00Z', distance_m: 5000 }] : null;
	}, 1);
	assertEquals(ids.length, 1);
});

// ---- BUG 2: embedded best efforts ----

/// Build a track at the equator (1 deg lng ≈ 111194.93 m) with `segments`
/// steps of `stepM` metres each, `stepS` seconds apart from `startIso`.
function evenTrack(startIso: string, segments: number, stepM: number, stepS: number) {
	const mPerDeg = 6371000 * (Math.PI / 180);
	const stepDeg = stepM / mPerDeg;
	const startMs = Date.parse(startIso);
	const track: { lat: number; lng: number; ts: string }[] = [];
	for (let i = 0; i <= segments; i++) {
		track.push({
			lat: 0,
			lng: i * stepDeg,
			ts: new Date(startMs + i * stepS * 1000).toISOString(),
		});
	}
	return track;
}

Deno.test('computeEmbeddedBests — fewer than 3 points writes nothing', () => {
	assertEquals(computeEmbeddedBests(evenTrack('2026-01-01T09:00:00Z', 1, 100, 30)), {});
});

Deno.test('computeEmbeddedBests — a track shorter than 5 km has no bests', () => {
	// 40 × 100 m = 4 km — below the 5 km bracket.
	assertEquals(computeEmbeddedBests(evenTrack('2026-01-01T09:00:00Z', 40, 100, 30)), {});
});

Deno.test('computeEmbeddedBests — even 6 km run yields a ~total-time 5k', () => {
	// 60 × 100 m at 30 s/step = 6 km, 5:00/km. Fastest 5 km window ≈ 1500 s.
	const bests = computeEmbeddedBests(evenTrack('2026-01-01T09:00:00Z', 60, 100, 30));
	assert(bests.fastest_5k_s >= 1495 && bests.fastest_5k_s <= 1505, `got ${bests.fastest_5k_s}`);
	assertEquals(bests.fastest_10k_s, undefined);
});

Deno.test('computeEmbeddedBests — a fast 5 km inside a long run is detected', () => {
	// First 5 km fast (100 m / 20 s → 1000 s), last 5 km slow (100 m / 40 s).
	const mPerDeg = 6371000 * (Math.PI / 180);
	const stepDeg = 100 / mPerDeg;
	const startMs = Date.parse('2026-01-01T09:00:00Z');
	const track: { lat: number; lng: number; ts: string }[] = [{ lat: 0, lng: 0, ts: new Date(startMs).toISOString() }];
	let t = startMs;
	for (let i = 1; i <= 100; i++) {
		t += (i <= 50 ? 20 : 40) * 1000;
		track.push({ lat: 0, lng: i * stepDeg, ts: new Date(t).toISOString() });
	}
	const bests = computeEmbeddedBests(track);
	// The embedded fast 5k (~1000 s) beats the whole-run-scaled pace (1500 s).
	assert(bests.fastest_5k_s >= 995 && bests.fastest_5k_s <= 1005, `got ${bests.fastest_5k_s}`);
	// Only one 10k window (the whole track): 1000 + 2000 = 3000 s.
	assert(bests.fastest_10k_s >= 2990 && bests.fastest_10k_s <= 3010, `got ${bests.fastest_10k_s}`);
	assertEquals(bests.fastest_half_marathon_s, undefined);
});

Deno.test('computeEmbeddedBests — a track with no timestamps writes nothing (no fake bests)', () => {
	const mPerDeg = 6371000 * (Math.PI / 180);
	const stepDeg = 100 / mPerDeg;
	const track = Array.from({ length: 61 }, (_, i) => ({ lat: 0, lng: i * stepDeg }));
	assertEquals(computeEmbeddedBests(track), {});
});

Deno.test('fastestWindowSeconds — null when the track is shorter than the window', () => {
	assertEquals(fastestWindowSeconds(evenTrack('2026-01-01T09:00:00Z', 10, 100, 30), 5000), null);
});
