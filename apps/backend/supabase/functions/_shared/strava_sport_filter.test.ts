/// Pins the isStravaRunFamily / ingestActivity rejection guard
/// (persona-hunt Pro #3). Pre-fix, ingestActivity's sport
/// categorisation only special-cased Walk and Hike; anything else
/// (Swim, Ride, Ski, AlpineSki, Crossfit, …) silently coerced to
/// activity_type='run', shipping cross-training load into the user's
/// weekly mileage + TSB if a future caller forgot to pre-filter.
///
/// Run with:
///   cd apps/backend && deno test --no-check supabase/functions/_shared/strava_sport_filter.test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { isStravaRunFamily } from './strava.ts';

Deno.test('isStravaRunFamily — Run / TrailRun / VirtualRun all qualify', () => {
	assertEquals(isStravaRunFamily('Run'), true);
	assertEquals(isStravaRunFamily('TrailRun'), true);
	assertEquals(isStravaRunFamily('VirtualRun'), true);
});

Deno.test('isStravaRunFamily — Walk / Hike qualify (categorised in ingestActivity)', () => {
	assertEquals(isStravaRunFamily('Walk'), true);
	assertEquals(isStravaRunFamily('Hike'), true);
});

Deno.test('isStravaRunFamily — Swim / Ride / Ski rejected', () => {
	assertEquals(isStravaRunFamily('Swim'), false);
	assertEquals(isStravaRunFamily('Ride'), false);
	assertEquals(isStravaRunFamily('VirtualRide'), false);
	assertEquals(isStravaRunFamily('AlpineSki'), false);
	assertEquals(isStravaRunFamily('NordicSki'), false);
	assertEquals(isStravaRunFamily('Crossfit'), false);
	assertEquals(isStravaRunFamily('WeightTraining'), false);
});

Deno.test('isStravaRunFamily — empty / null / undefined rejected', () => {
	assertEquals(isStravaRunFamily(''), false);
	assertEquals(isStravaRunFamily(null), false);
	assertEquals(isStravaRunFamily(undefined), false);
});

Deno.test('isStravaRunFamily — case-insensitive substring match', () => {
	assertEquals(isStravaRunFamily('RUN'), true);
	assertEquals(isStravaRunFamily('trailrun'), true);
	assertEquals(isStravaRunFamily('VIRTUAL_RUN'), true);
});
