/// The provider race-calendar sync's readings, caps and reconciliation.
///
/// No credential exists for either provider, so the live payload has not been
/// observed from this repo — which is exactly why these tests matter more than
/// usual. Every reading is optional-with-drop, and what is pinned below is that
/// a row which does not yield the two things `race_listings` requires becomes
/// nothing and is COUNTED, rather than becoming a race on a public calendar with
/// a guessed name or a transposed date (decisions § 977).
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-listings-sync/lib.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  DEFAULT_NEAR_RADIUS_M,
  MAX_LISTING_LOCATION_LEN,
  MAX_LISTING_NAME_LEN,
  MAX_LISTING_ROWS,
  MAX_NEAR_RADIUS_M,
  type RaceListingUpsert,
  type StoredListing,
  distanceMetresFrom,
  extractProviderRaces,
  listingDiffers,
  listingUpsertFrom,
  listingUrl,
  parseNearHint,
  parseProviderRaceDate,
  providerRacesUrl,
  readProviderRace,
  readRunSignUpRace,
  readUltraSignUpRace,
  reconcileListingBatch,
} from './lib.ts';

const MIGRATIONS = new URL('../../migrations/', import.meta.url).pathname;

Deno.test('the field caps are the columns own CHECK constraints, not numbers picked here', () => {
  // A composer capping LOWER than the column is merely conservative; one capping
  // higher hands the batch a 23514 that loses every other race in it. So the
  // caps are read back out of the migration that declares them.
  const sql = Deno.readTextFileSync(`${MIGRATIONS}20270503_001_free_text_length_caps.sql`);
  const name = /race_listings_name_len_chk\s*\n?\s*check \(name is null or char_length\(name\) <= (\d+)\)/
    .exec(sql);
  const loc =
    /race_listings_location_label_len_chk\s*\n?\s*check \(location_label is null or char_length\(location_label\) <= (\d+)\)/
      .exec(sql);
  assert(name && loc, 'the length CHECKs are no longer in 20270503_001 — re-anchor this guard');
  assert(
    MAX_LISTING_NAME_LEN <= Number(name![1]),
    `name cap ${MAX_LISTING_NAME_LEN} exceeds the column's ${name![1]}`,
  );
  assert(
    MAX_LISTING_LOCATION_LEN <= Number(loc![1]),
    `location cap ${MAX_LISTING_LOCATION_LEN} exceeds the column's ${loc![1]}`,
  );
});

Deno.test('an ISO date is taken whole and a time suffix is dropped', () => {
  assertEquals(parseProviderRaceDate('2027-06-20'), '2027-06-20');
  assertEquals(parseProviderRaceDate('2027-06-20T08:30:00Z'), '2027-06-20');
  assertEquals(parseProviderRaceDate('2027-06-20 08:30'), '2027-06-20');
  assertEquals(parseProviderRaceDate('2027-02-29'), null, 'not a leap year');
  assertEquals(parseProviderRaceDate('2028-02-29'), '2028-02-29');
  assertEquals(parseProviderRaceDate('2027-13-01'), null);
});

Deno.test('a slash date is read US month-first, and refused when it cannot be', () => {
  assertEquals(parseProviderRaceDate('6/20/2027'), '2027-06-20');
  assertEquals(parseProviderRaceDate('06/05/2027'), '2027-06-05');
  // The tripwire. A day-first feed announces itself on the first race past the
  // 12th of a month rather than seeding the calendar with transposed dates.
  assertEquals(parseProviderRaceDate('20/06/2027'), null);
  assertEquals(parseProviderRaceDate('13/01/2027'), null);
  assertEquals(parseProviderRaceDate('2/31/2027'), null, 'the calendar still applies');
  assertEquals(parseProviderRaceDate(''), null);
  assertEquals(parseProviderRaceDate(null), null);
  assertEquals(parseProviderRaceDate(20270620), null);
});

