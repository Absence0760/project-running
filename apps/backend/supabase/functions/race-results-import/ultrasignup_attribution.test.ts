/// The UltraSignup leg reads an ATHLETE feed and there is no listing it can
/// honestly attribute a row from it to.
///
/// `ultraSignUpResultsUrl` hits `/service/events.svc/results/athlete?uid=` —
/// one athlete's whole history, no race parameter — and every row that comes
/// back is mapped through the ONE `public_race_listings` row the request named.
/// The first test below measures that directly rather than describing it: three
/// results from three different races, one listing, three `runs` rows that
/// differ only in bib and finishing time. `ultraSignUpScopeGate` does not cover
/// it — requiring an athlete id is what makes the feed athlete-scoped in the
/// first place.
///
/// The other tests pin the refusal that closes it, at both doors a caller can
/// reach the leg through, and pin that it happens BEFORE the credential is read
/// and before anything is fetched.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-results-import/ultrasignup_attribution.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  extractUltraSignUpResults,
  type MappedRaceRun,
  mapUltraSignUpResult,
  ultraSignUpAttributionGate,
} from './lib.ts';

const SRC = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));

/// One athlete's history as the feed returns it: a 100-miler, a 100 km and a
/// road marathon, three years apart, three bibs.
const ATHLETE_HISTORY = [
  { bibno: '88', formattime: '4:32:10', place: 12, agerank: 3, agegroup: 'M40-49' },
  { bibno: '204', formattime: '28:40:15', place: 87, agerank: 9, agegroup: 'M40-49' },
  { bibno: '17', formattime: '2:58:44', place: 4, agerank: 1, agegroup: 'M40-49' },
];

const LISTING = {
  userId: 'u-1',
  listingId: 'L-9',
  raceName: 'Bighorn 100',
  raceDate: '2025-06-20',
  distanceM: 160934,
  isPublic: false,
};

Deno.test('the mapper cannot attribute: one listing swallows a whole history', () => {
  // Not a defect to be fixed in the mapper — the mapper is handed one listing
  // and has nothing else to go on. It is the measurement that says the REFUSAL
  // is the only correct answer while the row shape carries no race identifier.
  // If this ever stops holding, the leg has gained attribution and the gate
  // below should be lifted with it.
  const mapped = extractUltraSignUpResults(ATHLETE_HISTORY)
    .map((r) => mapUltraSignUpResult(r, LISTING))
    .filter((r): r is MappedRaceRun => r !== null);
  assertEquals(mapped.length, 3);
  assertEquals(new Set(mapped.map((m) => m.race_listing_id)).size, 1);
  assertEquals(new Set(mapped.map((m) => m.started_at)), new Set(['2025-06-20T10:00:00Z']));
  assertEquals(new Set(mapped.map((m) => m.distance_m)), new Set([160934]));
  assertEquals(new Set(mapped.map((m) => m.metadata.race_name)), new Set(['Bighorn 100']));
  // The 2:58 road marathon is now a 2:58 hundred-miler, and the external_ids
  // differ only by bib — so nothing downstream can tell the three apart either.
  assert(mapped.some((m) => m.duration_s === 2 * 3600 + 58 * 60 + 44));
  assertEquals(new Set(mapped.map((m) => m.external_id)).size, 3);
});

Deno.test('the leg refuses, on the seam both clients already act on', () => {
  const gate = ultraSignUpAttributionGate();
  assertEquals(gate.ok, false);
  assertEquals(gate.status, 503);
  // The clients disable their tile on this code; the reason is what stops an
  // operator who HAS set the key hunting for a missing one.
  assertEquals(gate.error, 'provider_not_configured');
  assertEquals(gate.reason, 'results_unattributable');
});

Deno.test('the refusal precedes the credential read and the fetch', () => {
  const branch = SRC.indexOf("} else if (provider === 'ultrasignup') {");
  assert(branch !== -1, 'the ultrasignup branch is gone');
  const gate = SRC.indexOf('ultraSignUpAttributionGate()', branch);
  const cred = SRC.indexOf("Deno.env.get('ULTRASIGNUP_API_KEY')", branch);
  const url = SRC.indexOf('ultraSignUpResultsUrl(', branch);
  assert(gate !== -1, 'the ultrasignup branch reaches no attribution gate');
  assert(cred !== -1 && url !== -1, 'the ultrasignup branch lost its credential read or its fetch');
  assert(gate < cred, 'the refusal must precede the credential read');
  assert(gate < url, 'the refusal must precede the outbound fetch');
  // And it must actually return on the refusal rather than compute one and
  // carry on — the shape a `const gate = ...` with no `if` would have.
  assert(
    /const attribution = ultraSignUpAttributionGate\(\);\s*if \(!attribution\.ok\) \{\s*return Response\.json\(/
      .test(SRC),
    'the attribution gate is computed but never returned on',
  );
});

Deno.test('the probe reports it unavailable too, whatever the keys say', () => {
  // Reporting `configured: true` here lights up a tile whose very next call
  // refuses. The old branch answered on key PRESENCE, so a provisioned deploy
  // would have advertised the leg.
  const probe = SRC.indexOf("if (isProbe) {");
  const end = SRC.indexOf("return Response.json({ configured: true });", probe);
  assert(
    probe !== -1 && end !== -1,
    'the probe block is gone, or its guard was renamed — re-anchor this rather ' +
      'than deleting the assertions below',
  );
  const block = SRC.slice(probe, end);
  assert(
    /provider === 'ultrasignup'[\s\S]{0,400}?ultraSignUpAttributionGate\(\)/.test(block),
    'the ultrasignup probe must answer through the attribution gate, not on key presence',
  );
  assert(
    !/provider === 'ultrasignup' &&[\s\S]{0,200}?ULTRASIGNUP_API_KEY/.test(block),
    'the ultrasignup probe still answers on key presence',
  );
});
