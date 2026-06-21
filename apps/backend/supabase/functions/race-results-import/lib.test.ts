import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  capField,
  chronoTrackConfigured,
  chronoTrackResultsUrl,
  extractChronoTrackResults,
  extractRunSignUpResults,
  extractUltraSignUpResults,
  mapChronoTrackResult,
  mapRunSignUpResult,
  mapUltraSignUpResult,
  MAX_FIELD_LEN,
  MAX_RESULTS_ROWS,
  parseClockToSeconds,
  parseRaceResultRow,
  raceExternalId,
  runSignUpResultsUrl,
  ultraSignUpResultsUrl,
} from './lib.ts';

const OPTS = {
  userId: 'u-1',
  listingId: 'L-1',
  raceName: 'Richmond Half Marathon',
  raceDate: '2025-09-21',
  distanceM: 21097,
  isPublic: false,
};

Deno.test('capField trims and truncates', () => {
  assertEquals(capField('  hi  '), 'hi');
  assertEquals(capField('x'.repeat(MAX_FIELD_LEN + 50)).length, MAX_FIELD_LEN);
  assertEquals(capField(42), '');
  assertEquals(capField(null), '');
});

Deno.test('parseClockToSeconds handles H:MM:SS / MM:SS / SS', () => {
  assertEquals(parseClockToSeconds('1:47:23'), 1 * 3600 + 47 * 60 + 23);
  assertEquals(parseClockToSeconds('24:31'), 24 * 60 + 31);
  assertEquals(parseClockToSeconds('45'), 45);
});

Deno.test('parseClockToSeconds rejects garbage as 0', () => {
  assertEquals(parseClockToSeconds('abc'), 0);
  assertEquals(parseClockToSeconds(''), 0);
  assertEquals(parseClockToSeconds('-1:00'), 0);
});

Deno.test('raceExternalId is race:name:date:bib and colon-safe', () => {
  assertEquals(
    raceExternalId('Richmond Half', '2025-09-21', '1234'),
    'race:Richmond Half:2025-09-21:1234',
  );
  // Embedded colons in a scraped value are replaced so they can't break the
  // delimiter (only the four leading literal colons remain).
  const id = raceExternalId('A:B', '2025-01-01', '7:7');
  assertEquals(id, 'race:A B:2025-01-01:7 7');
});

Deno.test('mapRunSignUpResult maps a finisher onto a race run', () => {
  const run = mapRunSignUpResult(
    {
      bib_num: '1234',
      chip_time: '1:47:23',
      clock_time: '1:48:01',
      place: 142,
      age_group_place: 12,
      age_group: 'M35-39',
    },
    OPTS,
  );
  assert(run !== null);
  assertEquals(run!.source, 'race');
  assertEquals(run!.activity_type, 'run');
  assertEquals(run!.distance_m, 21097);
  assertEquals(run!.duration_s, 1 * 3600 + 47 * 60 + 23);
  assertEquals(run!.external_id, 'race:Richmond Half Marathon:2025-09-21:1234');
  assertEquals(run!.race_listing_id, 'L-1');
  assertEquals(run!.started_at, '2025-09-21T10:00:00Z');
  assertEquals(run!.metadata.race_name, 'Richmond Half Marathon');
  assertEquals(run!.metadata.bib, '1234');
  assertEquals(run!.metadata.chip_time, '1:47:23');
  assertEquals(run!.metadata.gun_time, '1:48:01');
  assertEquals(run!.metadata.overall_place, 142);
  assertEquals(run!.metadata.age_group_place, 12);
  assertEquals(run!.metadata.age_group, 'M35-39');
});

Deno.test('mapRunSignUpResult falls back to gun time when chip is absent', () => {
  const run = mapRunSignUpResult({ bib_num: '5', clock_time: '0:30:00' }, OPTS);
  assert(run !== null);
  assertEquals(run!.duration_s, 30 * 60);
  assertEquals(run!.metadata.chip_time, undefined);
  assertEquals(run!.metadata.gun_time, '0:30:00');
});

Deno.test('mapRunSignUpResult returns null when there is no usable time', () => {
  assertEquals(mapRunSignUpResult({ bib_num: '9' }, OPTS), null);
  assertEquals(mapRunSignUpResult({ chip_time: 'DNS' }, OPTS), null);
});

Deno.test('mapRunSignUpResult honours isPublic from privacy_default', () => {
  const priv = mapRunSignUpResult({ chip_time: '20:00' }, OPTS);
  assertEquals(priv!.is_public, false);
  const pub = mapRunSignUpResult({ chip_time: '20:00' }, { ...OPTS, isPublic: true });
  assertEquals(pub!.is_public, true);
});

Deno.test('mapRunSignUpResult drops non-positive places', () => {
  const run = mapRunSignUpResult(
    { chip_time: '20:00', place: 0, age_group_place: -1 },
    OPTS,
  );
  assertEquals(run!.metadata.overall_place, undefined);
  assertEquals(run!.metadata.age_group_place, undefined);
});