Deno.test('a distance is converted, and an unknown unit is null rather than assumed', () => {
  assertEquals(distanceMetresFrom(26.2, 'miles'), 42165);
  assertEquals(distanceMetresFrom(26.2, 'mi'), 42165);
  assertEquals(distanceMetresFrom(5, 'K'), 5000);
  assertEquals(distanceMetresFrom(42195, undefined), 42195, 'a bare number is already metres');
  assertEquals(distanceMetresFrom(42195, 'metres'), 42195);
  // The one that matters. US race listings write MILES as `M` and SI writes
  // METRES as `m`; a case-insensitive table collapses them and files a 100-mile
  // race as a 100-metre one, and a case-sensitive one silently picks a reading
  // of a letter whose meaning in this feed has not been observed. Both readings
  // are refused, so the race keeps a null distance instead of somebody else's
  // band.
  assertEquals(distanceMetresFrom(100, 'M'), null);
  assertEquals(distanceMetresFrom(42195, 'm'), null);
  // `search_race_listings` buckets distance into race bands, so a guessed unit
  // files a 5K under "ultra".
  assertEquals(distanceMetresFrom(5, 'furlongs'), null);
  assertEquals(distanceMetresFrom(0, 'km'), null);
  assertEquals(distanceMetresFrom(-5, 'km'), null);
  assertEquals(distanceMetresFrom('not a number', 'km'), null);
  assertEquals(distanceMetresFrom(Infinity, 'km'), null);
});

Deno.test('a url the column would refuse is dropped, not written', () => {
  // `race_listings_entry_url_scheme_check` is `~* '^https?://'`; a value that
  // fails it raises 23514 and takes the whole batch insert with it.
  assertEquals(listingUrl('https://runsignup.com/Race/X'), 'https://runsignup.com/Race/X');
  assertEquals(listingUrl('http://x.test/r'), 'http://x.test/r');
  assertEquals(listingUrl('runsignup.com/Race/X'), null);
  assertEquals(listingUrl('javascript:alert(1)'), null);
  assertEquals(listingUrl(''), null);
  assertEquals(listingUrl(undefined), null);
});

Deno.test('a RunSignUp row without a name or a date becomes nothing', () => {
  assertEquals(readRunSignUpRace({ race_id: 1, next_date: '6/20/2027' }), null);
  assertEquals(readRunSignUpRace({ race_id: 1, name: 'Bighorn' }), null);
  assertEquals(readRunSignUpRace({}), null);
});

Deno.test('a RunSignUp row is normalised, and a past-only race still files', () => {
  const race = readRunSignUpRace({
    race_id: 4821,
    name: 'Bighorn Trail Run',
    next_date: '6/20/2027',
    url: 'https://runsignup.com/Race/WY/Sheridan/BighornTrailRun',
    results_url: 'https://runsignup.com/Race/Results/4821',
    address: { city: 'Sheridan', state: 'WY' },
    distance: 100,
    distance_units: 'miles',
  });
  assert(race !== null);
  assertEquals(race!.providerRaceId, '4821');
  assertEquals(race!.name, 'Bighorn Trail Run');
  assertEquals(race!.date, '2027-06-20');
  assertEquals(race!.distanceM, 160934);
  assertEquals(race!.locationLabel, 'Sheridan, WY');
  assertEquals(race!.entryUrl, 'https://runsignup.com/Race/WY/Sheridan/BighornTrailRun');
  const past = readRunSignUpRace({ race_id: 7, name: 'Old Race', last_date: '2019-05-04' });
  assertEquals(past?.date, '2019-05-04');
});

