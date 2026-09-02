import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { publishableKey, secretKey } from '../_shared/api_keys.ts';
import {
  MAX_LISTING_ROWS,
  type RaceListingUpsert,
  type StoredListing,
  extractProviderRaces,
  listingDiffers,
  listingUpsertFrom,
  parseNearHint,
  providerRacesUrl,
  readProviderRace,
  reconcileListingBatch,
} from './lib.ts';

// Pull a provider's upcoming races into race_listings. GATED on the provider's
// API key: until one is provisioned this returns 503 and writes nothing — the
// fail-closed default the missing-credential rule requires.
//
// The fetch + reconcile used to be a stub returning `{ synced: 0 }`, deferred
// on the grounds that the response shape could not be observed without a key.
// That deferral cost more than it saved: no provider race could enter the
// calendar at all, so a fully provisioned deployment still held only parkrun,
// crowd submissions and hand inserts. The whole path is written now, with the
// gate staying in config — the shape this repo already prescribes for a feature
// blocked on a credential (decisions § 977). What the missing key genuinely
// prevents is VERIFYING the provider's field names and endpoint, so every
// reading in ./lib.ts is optional-with-drop and the response reports what it
// could not read: a payload shaped differently answers `synced: 0` with
// `unusable` equal to the row count on the first call, rather than writing junk
// into a calendar every user reads.
//
// It writes as the SERVICE ROLE, not as the caller: a provider race is
// `is_verified`, and the `race_listings_force_unverified` trigger forces false
// for every other role. The caller's own client is still what identifies them
// and spends their rate-limit bucket.

interface RequestBody {
  near?: unknown; // { lng, lat, radius_m } region hint
  provider?: unknown; // 'runsignup' (default) | 'ultrasignup' — which leg to gate/sync
  sync?: unknown; // true to actually walk the feed; anything else is a credential probe
}

