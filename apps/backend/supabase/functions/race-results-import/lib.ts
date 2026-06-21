// Pure helpers for the race-results importer.
//
// Import modes:
//   - 'runsignup'   — maps the RunSignUp REST get-results JSON onto runs rows.
//   - 'chronotrack' — maps the ChronoTrack Live (CTLive) results JSON onto runs
//                     rows; gated fail-closed on its own CHRONOTRACK_* creds.
//   - 'paste'       — maps a single user-pasted result row (any timing site that
//                     has no API) onto one runs row.
//
// Everything here is network-free + side-effect-free so the mapping, the field
// caps, and the external_id shape are unit-testable without live credentials
// (the EF itself returns 503 when a provider's creds are unset — see index.ts).

export const MAX_FIELD_LEN = 200;
export const MAX_RESULTS_ROWS = 2000;

/** Trim + truncate an untrusted text field. Non-strings become ''. */
export function capField(raw: unknown, max: number = MAX_FIELD_LEN): string {
  if (typeof raw !== 'string') return '';
  const trimmed = raw.trim();
  return trimmed.length <= max ? trimmed : trimmed.slice(0, max);
}

/** Parse "H:MM:SS" / "MM:SS" / "SS" into whole seconds. 0 on garbage. */
export function parseClockToSeconds(time: unknown): number {
  const s = capField(time);
  if (!s) return 0;
  const parts = s.split(':').map((p) => Number(p));
  if (parts.some((n) => !Number.isFinite(n) || n < 0)) return 0;
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 1) return parts[0];
  return 0;
}

/**
 * Build the cross-source dedup external_id for a race result.
 * Shape: `race:{name}:{date}:{bib}` (integrations.md dedup table). The pieces
 * are capped + colon-stripped so a scraped value can't break the delimiter or
 * grow the id past the per-user index's reach.
 */
export function raceExternalId(name: string, date: string, bib: string): string {
  const clean = (v: string) => capField(v, 80).replace(/:/g, ' ');
  return `race:${clean(name)}:${clean(date)}:${clean(bib)}`;
}

/** A finisher row as RunSignUp returns it (the fields we consume). */
export interface RunSignUpResult {
  bib_num?: unknown;
  chip_time?: unknown;
  clock_time?: unknown; // gun time
  place?: unknown; // overall place
  age_group_place?: unknown;
  age_group?: unknown;
}

export interface MappedRaceRun {
  started_at: string;
  duration_s: number;
  distance_m: number | null;
  source: 'race';
  activity_type: 'run';
  is_public: boolean;
  external_id: string;
  race_listing_id: string;
  metadata: Record<string, unknown>;
}

/**
 * Map one RunSignUp finisher onto a runs row for `userId`. `raceName` +
 * `raceDate` + `distanceM` come from the race_listings row being imported;
 * `chip_time` is authoritative for duration_s, falling back to clock (gun)
 * time when chip is absent. Returns null when there is no usable time at all
 * (a DNS/DNF row with no result is not a run).
 */
export function mapRunSignUpResult(
  r: RunSignUpResult,
  opts: {
    userId: string;
    listingId: string;
    raceName: string;
    raceDate: string;
    distanceM: number | null;
    isPublic: boolean;
  },
): MappedRaceRun | null {
  const chip = capField(r.chip_time);
  const gun = capField(r.clock_time);
  const durationS = parseClockToSeconds(chip || gun);
  if (durationS <= 0) return null;

  const bib = capField(r.bib_num);
  const startedAt = `${opts.raceDate}T10:00:00Z`;

  const metadata: Record<string, unknown> = {
    activity_type: 'run',
    race_name: capField(opts.raceName),
  };
  if (bib) metadata.bib = bib;
  if (chip) metadata.chip_time = chip;
  if (gun) metadata.gun_time = gun;
  const place = toPositiveInt(r.place);
  if (place != null) metadata.overall_place = place;
  const agPlace = toPositiveInt(r.age_group_place);
  if (agPlace != null) metadata.age_group_place = agPlace;
  const ag = capField(r.age_group, 40);
  if (ag) metadata.age_group = ag;

  return {
    started_at: startedAt,
    duration_s: durationS,
    distance_m: opts.distanceM,
    source: 'race',
    activity_type: 'run',
    is_public: opts.isPublic,
    external_id: raceExternalId(opts.raceName, opts.raceDate, bib),
    race_listing_id: opts.listingId,
    metadata,
  };
}

/** A single user-pasted result (the no-API path). */
export interface PasteResultInput {
  bib?: unknown;
  chip_time?: unknown;
  gun_time?: unknown;
  overall_place?: unknown;
  age_group_place?: unknown;
  age_group?: unknown;
}

/**
 * Map a single pasted result onto a runs row. Same shape + dedup id as the
 * RunSignUp path so a later provider sync of the same race can't create a
 * duplicate. Returns null when the paste has no usable time.
 */
export function parseRaceResultRow(
  input: PasteResultInput,
  opts: {
    userId: string;
    listingId: string;
    raceName: string;
    raceDate: string;
    distanceM: number | null;
    isPublic: boolean;
  },
): MappedRaceRun | null {
  return mapRunSignUpResult(
    {
      bib_num: input.bib,
      chip_time: input.chip_time,
      clock_time: input.gun_time,
      place: input.overall_place,
      age_group_place: input.age_group_place,
      age_group: input.age_group,
    },
    opts,
  );
}

function toPositiveInt(raw: unknown): number | null {
  const n = typeof raw === 'number' ? raw : Number(capField(raw));
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.floor(n);
}

