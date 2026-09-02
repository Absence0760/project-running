// Pure helpers for the provider race-calendar sync.
//
// The function pulls a provider's upcoming-races feed and reconciles it into
// `race_listings`. Everything here is network-free and side-effect-free, so the
// envelope walk, the date and distance readings, the constraint-shaped field
// caps and the batch reconciliation are testable without a credential — which
// matters more here than usual, because no credential exists for either
// provider and the live payload has therefore not been observed from this repo.
//
// **What that means for the field names below, stated rather than implied.**
// Each provider's reader is the ONLY place its spellings appear, and every one
// of them is optional-with-drop: a row that does not yield a name and a date
// becomes nothing, and the response reports how many did that. So a payload
// whose shape differs from the one declared here produces `synced: 0` with an
// `unusable` count equal to the row count — an operator sees it on the first
// call — rather than junk in a calendar every user of the deployment reads.
// The alternative, refusing to write the leg until a key arrives, is what left
// `{ synced: 0 }` hardcoded here for three months while the calendar could hold
// nothing but crowd submissions.

import { isIsoCalendarDate } from '../_shared/calendar_date.ts';

/// Bound the batch independently of upstream input, the same rule the two
/// importers apply to theirs. A provider feed for one region is tens of races;
/// this is a ceiling on a hostile or misconfigured response, not a page size.
export const MAX_LISTING_ROWS = 500;

/// `race_listings.name` is `char_length <= 120`, `location_label <= 80`
/// (migration `20270503_001`). A row that busts either raises 23514 and, in a
/// single-statement insert, loses every other race in the batch — so the cap
/// is applied here rather than hoped for.
export const MAX_LISTING_NAME_LEN = 120;
export const MAX_LISTING_LOCATION_LEN = 80;

/// The providers whose feeds this function knows how to read. A subset of
/// `race_listings_provider_check` — `parkrun`, `manual`, `chronotrack` and
/// `raceresult` reach the calendar by other paths.
export type ListingSyncProvider = 'runsignup' | 'ultrasignup';

/// A provider row reduced to exactly what a listing needs. Each provider's
/// reader produces one of these or null; nothing downstream sees a provider's
/// own field names.
export interface NormalisedRace {
  providerRaceId: string | null;
  name: string;
  date: string;
  distanceM: number | null;
  locationLabel: string | null;
  entryUrl: string | null;
  resultsUrl: string | null;
}

/// The row shape written to `race_listings`. `is_verified` is true because the
/// provider is the authority on its own races, and only the service role may
/// set it (the `race_listings_force_unverified` trigger forces false for anyone
/// else) — which is why this sync must not run on the caller's client.
export interface RaceListingUpsert {
  provider: ListingSyncProvider;
  provider_race_id: string | null;
  name: string;
  race_date: string;
  distance_m: number | null;
  location_label: string | null;
  entry_url: string | null;
  results_url: string | null;
  is_verified: true;
}

function text(raw: unknown, max: number): string | null {
  if (typeof raw === 'number' && Number.isFinite(raw)) return String(raw);
  if (typeof raw !== 'string') return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  return trimmed.length <= max ? trimmed : trimmed.slice(0, max);
}

/// A URL only if it satisfies `race_listings_{entry,results}_url_scheme_check`.
/// Anything else is dropped rather than written: the CHECK would refuse it and
/// take the whole batch insert with it.
export function listingUrl(raw: unknown): string | null {
  const v = text(raw, 2048);
  if (!v) return null;
  return /^https?:\/\//i.test(v) ? v : null;
}

/// A provider's race date as an ISO `YYYY-MM-DD`, or null.
///
/// Two forms are accepted and the second is the interesting one. An ISO date is
/// unambiguous and is taken whole, with any time-of-day suffix discarded — the
/// column is a `date`. A slash date is read as **US month-first**, which is a
/// provider-specific reading (RunSignUp and UltraSignup are US platforms, and
/// `parseParkrunDate` already reads the UK site's slashes day-first for the
/// mirror-image reason) — but only when the first component can BE a month.
/// `13/06/2027` is refused rather than reinterpreted as 6 January, so a feed
/// that turns out to be day-first announces itself on the first race past the
/// 12th of a month instead of silently seeding the calendar with transposed
/// dates. Two same-month days under the 13th stay genuinely ambiguous and are
/// read US — that is the irreducible part, and it is why the refusal above
/// matters. Every refusal is counted in the response's `unusable`.
export function parseProviderRaceDate(raw: unknown): string | null {
  const v = text(raw, 64);
  if (!v) return null;
  const iso = /^(\d{4}-\d{2}-\d{2})(?:[T ].*)?$/.exec(v);
  if (iso) return isIsoCalendarDate(iso[1]) ? iso[1] : null;
  const slash = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(v);
  if (!slash) return null;
  const [month, day, year] = [slash[1], slash[2], slash[3]];
  // The calendar check is what refuses a day-first date: `20/06/2027` becomes
  // the candidate `2027-20-06`, whose month is 20. An explicit `month > 12`
  // test in front of it was written first and could never fail — it is not
  // here, and the mirror-image assertions in lib.test.ts pin the behaviour
  // against this line instead.
  const candidate = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
  return isIsoCalendarDate(candidate) ? candidate : null;
}

