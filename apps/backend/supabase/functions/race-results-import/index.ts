import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { isValidUuid } from '../_shared/input_validation.ts';
import { withSentry } from '../_shared/sentry.ts';
import {
  chronoTrackConfigured,
  chronoTrackResultsUrl,
  chronoTrackScopeGate,
  extractChronoTrackResults,
  extractRunSignUpResults,
  extractUltraSignUpResults,
  filterResultsByBib,
  mapChronoTrackResult,
  mapRunSignUpResult,
  mapUltraSignUpResult,
  matchResultGate,
  parseRaceResultRow,
  runSignUpResultsUrl,
  runSignUpScopeGate,
  ultraSignUpResultsUrl,
  type MappedRaceRun,
} from './lib.ts';
import { publishableKey } from '../_shared/api_keys.ts';

interface RequestBody {
  provider?: unknown; // 'runsignup' | 'ultrasignup' | 'chronotrack' | 'paste'
  listingId?: unknown; // race_listings.id to import onto / link
  runSignUpUserId?: unknown; // runner's RunSignUp account id (optional filter)
  ultraSignUpAthleteId?: unknown; // runner's UltraSignup participant uid (optional)
  bib?: unknown; // ChronoTrack: filter results to one bib
  result?: unknown; // paste-mode single result row
  matchRunId?: unknown; // when set, enrich THIS existing run instead of inserting
  probe?: unknown; // when true, only report whether `provider` is configured
}