Deno.test('parseRaceResultRow maps a pasted result with the same shape/id', () => {
  const run = parseRaceResultRow(
    { bib: '77', chip_time: '0:55:10', gun_time: '0:55:40', overall_place: 9, age_group: 'F40-44' },
    OPTS,
  );
  assert(run !== null);
  assertEquals(run!.external_id, 'race:Richmond Half Marathon:2025-09-21:77');
  assertEquals(run!.duration_s, 55 * 60 + 10);
  assertEquals(run!.metadata.age_group, 'F40-44');
});

Deno.test('runSignUpResultsUrl includes key/secret/format and encodes raceId', () => {
  const url = runSignUpResultsUrl({
    raceId: '9001',
    apiKey: 'KEY',
    apiSecret: 'SECRET',
    runSignUpUserId: 'rs-42',
  });
  assert(url.startsWith('https://runsignup.com/Rest/race/9001/results/get-results'));
  assert(url.includes('format=json'));
  assert(url.includes('api_key=KEY'));
  assert(url.includes('api_secret=SECRET'));
  assert(url.includes('user_id=rs-42'));
});

Deno.test('extractRunSignUpResults reads the nested results sets envelope', () => {
  const payload = {
    individual_results_sets: [
      { results: [{ bib_num: '1', chip_time: '20:00' }, { bib_num: '2', chip_time: '21:00' }] },
      { results: [{ bib_num: '3', chip_time: '22:00' }] },
    ],
  };
  const rows = extractRunSignUpResults(payload);
  assertEquals(rows.length, 3);
  assertEquals(rows[2].bib_num, '3');
});

Deno.test('extractRunSignUpResults tolerates a top-level results array + caps', () => {
  assertEquals(extractRunSignUpResults({ results: [{ bib_num: 'a' }] }).length, 1);
  assertEquals(extractRunSignUpResults(null).length, 0);
  assertEquals(extractRunSignUpResults({}).length, 0);
  const big = { results: Array.from({ length: MAX_RESULTS_ROWS + 100 }, () => ({ bib_num: 'x' })) };
  assertEquals(extractRunSignUpResults(big).length, MAX_RESULTS_ROWS);
});

// ── UltraSignup ──────────────────────────────────────────────────────────────

// A committed sample of the UltraSignup athlete-results JSON (bare top-level
// array, its native field names) so the mapper is testable without the live
// site or an API key.
const ULTRA_FIXTURE = [
  {
    bibno: '88',
    formattime: '4:32:10',
    place: 12,
    agerank: 3,
    agegroup: 'M40-49',
  },
  {
    bib: '91',
    time: '5:01:44',
    place: 21,
  },
  { bibno: '99', formattime: 'DNF', place: 0 }, // no usable time → dropped
];

const ULTRA_OPTS = {
  userId: 'u-1',
  listingId: 'L-9',
  raceName: 'Bighorn 100',
  raceDate: '2025-06-20',
  distanceM: 160934,
  isPublic: false,
};

Deno.test('mapUltraSignUpResult maps an UltraSignup finisher onto a race run', () => {
  const run = mapUltraSignUpResult(ULTRA_FIXTURE[0], ULTRA_OPTS);
  assert(run !== null);
  assertEquals(run!.source, 'race');
  assertEquals(run!.activity_type, 'run');
  assertEquals(run!.distance_m, 160934);
  assertEquals(run!.duration_s, 4 * 3600 + 32 * 60 + 10);
  assertEquals(run!.external_id, 'race:Bighorn 100:2025-06-20:88');
  assertEquals(run!.race_listing_id, 'L-9');
  assertEquals(run!.started_at, '2025-06-20T10:00:00Z');
  assertEquals(run!.metadata.race_name, 'Bighorn 100');
  assertEquals(run!.metadata.bib, '88');
  assertEquals(run!.metadata.chip_time, '4:32:10');
  assertEquals(run!.metadata.overall_place, 12);
  assertEquals(run!.metadata.age_group_place, 3);
  assertEquals(run!.metadata.age_group, 'M40-49');
});

Deno.test('mapUltraSignUpResult tolerates the bib/time field aliases', () => {
  const run = mapUltraSignUpResult(ULTRA_FIXTURE[1], ULTRA_OPTS);
  assert(run !== null);
  assertEquals(run!.metadata.bib, '91');
  assertEquals(run!.duration_s, 5 * 3600 + 1 * 60 + 44);
  assertEquals(run!.metadata.overall_place, 21);
  assertEquals(run!.metadata.age_group, undefined);
});

Deno.test('mapUltraSignUpResult returns null on a DNF row with no usable time', () => {
  assertEquals(mapUltraSignUpResult(ULTRA_FIXTURE[2], ULTRA_OPTS), null);
});

Deno.test('mapUltraSignUpResult shares the dedup external_id shape with paste/runsignup', () => {
  const ultra = mapUltraSignUpResult({ bibno: '88', formattime: '4:32:10' }, ULTRA_OPTS);
  const paste = parseRaceResultRow({ bib: '88', chip_time: '4:32:10' }, ULTRA_OPTS);
  assertEquals(ultra!.external_id, paste!.external_id);
});