/// Spellings that mean exactly one thing. `m` / `M` is deliberately ABSENT:
/// US race listings write miles as `M` while SI writes metres as `m`, and a
/// case-insensitive table collapses them — which files a 100-mile race as a
/// 100-metre one, at the wrong end of every distance band
/// `search_race_listings` sorts into. A case-SENSITIVE table would be worse
/// still, since it would silently pick one reading of a letter whose meaning in
/// this feed has not been observed. A null distance costs a race its band; a
/// wrong one puts it in somebody else's.
const UNIT_METRES: Record<string, number> = {
  meter: 1,
  meters: 1,
  metre: 1,
  metres: 1,
  k: 1000,
  km: 1000,
  kilometer: 1000,
  kilometers: 1000,
  kilometre: 1000,
  kilometres: 1000,
  mi: 1609.344,
  mile: 1609.344,
  miles: 1609.344,
};

/// A nominal race distance in whole metres, or null when it cannot be read.
///
/// `race_listings.distance_m` is nullable and `search_race_listings` buckets it
/// into race-distance bands, so an absent distance costs a race its band while
/// a WRONG one files a 5K under "ultra". A unit this does not recognise is
/// therefore null rather than assumed — the one assumption made is that a bare
/// number with no unit is already metres, which is the column's own unit.
export function distanceMetresFrom(value: unknown, units: unknown): number | null {
  const n = typeof value === 'number' ? value : Number(text(value, 32) ?? NaN);
  if (!Number.isFinite(n) || n <= 0) return null;
  const rawUnit = text(units, 32);
  if (rawUnit === null) return Math.round(n);
  const factor = UNIT_METRES[rawUnit.toLowerCase()];
  if (factor === undefined) return null;
  const metres = Math.round(n * factor);
  return metres > 0 ? metres : null;
}

function joinLocation(city: unknown, state: unknown, country: unknown): string | null {
  const parts = [text(city, 80), text(state, 80), text(country, 80)].filter(
    (p): p is string => p !== null,
  );
  if (parts.length === 0) return null;
  return text(parts.join(', '), MAX_LISTING_LOCATION_LEN);
}

/// A RunSignUp race object, as the `/Rest/races` envelope carries it.
///
/// **Unverified against a live payload** — see the module header. Every field is
/// optional and the two required ones are checked, so a mismatch drops the row
/// and is counted rather than guessed around.
export interface RunSignUpRaceRow {
  race_id?: unknown;
  name?: unknown;
  next_date?: unknown;
  last_date?: unknown;
  url?: unknown;
  results_url?: unknown;
  address?: unknown;
  distance?: unknown;
  distance_units?: unknown;
}

export function readRunSignUpRace(row: RunSignUpRaceRow): NormalisedRace | null {
  const name = text(row.name, MAX_LISTING_NAME_LEN);
  // `next_date` is the upcoming running; `last_date` is what a race that has
  // already happened carries. A calendar wants the first and can still file the
  // second, so the fallback is deliberate — but only one of them is read, never
  // merged.
  const date = parseProviderRaceDate(row.next_date) ?? parseProviderRaceDate(row.last_date);
  if (!name || !date) return null;
  const address = (row.address ?? {}) as Record<string, unknown>;
  return {
    providerRaceId: text(row.race_id, 200),
    name,
    date,
    distanceM: distanceMetresFrom(row.distance, row.distance_units),
    locationLabel: joinLocation(address.city, address.state, address.country),
    entryUrl: listingUrl(row.url),
    resultsUrl: listingUrl(row.results_url),
  };
}