Deno.serve(withSentry('race-listings-sync', async (req: Request) => {
  const guarded = await readJsonWithLimit<RequestBody>(req, 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return Response.json({ error: 'unauthorized' }, { status: 401 });

  const supabase = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    publishableKey(),
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: 'unauthorized' }, { status: 401 });

  const body = (guarded.body ?? {}) as RequestBody;
  const isSync = body.sync === true;

  // Two buckets, because these are two different costs wearing one name.
  //
  // A SYNC walks a provider's upcoming-races feed on OUR credential and writes
  // the shared public calendar rather than the caller's own rows, so 2/hour free
  // is right and a limiter that disappears on an RPC blip drops the only bound
  // on how often one account can drive it (decisions § 974).
  //
  // A PROBE reads two env vars and returns. Charging it to the sync's bucket was
  // a live defect and web's own client comment describes the symptom without
  // naming the cause: both `isRunSignUpConfigured` and `isUltraSignUpConfigured`
  // hit this function, so ONE page load spends a free user's whole 2/hour
  // allowance and the next load 429s — which `isProviderNotConfigured` then
  // fail-closes into "provider unavailable" for a provider that is configured
  // and working (decisions § 977). Its own generous bucket costs nothing and
  // removes the false unavailability.
  const denied = isSync
    ? await checkRateLimitTiered(supabase, user.id, 'race-listings-sync', 2, 8, 3600, {
      failClosed: true,
    })
    : await checkRateLimitTiered(supabase, user.id, 'race-listings-sync:probe', 60, 240, 3600, {
      failClosed: true,
    });
  if (denied) return denied;

  // Fail closed on the missing provider key — the chosen leg is inert until its
  // credential lands (integrations.md + decisions ADR). Defaults to RunSignUp so
  // the existing probe is unchanged; UltraSignup is gated symmetrically.
  // An unrecognised provider is refused, not silently read as the default.
  // Coercing it to RunSignUp gated the caller's request on a credential for a
  // provider they never asked for — a 503 when RunSignUp's key is missing, and
  // a `synced: 0` success once it lands, for a provider this function has
  // never heard of. `race-results-import` already answers 400 here and names
  // this the same class of bug as claiming an unconfigured leg is configured.
  const requested = body.provider ?? 'runsignup';
  if (requested !== 'runsignup' && requested !== 'ultrasignup') {
    return Response.json({ error: 'unknown_provider' }, { status: 400 });
  }
  const provider = requested;
  const apiKey = provider === 'ultrasignup'
    ? Deno.env.get('ULTRASIGNUP_API_KEY')
    : Deno.env.get('RUNSIGNUP_API_KEY');
  const apiSecret = provider === 'ultrasignup'
    ? Deno.env.get('ULTRASIGNUP_API_SECRET')
    : Deno.env.get('RUNSIGNUP_API_SECRET');
  if (!apiKey || !apiSecret) {
    return Response.json({ error: 'provider_not_configured' }, { status: 503 });
  }

  // Every caller in the tree today is a CREDENTIAL PROBE, not a sync: web's
  // `isRunSignUpConfigured` / `isUltraSignUpConfigured` invoke this with `{}`
  // and `{ provider: 'ultrasignup' }` to decide whether to offer the affordance
  // or the unavailable explainer, and mobile's `raceImportProviders` names it as
  // two `probeFunction`s. Nothing anywhere reads `synced`. While the leg was a
  // stub that cost nothing; now that it walks a provider feed and writes the
  // shared calendar, a page load must not trigger one — it would also spend the
  // 2/hour bucket, so the second probe in an hour would 429 and the tile would
  // read unavailable for the rest of it. So a sync is opt-IN, the same shape
  // `race-results-import` already uses for its own probe mode, and the default
  // answer is the credential verdict alone (decisions § 977).
  if (!isSync) {
    return Response.json({ configured: true });
  }

  const nearHint = parseNearHint(body.near);
  if (!nearHint.ok) {
    return Response.json({ error: nearHint.error }, { status: 400 });
  }

  const upstream = await fetch(
    providerRacesUrl({ provider, apiKey, apiSecret, near: nearHint.near }),
    { headers: { 'User-Agent': Deno.env.get('RACE_IMPORT_USER_AGENT') || 'RunApp/1.0' } },
  );
  if (!upstream.ok) {
    // Fail loud on a non-2xx rather than feeding an error page into the parser
    // and reporting `synced: 0`, which is indistinguishable from a region with
    // no races. Same rule as both sibling importers.
    return Response.json({ error: `${provider} upstream ${upstream.status}` }, { status: 502 });
  }
  let payload: unknown;
  try {
    payload = await upstream.json();
  } catch (_) {
    return Response.json({ error: `${provider} upstream not JSON` }, { status: 502 });
  }

  const rows = extractProviderRaces(payload);
  const listings: RaceListingUpsert[] = [];
  let unusable = 0;
  for (const row of rows) {
    const race = readProviderRace(provider, row);
    if (!race) {
      unusable++;
      continue;
    }
    listings.push(listingUpsertFrom(provider, race));
  }

  const complete = rows.length < MAX_LISTING_ROWS;
  if (listings.length === 0) {
    return Response.json({
      synced: 0,
      updated: 0,
      skipped: 0,
      unusable,
      total: rows.length,
      complete,
    });
  }

  const service = createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey());

  const ids = listings
    .map((l) => l.provider_race_id)
    .filter((id): id is string => id !== null);
  // One string literal: a concatenated column list infers as `string` and
  // silently degrades the typed client to `any`.
  const { data: storedRows, error: readErr } = await service
    .from('race_listings')
    .select('id, provider_race_id, name, race_date, distance_m, location_label, entry_url, results_url, is_verified')
    .eq('provider', provider)
    .in('provider_race_id', ids);
  if (readErr) {
    // A read that failed is not an empty calendar. Proceeding would insert every
    // race again and duplicate the whole feed.
    console.error('race-listings-sync: existing-listing read failed', readErr.message);
    return Response.json({ error: 'listing_read_failed' }, { status: 500 });
  }

  const stored = new Map<string, StoredListing>();
  for (const row of (storedRows ?? []) as StoredListing[]) {
    if (row.provider_race_id !== null) stored.set(row.provider_race_id, row);
  }

  const batch = reconcileListingBatch(listings, [...stored.keys()]);

  let synced = 0;
  if (batch.fresh.length > 0) {
    const { error } = await service.from('race_listings').insert(batch.fresh);
    if (error) {
      console.error('race-listings-sync: insert failed', error.message);
      return Response.json({ error: 'listing_insert_failed' }, { status: 500 });
    }
    synced = batch.fresh.length;
  }

  // Only the rows whose stored answer actually differs. The partial unique index
  // cannot arbitrate an ON CONFLICT through PostgREST, so each rewrite is its own
  // round trip and a sync that rewrote everything would issue one per race every
  // hour.
  let updated = 0;
  for (const row of batch.existing) {
    const current = stored.get(row.provider_race_id!)!;
    if (!listingDiffers(current, row)) continue;
    const { error } = await service
      .from('race_listings')
      .update({
        name: row.name,
        race_date: row.race_date,
        distance_m: row.distance_m,
        location_label: row.location_label,
        entry_url: row.entry_url,
        results_url: row.results_url,
        is_verified: true,
      })
      .eq('id', current.id);
    if (error) {
      console.error('race-listings-sync: update failed', error.message);
      return Response.json({ error: 'listing_update_failed' }, { status: 500 });
    }
    updated++;
  }

  return Response.json({
    synced,
    updated,
    skipped: batch.skipped,
    unusable,
    total: rows.length,
    complete,
  });
}));