Deno.serve(withSentry('race-results-import', async (req: Request) => {
  const guarded = await readJsonWithLimit<RequestBody>(req, 8192);
  if ('tooLarge' in guarded) return guarded.tooLarge;

  // Authenticate before parsing the body (parity with parkrun-import).
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return Response.json({ error: 'unauthorized' }, { status: 401 });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    publishableKey(),
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: 'unauthorized' }, { status: 401 });

  const denied = await checkRateLimitTiered(supabase, user.id, 'race-results-import', 8, 32, 3600);
  if (denied) return denied;

  const body = (guarded.body ?? {}) as RequestBody;
  const provider = typeof body.provider === 'string' ? body.provider : '';

  // Provider-availability probe: report fail-closed (503 provider_not_configured)
  // when the named provider's credentials are unset, without needing a listing.
  // The ChronoTrack Settings card uses this to disable itself with an explainer.
  if (body.probe === true) {
    // Every credential-gated provider has to be probed, not just ChronoTrack:
    // reporting `configured: true` for runsignup / ultrasignup while their keys
    // are unset made the UI enable a card that 503s on the very next call.
    if (provider === 'chronotrack' && !chronoTrackConfigured((n) => Deno.env.get(n))) {
      return Response.json({ error: 'provider_not_configured' }, { status: 503 });
    }
    if (
      provider === 'runsignup' &&
      !(Deno.env.get('RUNSIGNUP_API_KEY') && Deno.env.get('RUNSIGNUP_API_SECRET'))
    ) {
      return Response.json({ error: 'provider_not_configured' }, { status: 503 });
    }
    if (
      provider === 'ultrasignup' &&
      !(Deno.env.get('ULTRASIGNUP_API_KEY') && Deno.env.get('ULTRASIGNUP_API_SECRET'))
    ) {
      return Response.json({ error: 'provider_not_configured' }, { status: 503 });
    }
    return Response.json({ configured: true });
  }

  const listingId = typeof body.listingId === 'string' ? body.listingId : '';
  if (!listingId) return Response.json({ error: 'listingId required' }, { status: 400 });
  // Without this the listing lookup below raises 22P02, which the
  // `listingErr || !listing` collapse reports as a 404 "not found" — a
  // malformed id looks to the caller like a missing race.
  if (!isValidUuid(listingId)) {
    return Response.json({ error: 'listingId must be a UUID' }, { status: 400 });
  }

  // The calendar is public-read through the redacted public_race_listings
  // view (20270320_001 — the base table is submitter-own-rows only), so the
  // user's own client resolves the race name / date / distance there.
  const { data: listing, error: listingErr } = await supabase
    .from('public_race_listings')
    .select('id, provider, provider_race_id, name, race_date, distance_m')
    .eq('id', listingId)
    .maybeSingle();
  if (listingErr || !listing) {
    return Response.json({ error: 'race listing not found' }, { status: 404 });
  }

  // Honour privacy_default (parity with parkrun / Strava / manual saves); any
  // read error falls closed to private.
  let isPublic = false;
  try {
    const { data: settings } = await supabase
      .from('user_settings')
      .select('prefs')
      .eq('user_id', user.id)
      .maybeSingle();
    const prefs = (settings?.prefs ?? null) as Record<string, unknown> | null;
    isPublic = prefs?.privacy_default === 'public';
  } catch (_) {
    isPublic = false;
  }

  const mapOpts = {
    userId: user.id,
    listingId: listing.id as string,
    raceName: (listing.name as string) ?? '',
    raceDate: (listing.race_date as string) ?? '',
    distanceM: (listing.distance_m as number | null) ?? null,
    isPublic,
  };

  let mapped: MappedRaceRun[] = [];

  if (provider === 'runsignup') {
    // Fail closed when the provider key is unconfigured. The whole RunSignUp
    // leg is gated on a missing API key (integrations.md); until it is
    // provisioned the EF is inert and the UI shows the unavailable explainer.
    const apiKey = Deno.env.get('RUNSIGNUP_API_KEY');
    const apiSecret = Deno.env.get('RUNSIGNUP_API_SECRET');
    if (!apiKey || !apiSecret) {
      return Response.json({ error: 'provider_not_configured' }, { status: 503 });
    }
    const raceId = (listing.provider_race_id as string | null) ?? '';
    if (!raceId) {
      return Response.json({ error: 'listing has no RunSignUp race id' }, { status: 400 });
    }
    // Fail closed: an unscoped fetch returns the entire finisher field, which
    // would be imported as the caller's own runs (issue #360). Require the
    // runner's RunSignUp user id or a bib before hitting the upstream.
    const runSignUpUserId =
      typeof body.runSignUpUserId === 'string' ? body.runSignUpUserId : undefined;
    const runSignUpBib = typeof body.bib === 'string' ? body.bib : undefined;
    const scope = runSignUpScopeGate({ runSignUpUserId, bib: runSignUpBib });
    if (!scope.ok) {
      return Response.json({ error: scope.error }, { status: scope.status });
    }
    const url = runSignUpResultsUrl({ raceId, apiKey, apiSecret, runSignUpUserId });
    const upstream = await fetch(url, {
      headers: { 'User-Agent': Deno.env.get('RACE_IMPORT_USER_AGENT') || 'RunApp/1.0' },
    });
    if (!upstream.ok) {
      // Fail loud on a non-2xx upstream rather than feeding an error page in.
      return Response.json({ error: `runsignup upstream ${upstream.status}` }, { status: 502 });
    }
    let payload: unknown;
    try {
      payload = await upstream.json();
    } catch (_) {
      return Response.json({ error: 'runsignup upstream not JSON' }, { status: 502 });
    }
    mapped = extractRunSignUpResults(payload)
      .map((r) => mapRunSignUpResult(r, mapOpts))
      .filter((r): r is MappedRaceRun => r !== null);
    // A bib-scoped request narrows here: the API filters only by user id, so
    // without this a bib-only request would still map the whole field.
    if (runSignUpBib) mapped = filterResultsByBib(mapped, runSignUpBib);
  } else if (provider === 'ultrasignup') {
    // Fail closed when the provider key is unconfigured — the UltraSignup leg
    // mirrors RunSignUp's missing-credential gate (integrations.md + the race
    // calendar ADR). Until the key is provisioned the EF is inert and the UI
    // shows the unavailable explainer.
    const apiKey = Deno.env.get('ULTRASIGNUP_API_KEY');
    const apiSecret = Deno.env.get('ULTRASIGNUP_API_SECRET');
    if (!apiKey || !apiSecret) {
      return Response.json({ error: 'provider_not_configured' }, { status: 503 });
    }
    // The athlete uid is the listing's provider_race_id for an UltraSignup
    // listing, or supplied per-call (a runner importing their own history).
    const athleteId = typeof body.ultraSignUpAthleteId === 'string' && body.ultraSignUpAthleteId
      ? body.ultraSignUpAthleteId
      : ((listing.provider_race_id as string | null) ?? '');
    if (!athleteId) {
      return Response.json({ error: 'listing has no UltraSignup athlete id' }, { status: 400 });
    }
    const url = ultraSignUpResultsUrl({ athleteId, apiKey, apiSecret });
    const upstream = await fetch(url, {
      headers: { 'User-Agent': Deno.env.get('RACE_IMPORT_USER_AGENT') || 'RunApp/1.0' },
    });
    if (!upstream.ok) {
      // Fail loud on a non-2xx upstream rather than feeding an error page in.
      return Response.json({ error: `ultrasignup upstream ${upstream.status}` }, { status: 502 });
    }
    let payload: unknown;
    try {
      payload = await upstream.json();
    } catch (_) {
      return Response.json({ error: 'ultrasignup upstream not JSON' }, { status: 502 });
    }
    mapped = extractUltraSignUpResults(payload)
      .map((r) => mapUltraSignUpResult(r, mapOpts))
      .filter((r): r is MappedRaceRun => r !== null);
  } else if (provider === 'chronotrack') {
    // Fail closed when the ChronoTrack Live credentials are unconfigured. The
    // whole ChronoTrack leg is gated on its own CHRONOTRACK_* creds; until they
    // are provisioned the EF is inert and the UI shows the unavailable explainer.
    if (!chronoTrackConfigured((n) => Deno.env.get(n))) {
      return Response.json({ error: 'provider_not_configured' }, { status: 503 });
    }
    const clientId = Deno.env.get('CHRONOTRACK_CLIENT_ID')!;
    const ctUserId = Deno.env.get('CHRONOTRACK_USER_ID')!;
    const password = Deno.env.get('CHRONOTRACK_PASSWORD')!;
    const eventId = (listing.provider_race_id as string | null) ?? '';
    if (!eventId) {
      return Response.json({ error: 'listing has no ChronoTrack event id' }, { status: 400 });
    }
    // Scope BEFORE the fetch, exactly as the RunSignUp leg does: an unscoped
    // ChronoTrack request returns the whole finisher field, and every row of it
    // would be inserted as the caller's own run (issue #360's failure mode, on
    // the provider that never got the gate).
    const ctScope = chronoTrackScopeGate({
      bib: typeof body.bib === 'string' ? body.bib : undefined,
    });
    if (!ctScope.ok) {
      return Response.json({ error: ctScope.error }, { status: ctScope.status });
    }
    const url = chronoTrackResultsUrl({
      eventId,
      clientId,
      userId: ctUserId,
      password,
      bib: typeof body.bib === 'string' ? body.bib : undefined,
    });
    const upstream = await fetch(url, {
      headers: { 'User-Agent': Deno.env.get('RACE_IMPORT_USER_AGENT') || 'RunApp/1.0' },
    });
    if (!upstream.ok) {
      // Fail loud on a non-2xx upstream rather than feeding an error page in.
      return Response.json({ error: `chronotrack upstream ${upstream.status}` }, { status: 502 });
    }
    let payload: unknown;
    try {
      payload = await upstream.json();
    } catch (_) {
      return Response.json({ error: 'chronotrack upstream not JSON' }, { status: 502 });
    }
    mapped = extractChronoTrackResults(payload)
      .map((r) => mapChronoTrackResult(r, mapOpts))
      .filter((r): r is MappedRaceRun => r !== null);
  } else if (provider === 'paste') {
    if (!body.result || typeof body.result !== 'object') {
      return Response.json({ error: 'result required for paste import' }, { status: 400 });
    }
    const one = parseRaceResultRow(body.result as Record<string, unknown>, mapOpts);
    if (!one) {
      return Response.json({ error: 'pasted result has no usable time' }, { status: 400 });
    }
    mapped = [one];
  } else {
    return Response.json({ error: 'unsupported provider' }, { status: 400 });
  }

  if (mapped.length === 0) {
    return Response.json({ imported: 0, skipped: 0, enriched: 0 });
  }

  // Enrich an existing recorded run rather than inserting a duplicate when the
  // user matched an in-app run to this race (the auto-match-on-record seam).
  // The match writes onto the runner's OWN run row (RLS-scoped) — a single
  // result is expected in this mode.
  const matchRunId = typeof body.matchRunId === 'string' ? body.matchRunId : '';
  if (matchRunId && !isValidUuid(matchRunId)) {
    return Response.json({ error: 'matchRunId must be a UUID' }, { status: 400 });
  }
  if (matchRunId) {
    // Enrich merges ONE result onto the caller's own run. More than one mapped
    // result is ambiguous — reject rather than stamp a stranger's mapped[0]
    // onto the run (issue #360).
    const gate = matchResultGate(mapped.length);
    if (!gate.ok) {
      return Response.json({ error: gate.error }, { status: gate.status });
    }
    const result = mapped[0];
    const { data: existing } = await supabase
      .from('runs')
      .select('id, metadata, user_id')
      .eq('id', matchRunId)
      .maybeSingle();
    if (!existing || existing.user_id !== user.id) {
      return Response.json({ error: 'run not found' }, { status: 404 });
    }
    const merged = {
      ...((existing.metadata as Record<string, unknown> | null) ?? {}),
      ...result.metadata,
    };
    const { error } = await supabase
      .from('runs')
      .update({ metadata: merged, race_listing_id: result.race_listing_id })
      .eq('id', matchRunId)
      .eq('user_id', user.id);
    if (error) {
      return Response.json({ error: 'failed to enrich run' }, { status: 500 });
    }
    return Response.json({ imported: 0, skipped: 0, enriched: 1 });
  }

  // Plain-insert path (no recorded counterpart). Dedupe per-user against
  // existing external_ids first — the runs.external_id index is a PER-USER
  // PARTIAL unique, which PostgREST onConflict can't target (see parkrun).
  const externalIds = mapped.map((r) => r.external_id);
  const { data: seenRows } = await supabase
    .from('runs')
    .select('external_id')
    .eq('user_id', user.id)
    .in('external_id', externalIds);
  const seen = new Set((seenRows ?? []).map((r) => r.external_id as string));
  const fresh = mapped
    .filter((r) => !seen.has(r.external_id))
    .map((r) => ({ ...r, id: crypto.randomUUID(), user_id: user.id }));
  const skipped = mapped.length - fresh.length;

  let imported = 0;
  if (fresh.length > 0) {
    const { error } = await supabase.from('runs').insert(fresh);
    if (error) {
      return Response.json({ error: 'race import failed to save' }, { status: 500 });
    }
    imported = fresh.length;
  }

  return Response.json({ imported, skipped, enriched: 0 });
}));