/// An UltraSignup event row. Same unverified status, same drop-and-count rule.
export interface UltraSignUpRaceRow {
  eventid?: unknown;
  eventname?: unknown;
  eventdate?: unknown;
  url?: unknown;
  city?: unknown;
  state?: unknown;
  distance?: unknown;
  distance_units?: unknown;
}

export function readUltraSignUpRace(row: UltraSignUpRaceRow): NormalisedRace | null {
  const name = text(row.eventname, MAX_LISTING_NAME_LEN);
  const date = parseProviderRaceDate(row.eventdate);
  if (!name || !date) return null;
  return {
    providerRaceId: text(row.eventid, 200),
    name,
    date,
    distanceM: distanceMetresFrom(row.distance, row.distance_units),
    locationLabel: joinLocation(row.city, row.state, null),
    entryUrl: listingUrl(row.url),
    resultsUrl: null,
  };
}

/// Pull the flat race array out of a provider envelope, capped.
///
/// Tolerant of the nestings a REST feed of this shape uses, in the same
/// defensive style as `extractRunSignUpResults`: a bare array, a `races` array
/// whose members either ARE the race or wrap one under `race`, or a top-level
/// `events` array. Anything else yields nothing, which the caller reports.
export function extractProviderRaces(payload: unknown): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];
  const push = (v: unknown): boolean => {
    if (!v || typeof v !== 'object' || Array.isArray(v)) return true;
    const obj = v as Record<string, unknown>;
    const inner = obj.race;
    out.push(
      inner && typeof inner === 'object' && !Array.isArray(inner)
        ? inner as Record<string, unknown>
        : obj,
    );
    return out.length < MAX_LISTING_ROWS;
  };
  const walk = (rows: unknown): boolean => {
    if (!Array.isArray(rows)) return true;
    for (const r of rows) if (!push(r)) return false;
    return true;
  };
  if (Array.isArray(payload)) {
    walk(payload);
    return out;
  }
  if (!payload || typeof payload !== 'object') return out;
  const obj = payload as Record<string, unknown>;
  if (!walk(obj.races)) return out;
  if (out.length === 0) walk(obj.events);
  return out;
}

export function readProviderRace(
  provider: ListingSyncProvider,
  row: Record<string, unknown>,
): NormalisedRace | null {
  return provider === 'ultrasignup' ? readUltraSignUpRace(row) : readRunSignUpRace(row);
}

export function listingUpsertFrom(
  provider: ListingSyncProvider,
  race: NormalisedRace,
): RaceListingUpsert {
  return {
    provider,
    provider_race_id: race.providerRaceId,
    name: race.name,
    race_date: race.date,
    distance_m: race.distanceM,
    location_label: race.locationLabel,
    entry_url: race.entryUrl,
    results_url: race.resultsUrl,
    is_verified: true,
  };
}

export interface ListingBatch {
  /// Rows to INSERT: a provider race id this deployment has not stored.
  fresh: RaceListingUpsert[];
  /// Rows to UPDATE in place, keyed by their provider race id — a race whose
  /// date or venue moved must follow the provider rather than stay as first
  /// seen, which is the whole point of a sync over a one-time seed.
  existing: RaceListingUpsert[];
  /// Rows dropped because the feed named the same race twice, or because the
  /// row carries no provider race id at all.
  skipped: number;
}

/// Split mapped rows against what is already stored, and against the batch
/// itself.
///
/// The insert below is ONE statement against the partial unique index
/// `race_listings_provider_uniq`, so a feed that repeats a race would raise
/// 23505 and lose every OTHER race in it — the same failure `reconcileImportBatch`
/// exists to stop on the two importers.
///
/// A row with NO provider race id is dropped rather than inserted: the unique
/// index does not cover nulls, so such a row would be re-inserted on every sync
/// and the calendar would grow a duplicate an hour.
export function reconcileListingBatch(
  rows: RaceListingUpsert[],
  storedIds: readonly string[],
): ListingBatch {
  const stored = new Set(storedIds);
  const seen = new Set<string>();
  const fresh: RaceListingUpsert[] = [];
  const existing: RaceListingUpsert[] = [];
  let skipped = 0;
  for (const row of rows) {
    const id = row.provider_race_id;
    if (id === null || seen.has(id)) {
      skipped++;
      continue;
    }
    seen.add(id);
    if (stored.has(id)) existing.push(row);
    else fresh.push(row);
  }
  return { fresh, existing, skipped };
}

/// The stored columns a sync may rewrite, as PostgREST returns them.
export interface StoredListing {
  id: string;
  provider_race_id: string | null;
  name: string | null;
  race_date: string | null;
  distance_m: number | null;
  location_label: string | null;
  entry_url: string | null;
  results_url: string | null;
  is_verified: boolean | null;
}