Deno.test('an over-long name is capped rather than refused by the column', () => {
  const race = readRunSignUpRace({
    race_id: 1,
    name: 'x'.repeat(400),
    next_date: '2027-06-20',
    address: { city: 'y'.repeat(200), state: 'z'.repeat(200) },
  });
  // `typeof` rather than a null test: a reader that answers `undefined` gives
  // `race?.name.length` the same `undefined` the cap constant would have, and
  // two absent values compare equal. The vacuity operator scored this case as
  // surviving until the check named a string.
  assert(typeof race?.name === 'string', 'the reader produced no name to cap');
  assert(typeof race!.locationLabel === 'string', 'the reader produced no location to cap');
  assertEquals(race!.name.length, MAX_LISTING_NAME_LEN);
  assertEquals(race!.locationLabel!.length, MAX_LISTING_LOCATION_LEN);
});

Deno.test('an UltraSignup row reads its own spellings and nobody elses', () => {
  const race = readUltraSignUpRace({
    eventid: 91234,
    eventname: 'Hardrock 100',
    eventdate: '7/9/2027',
    city: 'Silverton',
    state: 'CO',
    distance: 100.5,
    distance_units: 'miles',
    url: 'https://ultrasignup.com/register.aspx?did=91234',
  });
  assertEquals(race?.providerRaceId, '91234');
  assertEquals(race?.date, '2027-07-09');
  assertEquals(race?.locationLabel, 'Silverton, CO');
  assertEquals(race?.resultsUrl, null);
  // The whole point of the unverified-field-names posture, and the dispatcher
  // hands each provider its own reader rather than a merged one: a payload
  // spelled the other provider's way yields nothing, not a race with a guessed
  // name.
  assertEquals(readProviderRace('ultrasignup', { name: 'X', next_date: '2027-07-09' }), null);
  assertEquals(readProviderRace('runsignup', { eventname: 'X', eventdate: '2027-07-09' }), null);
});

Deno.test('the envelope walk tolerates the nestings and caps the batch', () => {
  assertEquals(extractProviderRaces([{ race_id: 1 }, { race_id: 2 }]).length, 2);
  assertEquals(extractProviderRaces({ races: [{ race: { race_id: 3 } }] })[0].race_id, 3);
  assertEquals(extractProviderRaces({ races: [{ race_id: 4 }] })[0].race_id, 4);
  assertEquals(extractProviderRaces({ events: [{ eventid: 5 }] })[0].eventid, 5);
  assertEquals(extractProviderRaces(null).length, 0);
  assertEquals(extractProviderRaces({}).length, 0);
  assertEquals(extractProviderRaces('nope').length, 0);
  const huge = { races: Array.from({ length: MAX_LISTING_ROWS + 40 }, () => ({ race_id: 1 })) };
  assertEquals(extractProviderRaces(huge).length, MAX_LISTING_ROWS);
});

function upsert(id: string | null, over: Partial<RaceListingUpsert> = {}): RaceListingUpsert {
  return {
    ...listingUpsertFrom('runsignup', {
      providerRaceId: id,
      name: 'Race',
      date: '2027-06-20',
      distanceM: 42195,
      locationLabel: 'Somewhere',
      entryUrl: null,
      resultsUrl: null,
    }),
    ...over,
  };
}

Deno.test('the batch is reconciled against storage AND against itself', () => {
  const batch = reconcileListingBatch(
    [upsert('a'), upsert('b'), upsert('a'), upsert(null)],
    ['b'],
  );
  assertEquals(batch.fresh.map((r) => r.provider_race_id), ['a']);
  assertEquals(batch.existing.map((r) => r.provider_race_id), ['b']);
  // The repeat and the id-less row: the insert is ONE statement against the
  // partial unique index, so a repeat would 23505 and lose every other race in
  // the batch — and an id-less row would be re-inserted on every sync, since the
  // index does not cover nulls.
  assertEquals(batch.skipped, 2);
});

Deno.test('a provider row is marked verified, which only the service role may do', () => {
  const row = upsert('a');
  assertEquals(row.is_verified, true);
  assertEquals(row.provider, 'runsignup');
});