/**
 * Whether the ChronoTrack Live leg has all three credentials provisioned.
 * Pure over a `(name) => value | undefined` getter so the fail-closed gate is
 * unit-testable without a Deno.env or the EF's heavy supabase-js import.
 */
export function chronoTrackConfigured(
  getEnv: (name: string) => string | undefined,
): boolean {
  return Boolean(
    getEnv('CHRONOTRACK_CLIENT_ID') &&
      getEnv('CHRONOTRACK_USER_ID') &&
      getEnv('CHRONOTRACK_PASSWORD'),
  );
}

/** A finisher row as the ChronoTrack Live API returns it (fields we consume). */
export interface ChronoTrackResult {
  results_bib?: unknown;
  results_time?: unknown; // chip / net time
  results_gun_time?: unknown; // gun time
  results_rank?: unknown; // overall place
  results_division_rank?: unknown; // age-group place
  results_division?: unknown; // age group label
}

/**
 * Map one ChronoTrack finisher onto a runs row for `userId`. Delegates to the
 * shared `mapRunSignUpResult` shaping so the run row shape, the time fallback
 * (chip → gun), the external_id, and the metadata keys are identical across
 * providers — only the provider-specific field names differ here.
 */
export function mapChronoTrackResult(
  r: ChronoTrackResult,
  opts: {
    userId: string;
    listingId: string;
    raceName: string;
    raceDate: string;
    distanceM: number | null;
    isPublic: boolean;
  },
): MappedRaceRun | null {
  return mapRunSignUpResult(
    {
      bib_num: r.results_bib,
      chip_time: r.results_time,
      clock_time: r.results_gun_time,
      place: r.results_rank,
      age_group_place: r.results_division_rank,
      age_group: r.results_division,
    },
    opts,
  );
}

/**
 * Build the ChronoTrack Live get-results URL. Centralised so the credential
 * handling (client_id + the user_id/user_pass basic-auth pair in the query
 * string, format=json) lives in one place and the URL is testable. `eventId`
 * is the ChronoTrack event id stored on the listing's `provider_race_id`.
 */
export function chronoTrackResultsUrl(opts: {
  eventId: string;
  clientId: string;
  userId: string;
  password: string;
  bib?: string;
}): string {
  const u = new URL(
    `https://api.chronotrack.com/api/event/${encodeURIComponent(opts.eventId)}/results`,
  );
  u.searchParams.set('format', 'json');
  u.searchParams.set('client_id', opts.clientId);
  u.searchParams.set('user_id', opts.userId);
  u.searchParams.set('user_pass', opts.password);
  if (opts.bib) u.searchParams.set('bib', opts.bib);
  return u.toString();
}

/**
 * Pull the flat finisher array out of the ChronoTrack Live results envelope,
 * capped. CTLive nests rows under `event_results[]`; tolerate a top-level
 * `results` too (the same defensive shape as the RunSignUp extractor).
 */
export function extractChronoTrackResults(payload: unknown): ChronoTrackResult[] {
  const out: ChronoTrackResult[] = [];
  if (!payload || typeof payload !== 'object') return out;
  const obj = payload as Record<string, unknown>;
  const rows = obj.event_results;
  if (Array.isArray(rows)) {
    for (const r of rows) {
      out.push(r as ChronoTrackResult);
      if (out.length >= MAX_RESULTS_ROWS) return out;
    }
  }
  if (out.length === 0 && Array.isArray(obj.results)) {
    for (const r of obj.results) {
      out.push(r as ChronoTrackResult);
      if (out.length >= MAX_RESULTS_ROWS) return out;
    }
  }
  return out;
}

/**
 * Build the RunSignUp get-results URL. Centralised so the scraper-hygiene
 * (api_key/api_secret in the query string, format=json) lives in one place and
 * the URL is testable. `userId` here is the runner's RunSignUp account id —
 * NOT our auth user id.
 */
export function runSignUpResultsUrl(opts: {
  raceId: string;
  apiKey: string;
  apiSecret: string;
  runSignUpUserId?: string;
}): string {
  const u = new URL(
    `https://runsignup.com/Rest/race/${encodeURIComponent(opts.raceId)}/results/get-results`,
  );
  u.searchParams.set('format', 'json');
  u.searchParams.set('api_key', opts.apiKey);
  u.searchParams.set('api_secret', opts.apiSecret);
  if (opts.runSignUpUserId) u.searchParams.set('user_id', opts.runSignUpUserId);
  return u.toString();
}

/**
 * Pull the flat finisher array out of the RunSignUp get-results envelope,
 * capped. The API nests results under
 * `individual_results_sets[].results[]`; tolerate a top-level `results` too.
 */
export function extractRunSignUpResults(payload: unknown): RunSignUpResult[] {
  const out: RunSignUpResult[] = [];
  if (!payload || typeof payload !== 'object') return out;
  const obj = payload as Record<string, unknown>;
  const sets = obj.individual_results_sets;
  if (Array.isArray(sets)) {
    for (const set of sets) {
      const rows = (set as Record<string, unknown>)?.results;
      if (Array.isArray(rows)) {
        for (const r of rows) {
          out.push(r as RunSignUpResult);
          if (out.length >= MAX_RESULTS_ROWS) return out;
        }
      }
    }
  }
  if (out.length === 0 && Array.isArray(obj.results)) {
    for (const r of obj.results) {
      out.push(r as RunSignUpResult);
      if (out.length >= MAX_RESULTS_ROWS) return out;
    }
  }
  return out;
}