/// Whether the provider's current answer differs from what is stored.
///
/// A sync that rewrote every matched row would issue one UPDATE per race on
/// every call — the partial unique index `race_listings_provider_uniq` cannot
/// be an `ON CONFLICT` arbiter through PostgREST (the predicate is
/// unexpressible, 42P10), so there is no single-statement upsert to fall back
/// on and each rewrite is its own round trip. In steady state a feed answers the
/// same thing it answered last hour, so comparing first makes the common case
/// zero writes and keeps the ones that do happen meaningful in the log.
export function listingDiffers(stored: StoredListing, next: RaceListingUpsert): boolean {
  return stored.name !== next.name ||
    stored.race_date !== next.race_date ||
    stored.distance_m !== next.distance_m ||
    stored.location_label !== next.location_label ||
    stored.entry_url !== next.entry_url ||
    stored.results_url !== next.results_url ||
    // A race a user submitted first lands unverified (the
    // `race_listings_force_unverified` trigger), and the provider catching up
    // with it is exactly when that should change.
    stored.is_verified !== true;
}

export interface NearHint {
  lng: number;
  lat: number;
  radiusM: number;
}

/// The default radius when a caller gives a point and no radius, in metres.
/// `search_race_listings` defaults its own proximity gate to 50 km; a discovery
/// sync that pulled a wider net than the search can show would write races
/// nobody can find.
export const DEFAULT_NEAR_RADIUS_M = 50_000;
export const MAX_NEAR_RADIUS_M = 200_000;

/// Read the optional region hint. `undefined` means "no hint" and is valid;
/// anything present but unusable is an ERROR rather than a silent fall back to
/// no hint, because a typo in a radius would otherwise pull the provider's
/// whole national feed and write it into the calendar as if it were local.
export function parseNearHint(
  raw: unknown,
): { ok: true; near: NearHint | null } | { ok: false; error: string } {
  if (raw === undefined || raw === null) return { ok: true, near: null };
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return { ok: false, error: 'invalid_near' };
  }
  const o = raw as Record<string, unknown>;
  const lng = o.lng;
  const lat = o.lat;
  if (typeof lng !== 'number' || !Number.isFinite(lng) || lng < -180 || lng > 180) {
    return { ok: false, error: 'invalid_near_lng' };
  }
  if (typeof lat !== 'number' || !Number.isFinite(lat) || lat < -90 || lat > 90) {
    return { ok: false, error: 'invalid_near_lat' };
  }
  let radiusM = DEFAULT_NEAR_RADIUS_M;
  if (o.radius_m !== undefined) {
    const r = o.radius_m;
    if (typeof r !== 'number' || !Number.isFinite(r) || r <= 0 || r > MAX_NEAR_RADIUS_M) {
      return { ok: false, error: 'invalid_near_radius' };
    }
    radiusM = Math.round(r);
  }
  return { ok: true, near: { lng, lat, radiusM } };
}

/// Build the provider's upcoming-races URL.
///
/// **The endpoints are unverified from here**, like the field names above, and
/// for the same reason — no credential exists for either provider. The failure
/// mode is the safe one and it is loud: a wrong path answers a non-2xx, which
/// the caller reports as `502 <provider> upstream <status>` and writes nothing,
/// exactly as its two sibling importers already do. A wrong URL costs one
/// request and announces itself; that is why writing the leg against a declared
/// endpoint is better than leaving `{ synced: 0 }` hardcoded.
export function providerRacesUrl(opts: {
  provider: ListingSyncProvider;
  apiKey: string;
  apiSecret: string;
  near: NearHint | null;
}): string {
  const u = opts.provider === 'ultrasignup'
    ? new URL('https://ultrasignup.com/service/events.svc/upcomingevents')
    : new URL('https://runsignup.com/Rest/races');
  u.searchParams.set('format', 'json');
  u.searchParams.set('api_key', opts.apiKey);
  u.searchParams.set('api_secret', opts.apiSecret);
  u.searchParams.set('results_per_page', String(MAX_LISTING_ROWS));
  if (opts.near) {
    u.searchParams.set('lat', String(opts.near.lat));
    u.searchParams.set('lng', String(opts.near.lng));
    // Both platforms are US and quote radii in miles.
    u.searchParams.set('radius', String(Math.max(1, Math.round(opts.near.radiusM / 1609.344))));
  }
  return u.toString();
}