function storedOf(over: Partial<StoredListing> = {}): StoredListing {
  return {
    id: 'L-1',
    provider_race_id: 'a',
    name: 'Race',
    race_date: '2027-06-20',
    distance_m: 42195,
    location_label: 'Somewhere',
    entry_url: null,
    results_url: null,
    is_verified: true,
    ...over,
  };
}

Deno.test('an unchanged race writes nothing, and each field that moves writes', () => {
  assertEquals(listingDiffers(storedOf(), upsert('a')), false);
  assertEquals(listingDiffers(storedOf({ race_date: '2027-06-27' }), upsert('a')), true);
  assertEquals(listingDiffers(storedOf({ name: 'Renamed' }), upsert('a')), true);
  assertEquals(listingDiffers(storedOf({ distance_m: 21097 }), upsert('a')), true);
  assertEquals(listingDiffers(storedOf({ location_label: 'Elsewhere' }), upsert('a')), true);
  assertEquals(listingDiffers(storedOf({ entry_url: 'https://x.test' }), upsert('a')), true);
  assertEquals(listingDiffers(storedOf({ results_url: 'https://x.test' }), upsert('a')), true);
  // A race a user submitted first lands unverified; the provider catching up
  // with it is exactly when that should change.
  assertEquals(listingDiffers(storedOf({ is_verified: false }), upsert('a')), true);
});

Deno.test('a region hint is validated, and a bad one is an error not a silent no-hint', () => {
  assertEquals(parseNearHint(undefined), { ok: true, near: null });
  assertEquals(parseNearHint(null), { ok: true, near: null });
  assertEquals(parseNearHint({ lng: -106.9, lat: 37.8 }), {
    ok: true,
    near: { lng: -106.9, lat: 37.8, radiusM: DEFAULT_NEAR_RADIUS_M },
  });
  assertEquals(parseNearHint({ lng: -106.9, lat: 37.8, radius_m: 25000 }).ok, true);
  // Falling back to "no hint" on a typo pulls the provider's whole national feed
  // and writes it into the calendar as if it were local.
  assertEquals(parseNearHint({ lat: 37.8 }), { ok: false, error: 'invalid_near_lng' });
  assertEquals(parseNearHint({ lng: 200, lat: 37.8 }), { ok: false, error: 'invalid_near_lng' });
  assertEquals(parseNearHint({ lng: -106.9, lat: 91 }), { ok: false, error: 'invalid_near_lat' });
  assertEquals(parseNearHint({ lng: 0, lat: 0, radius_m: 0 }), {
    ok: false,
    error: 'invalid_near_radius',
  });
  assertEquals(parseNearHint({ lng: 0, lat: 0, radius_m: MAX_NEAR_RADIUS_M + 1 }).ok, false);
  assertEquals(parseNearHint({ lng: 0, lat: 0, radius_m: NaN }).ok, false);
  assertEquals(parseNearHint([1, 2]), { ok: false, error: 'invalid_near' });
  assertEquals(parseNearHint('nope'), { ok: false, error: 'invalid_near' });
});

Deno.test('the provider URL carries the credential and the region, per provider', () => {
  const rs = providerRacesUrl({
    provider: 'runsignup',
    apiKey: 'KEY',
    apiSecret: 'SECRET',
    near: { lng: -106.9, lat: 37.8, radiusM: 80467 },
  });
  assert(rs.startsWith('https://runsignup.com/Rest/races'));
  assert(rs.includes('format=json'));
  assert(rs.includes('api_key=KEY'));
  assert(rs.includes('api_secret=SECRET'));
  assert(rs.includes('radius=50'), '80467 m is 50 miles');
  const us = providerRacesUrl({
    provider: 'ultrasignup',
    apiKey: 'K',
    apiSecret: 'S',
    near: null,
  });
  assert(us.startsWith('https://ultrasignup.com/service/events.svc/'));
  assert(!us.includes('radius='), 'no hint means no region params');
  assert(us !== rs, 'the two providers must not resolve to one endpoint');
});