Deno.test('ultraSignUpResultsUrl includes uid/key/secret/format', () => {
  const url = ultraSignUpResultsUrl({ athleteId: 'uid-42', apiKey: 'KEY', apiSecret: 'SECRET' });
  assert(url.startsWith('https://ultrasignup.com/service/events.svc/results/athlete'));
  assert(url.includes('format=json'));
  assert(url.includes('uid=uid-42'));
  assert(url.includes('api_key=KEY'));
  assert(url.includes('api_secret=SECRET'));
});

Deno.test('extractUltraSignUpResults reads a bare array and a results wrapper', () => {
  assertEquals(extractUltraSignUpResults(ULTRA_FIXTURE).length, 3);
  assertEquals(extractUltraSignUpResults({ results: [{ bibno: '1' }] }).length, 1);
  assertEquals(extractUltraSignUpResults(null).length, 0);
  assertEquals(extractUltraSignUpResults({}).length, 0);
});

Deno.test('extractUltraSignUpResults caps a huge feed', () => {
  const big = Array.from({ length: MAX_RESULTS_ROWS + 100 }, () => ({ bibno: 'x' }));
  assertEquals(extractUltraSignUpResults(big).length, MAX_RESULTS_ROWS);
});

Deno.test('chronoTrackConfigured fails closed unless all three creds are set', () => {
  const full: Record<string, string> = {
    CHRONOTRACK_CLIENT_ID: 'cid',
    CHRONOTRACK_USER_ID: 'uid',
    CHRONOTRACK_PASSWORD: 'pw',
  };
  assert(chronoTrackConfigured((n) => full[n]));
  // Any one missing → unconfigured (the dev/CI default is all-unset).
  assertEquals(chronoTrackConfigured(() => undefined), false);
  for (const drop of Object.keys(full)) {
    const partial = { ...full, [drop]: '' };
    assertEquals(chronoTrackConfigured((n) => partial[n]), false);
  }
});

Deno.test('mapChronoTrackResult maps a ChronoTrack finisher onto a race run', () => {
  const run = mapChronoTrackResult(
    {
      results_bib: '1234',
      results_time: '1:47:23',
      results_gun_time: '1:48:01',
      results_rank: 142,
      results_division_rank: 12,
      results_division: 'M35-39',
    },
    OPTS,
  );
  assert(run !== null);
  assertEquals(run!.source, 'race');
  assertEquals(run!.distance_m, 21097);
  assertEquals(run!.duration_s, 1 * 3600 + 47 * 60 + 23);
  // Identical external_id + metadata shaping to the RunSignUp path (shared mapper).
  assertEquals(run!.external_id, 'race:Richmond Half Marathon:2025-09-21:1234');
  assertEquals(run!.metadata.race_name, 'Richmond Half Marathon');
  assertEquals(run!.metadata.bib, '1234');
  assertEquals(run!.metadata.chip_time, '1:47:23');
  assertEquals(run!.metadata.gun_time, '1:48:01');
  assertEquals(run!.metadata.overall_place, 142);
  assertEquals(run!.metadata.age_group_place, 12);
  assertEquals(run!.metadata.age_group, 'M35-39');
});

Deno.test('mapChronoTrackResult falls back to gun time + returns null with no time', () => {
  const gun = mapChronoTrackResult({ results_bib: '5', results_gun_time: '0:30:00' }, OPTS);
  assert(gun !== null);
  assertEquals(gun!.duration_s, 30 * 60);
  assertEquals(gun!.metadata.chip_time, undefined);
  assertEquals(gun!.metadata.gun_time, '0:30:00');
  assertEquals(mapChronoTrackResult({ results_bib: '9' }, OPTS), null);
});

Deno.test('chronoTrackResultsUrl includes creds/format and encodes the event id', () => {
  const url = chronoTrackResultsUrl({
    eventId: 'EVT 42',
    clientId: 'CID',
    userId: 'UID',
    password: 'PASS',
    bib: '77',
  });
  assert(url.startsWith('https://api.chronotrack.com/api/event/EVT%2042/results'));
  assert(url.includes('format=json'));
  assert(url.includes('client_id=CID'));
  assert(url.includes('user_id=UID'));
  assert(url.includes('user_pass=PASS'));
  assert(url.includes('bib=77'));
});

Deno.test('extractChronoTrackResults reads event_results + tolerates results + caps', () => {
  const nested = {
    event_results: [
      { results_bib: '1', results_time: '20:00' },
      { results_bib: '2', results_time: '21:00' },
    ],
  };
  assertEquals(extractChronoTrackResults(nested).length, 2);
  assertEquals(extractChronoTrackResults({ results: [{ results_bib: 'a' }] }).length, 1);
  assertEquals(extractChronoTrackResults(null).length, 0);
  assertEquals(extractChronoTrackResults({}).length, 0);
  const big = {
    event_results: Array.from({ length: MAX_RESULTS_ROWS + 100 }, () => ({ results_bib: 'x' })),
  };
  assertEquals(extractChronoTrackResults(big).length, MAX_RESULTS_ROWS);
});
