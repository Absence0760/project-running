# Race calendar + results import — implementation plan

> **Status:** Planned — specced 2026-06-15, not yet built. This is an implementation handoff plan, not a description of shipped behaviour. Tracked in [roadmap.md § Planned features](../product/roadmap.md#planned-features--specced-2026-06-15).

## Goal & user value

Parity backlog item #10: let a runner **discover races near them** (a searchable calendar of upcoming races with date, distance, location, and an **entry/registration link**), and **auto-match a recorded run to its official race result** so the chip time, place, and splits land on the run automatically. Today the only race-adjacent surfaces are club *events* (intra-club) and the parkrun scraper (one provider, manual athlete-number entry). This adds a first-class, cross-provider **race calendar** plus a **results-import + auto-match-on-record seam** that works for RunSignUp (built behind a missing-API-key gate, per `docs/features/integrations.md`) and parkrun (already shipped), and degrades to manual paste for everything else.

## What already exists to build on (verified)

- **`docs/features/integrations.md § Race results (RunSignUp + general scraping)`** — the design source. RunSignUp REST API (`GET runsignup.com/Rest/race/{race_id}/results/get-results`, API-key gated), parkrun scrape (shipped), general timing-platform URL patterns (ChronoTrack / RaceResult / UltraSignup), and the **race `external_id` format `race:{race-name}:{date}:{bib}`** + `source = 'race'`.
- **`apps/backend/supabase/functions/parkrun-import/index.ts`** + its `lib.ts` — the **exact pattern to mirror** for a race-results importer EF: auth-before-parse, per-user tiered rate limit (`checkRateLimitTiered`), `readJsonWithLimit` / body caps, `withSentry`, fail-loud on non-2xx upstream, `privacy_default`-honouring `is_public`, upsert with `onConflict: external_id`, cap helpers in `lib.ts`.
- **`runs` table + metadata race fields** — `docs/backend/metadata.md § Race fields` **already reserves four owner-only keys with no writer**: `race_name`, `bib`, `overall_place`, `chip_time` (all stripped from `public_runs` by `20260714_001`). This plan **builds the writer**. The additional keys this plan introduces — `gun_time`, `age_group_place`, `age_group` — are **NOT yet in the registry**; this plan must add a registry row for each (same owner-only classification + `public_runs` strip) in the same turn it writes them, per the metadata-key registry rule. `runs.source` CHECK already includes `'race'` (`20260505_001_narrow_union_check_constraints.sql`).
- **`runs.external_id`** unique-per-user index → dedupe via `ON CONFLICT (external_id) DO NOTHING` (the cross-source dedup strategy in integrations.md).
- **`integrations` table** + `IntegrationProvider = 'strava' | 'garmin' | 'parkrun' | 'runsignup'` (`apps/web/src/lib/types.ts:151`, CHECK in `20260505_001`) — **`runsignup` is already a permitted provider**. OAuth-style connect rows live here.
- **`apps/web/src/routes/settings/integrations/+page.svelte`** + the mobile `settings_integrations_screen.dart` — where a "Connect RunSignUp" / "Import race results" card belongs (the parkrun card is here).
- **Discover surface precedent** — `apps/web/src/routes/social/+page.svelte` + `apps/web/src/lib/components/SocialDiscover.svelte` + the `search_public_events` RPC (`20270110_001`, with `pg_trgm` discipline index, proximity via `clubs.location_point` + `p_center_lng/lat/radius_m`, `geocodePlace` in `apps/web/src/lib/routes/geocoding`). The race calendar's discovery UI **directly mirrors `SocialDiscover`** (category/place/time filters, "near me" geolocation).
- **Run save path** — `packages/run_recorder/lib/src/run_recorder.dart` (recorder state machine) and `packages/api_client/lib/src/api_client.dart` (`upsertRun*`, `onConflict: RunRow.colExternalId`) — where the auto-match-on-record seam hooks in (post-save, layered-resilience-wrapped).
- **Run-detail** `apps/web/src/routes/runs/[id]/+page.svelte` + mobile `apps/mobile_android/lib/screens/run_detail_screen.dart` — where a matched race result + "Find my result" affordance render.

## Data model / migrations

One migration. **Number is a placeholder — assign the next free sequential number at landing** (e.g. `2027XXXX_001_race_calendar.sql`; latest on `main` at spec time is `20270202_001`). The fundraising plan also wants the next slot, so coordinate so the two don't collide.

Two new tables: `races` (the calendar) and `race_results` is **already taken** by clubs (`20260424_001_event_results.sql` defines `event_results`, and there is no top-level `race_results`). Use **`race_listings`** for the calendar and **`race_result_imports`** for raw imported provider results — but the simplest durable design reuses the existing `runs` row as the result store (the integrations.md design maps a result straight onto a `run` with `source = 'race'`). So:

- **`race_listings`** — the discoverable calendar (one row per real-world race).
- **No separate results table** — an imported/auto-matched result is **written onto the runner's `runs` row** (`source = 'race'`, `external_id = race:{...}`, the metadata race fields that already exist in the registry). This avoids a parallel results entity and reuses the dedup index + privacy strip already built. A nullable `runs.race_listing_id` FK links a matched run back to its calendar entry (mirrors `runs.event_id`).

```sql
-- ── race_listings (the calendar) ─────────────────────────────────────────────
create table race_listings (
  id              uuid primary key default gen_random_uuid(),
  provider        text not null,              -- RaceProvider union (below)
  provider_race_id text,                      -- e.g. RunSignUp race_id; null for manual
  name            text not null,
  race_date       date not null,
  distance_m      integer,                    -- nominal distance; null if unknown/multi
  location_label  text,                       -- "Boston, MA"
  location_point  geography(point, 4326),     -- for proximity search (clubs.location_point precedent)
  entry_url       text,                       -- registration link (http/https CHECK)
  results_url     text,                       -- where results live, when known
  submitted_by    uuid references auth.users on delete set null,  -- crowd-submitted listings
  is_verified     boolean not null default false,  -- admin/provider-verified vs user-submitted
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

alter table race_listings add constraint race_listings_provider_check
  check (provider in ('runsignup', 'parkrun', 'manual', 'chronotrack', 'raceresult', 'ultrasignup'));
alter table race_listings add constraint race_listings_entry_url_scheme_check
  check (entry_url is null or entry_url ~* '^https?://');
alter table race_listings add constraint race_listings_results_url_scheme_check
  check (results_url is null or results_url ~* '^https?://');

-- one listing per provider race; manual listings dedup loosely on (name,date)
create unique index race_listings_provider_uniq
  on race_listings (provider, provider_race_id) where provider_race_id is not null;
create index race_listings_date_idx on race_listings (race_date);
create index race_listings_location_gist on race_listings using gist (location_point);
create index race_listings_name_trgm
  on race_listings using gin (name extensions.gin_trgm_ops);  -- pg_trgm, like events_discipline_trgm

alter table race_listings enable row level security;

-- Public read (a race calendar is public discovery data). Anyone, incl. anon.
create policy "race listings readable by all"
  on race_listings for select using (true);
-- Authenticated users may submit a listing (is_verified stays false until an
-- admin/import verifies). A trigger forces is_verified = false on user INSERT.
create policy "users submit race listings"
  on race_listings for insert to authenticated with check (submitted_by = auth.uid());
-- Submitter may edit their own unverified listing; verified ones are locked.
create policy "submitters edit own unverified listings"
  on race_listings for update to authenticated
  using (submitted_by = auth.uid() and is_verified = false)
  with check (submitted_by = auth.uid() and is_verified = false);

-- ── runs linkage ─────────────────────────────────────────────────────────────
alter table runs add column race_listing_id uuid references race_listings on delete set null;
create index runs_race_listing_idx on runs (race_listing_id) where race_listing_id is not null;
```

**The proximity + soonest-first discovery RPC** (copy `search_public_events` from `20270110_001`, `security invoker`, public-scoped):

```sql
create or replace function search_race_listings(
  p_query    text default null,    -- name ILIKE / trgm
  p_distance text default null,    -- '5k' | '10k' | 'half' | 'marathon' | 'ultra' (band → metres range)
  p_from     date default null,    -- date window
  p_to       date default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m   double precision default null,
  p_limit    int  default 60
) returns table (... race_listings cols + distance_m_away ...) ...
```

**Two narrow unions** (TS union + CHECK in lockstep; append to `apps/web/scripts/check_constraint_unions.mjs` `PAIRS`):

```
RaceProvider = 'runsignup' | 'parkrun' | 'manual' | 'chronotrack' | 'raceresult' | 'ultrasignup'
RaceDistanceBand = '5k' | '10k' | 'half' | 'marathon' | 'ultra'   (client-side only — derived; no CHECK column unless persisted)
```

Note: `runs.source = 'race'` and the metadata race fields are **already in the schema/registry** — no change needed there beyond writing values. `race_listing_id` is a new real column → both type generators run.

**Two codegen commands (mandatory):**

```
cd apps/backend && npm run gen:types
dart run scripts/gen_dart_models.dart
```

**`public_runs` strip**: `race_name`/`bib`/`overall_place`/`chip_time` are already stripped (`20260714_001`). The new `runs.race_listing_id` column is **non-sensitive** (it just links to a public calendar entry) — confirm it passes through the `public_runs` projection or add it to the denylist in this migration if owner-only is preferred (recommend: pass-through, it reveals nothing the public results page doesn't).

## Web implementation (canonical)

Web-first (`decisions.md §24`). Paths under `apps/web/src/`.

**Edge Functions (new, under `apps/backend/supabase/functions/`):**
- `race-results-import/index.ts` + `lib.ts` — **mirror `parkrun-import` closely.** Two modes by `provider`:
  - `runsignup` — call the RunSignUp REST results endpoint with `RUNSIGNUP_API_KEY` (Edge-only env). **Fail closed**: if the key is unset, return `503 provider_not_configured` (the design-around-the-missing-key requirement). Parse `get-results` JSON → map each finisher to a `run` row (`source='race'`, `external_id=race:{name}:{date}:{bib}`, metadata `race_name/bib/chip_time/gun_time/overall_place/age_group_place/age_group`, `distance_m` from the listing). Upsert `onConflict: external_id`. Honour `privacy_default`.
  - `paste` / `general` — accept a results URL or bib+race; for the v1 the durable path is **structured paste** (the user pastes their result row from a non-API timing site) rather than a brittle per-site scraper. Build the scraper hooks (URL-pattern dispatch in `lib.ts`) and ship the RunSignUp + **UltraSignup** + paste paths; ChronoTrack / RaceResult per-site scrapers stay scoped follow-ups (the integrations.md fragility warning). **UltraSignup leg shipped (2026-06-20, decisions §185)** — the RunSignUp pattern with its own `ULTRASIGNUP_API_KEY` / `ULTRASIGNUP_API_SECRET` fail-closed gate (unset → 503 `provider_not_configured`), `extractUltraSignUpResults` in `race-results-import/lib.ts`, the `race-listings-sync` per-provider probe, a Settings integrations card + web data-layer surface; 20 lib tests + a Playwright fail-closed-gate e2e.
  - Pure parsing/mapping (`mapRunSignUpResult`, `parseRaceResultRow`, field caps) lives in `lib.ts` for unit testing without network.
- `race-listings-sync/index.ts` (optional, deferrable) — pull upcoming RunSignUp races near a region into `race_listings`. **Also gated on `RUNSIGNUP_API_KEY`.** v1 can rely on user-submitted + manual listings + on-demand import; auto-sync is a follow-up. Keep the EF stub fail-closed so the seam exists.

**`data.ts` helpers (`apps/web/src/lib/core/data.ts`):**
- `searchRaceListings(filters)` → `RaceListingResult[]` (calls `search_race_listings`; mirror `searchPublicEvents` exactly, incl. `geocodePlace` center + geolocation).
- `submitRaceListing(input)` / `updateRaceListing` — crowd-submitted calendar entry.
- `importRaceResult({ provider, listingId, ... })` → invokes `race-results-import`.
- `fetchRaceResultForRun(runId)` → reads the run's race metadata + linked listing (for run-detail render).
- `findRaceMatchCandidates(runId)` → the auto-match seam (below): given a run's `started_at` + GPS start point + distance, return nearby same-day `race_listings` to offer "Is this your race?".

**types.ts overlays:**
- `RaceProvider` union; `RaceListing = Omit<RaceListingRow, 'provider'> & { provider: RaceProvider }`; `RaceListingResult` (RPC projection with `distance_m_away`).

**Routes / components (new):**
- `apps/web/src/routes/races/+page.svelte` + `+page.ts` — the **race calendar / discovery** page. **Reuse `SocialDiscover`'s structure**: name search, distance-band chips, date window, "near me / near a place" (geolocation + `geocodePlace`), result cards (name, date, distance, location, "X km away", **Register** link to `entry_url`, **Import my result** when results are available). A "Submit a race" affordance for crowd listings.
- `apps/web/src/lib/components/RaceCalendarCard.svelte` — a discovery result card.
- `apps/web/src/lib/components/RaceListingEditor.svelte` — submit/edit a manual listing.
- **Settings → Integrations** `apps/web/src/routes/settings/integrations/+page.svelte` — add a **RunSignUp card** ("Connect to import race results"; disabled with an explainer when `RUNSIGNUP_API_KEY` is unconfigured server-side — surface via a `503` probe) and keep the existing parkrun card.
- **Run-detail** `apps/web/src/routes/runs/[id]/+page.svelte` — if the run has race metadata, render the official result (chip time, place, race name, link to the listing). If not, an owner-only **"Find my race result"** button that runs `findRaceMatchCandidates` → pick a listing → `importRaceResult` (or manual paste).

**Nav placement (web)**: add `/races` to the primary discovery nav alongside `/social` and `/routes` (web has no 6-tab limit). The legacy-free top-level `/races` is the canonical URL.

## The auto-match-on-record seam (the load-bearing piece)

When a run finishes recording, offer to match it to an official race result — **never auto-write silently** (data-trust "inform" tier, `multi_modal.md §63`):

1. **After local save** (post `run_recorder.stop()` + upsert), a **best-effort, fire-and-forget, try/catch-wrapped** check (layered resilience — an auxiliary L4 effect that must never break the L0/L1 save): does a `race_listings` row exist with `race_date == run.started_at::date` **and** `location_point` within ~5 km of the run's start point **and** a distance band matching the run's distance? This is the pure predicate `raceMatchScore(run, listing)` (parity pair, below).
2. If a candidate is found, surface a **non-blocking prompt** on the run-detail / post-run summary: *"Was this the {race name}? Import your official result."* — the user confirms; nothing writes to their run's race metadata without that tap.
3. On confirm → `importRaceResult` fetches the official result (RunSignUp by bib, or manual paste) and stamps `race_name/bib/chip_time/overall_place` + `race_listing_id` onto the **existing** run row (not a new run — dedup: the recorded run already exists; the import enriches it, matched on the same `external_id`-or-run-id, so a later provider sync via `external_id` doesn't create a duplicate).
4. **Dedup invariant**: a run recorded in-app (`external_id = app:{uuid}`) that is later matched to a race must not also produce a second `race:{...}` run. The match writes onto the in-app run and sets `race_listing_id`; the importer's `onConflict` path is only for results with **no** recorded counterpart (a runner who didn't record but wants the result).

## Mobile implementation (Android + iOS twin)

Byte-identical across `apps/mobile_android/lib/` and `apps/mobile_ios/lib/` (+ tests), `decisions.md §39`.

- **Service** `apps/mobile_android/lib/` — add a `race_service.dart` (or extend an existing service) with `searchRaceListings`, `importRaceResult`, `findRaceMatchCandidates`, `fetchRaceResultForRun`.
- **Discovery screen** `apps/mobile_android/lib/screens/races_screen.dart` — mirrors the web calendar (search, distance chips, near-me, register link via `url_launcher`). **Reuse, don't grow the bottom nav**: surface Races as an entry inside the existing Social area (where Clubs / Discover already live as sub-tabs) or the Fitness-hub "Runs" area — **do not add a new bottom-nav destination** (the shell is a hard 4 nav tabs + centre Log FAB = 5 slots; clubs is a sub-tab of Social, not its own slot — see `apps/mobile_android/CLAUDE.md` + `decisions.md §63`). Place it as a sub-route reachable from the existing discovery surface.
- **Auto-match prompt** — the post-run summary / `run_detail_screen.dart` shows the non-blocking "Was this the {race}? Import result" card when `findRaceMatchCandidates` returns a hit. The recorder-side seam lives in the shared `packages/run_recorder` only as data (it does not call network); the network check runs in the app layer after save, `tester.runAsync`-friendly and try/catch-wrapped.
- **Settings → Integrations** `apps/mobile_android/lib/screens/settings_integrations_screen.dart` — add the RunSignUp tile (web-checkout-free; results import runs through the same EF). Disabled-with-explainer when the provider key is unconfigured.
- **iOS twin**: mirror every Dart file + test byte-for-byte.

## TS↔Dart parity helpers

- **`race_match`** — new parity pair: web `apps/web/src/lib/integrations/race_match.ts` ↔ mobile `apps/mobile_android/lib/race_match.dart` (+ iOS twin). Pure: `raceDistanceBand(distanceM)` (metres → `'5k'|'10k'|'half'|'marathon'|'ultra'` with tolerance bands), and `raceMatchScore({ runDate, runStartLatLng, runDistanceM }, listing)` → a 0–1 confidence (same-day + within-radius + distance-band-match), with a threshold above which a candidate is offered. Deterministic, no I/O. **Matched test counts** (≥14 each). Add to the root `CLAUDE.md` lockstep list.
- The RunSignUp JSON→run mapping stays in the EF `lib.ts` (server-only, Deno-tested) — not a parity pair (mobile doesn't import directly; it calls the EF).

## Tests (same commit as each piece)

- **Playwright (`apps/web/tests-e2e/`):**
  - `races/race-calendar-discover.spec.ts` — search by name/distance/near-me; register link present; submit a manual listing.
  - `races/race-result-import-manual.spec.ts` — paste a result onto a run; metadata renders on run-detail; private run keeps race fields owner-only.
  - `races/runsignup-gate.spec.ts` — with the key unconfigured, the RunSignUp card is disabled with an explainer (no crash).
- **pgtap (`apps/backend/supabase/tests/`):**
  - `race_listings_rls_test.sql` — anon reads listings; a user can submit (forced `is_verified=false`); cannot edit a verified listing; cannot forge `is_verified`.
  - `race_listing_link_test.sql` — `runs.race_listing_id` FK + the `public_runs` projection still strips the owner-only race metadata.
- **Deno (next to the EF):** `race-results-import/lib.test.ts` — RunSignUp JSON mapping, field caps, `external_id` shape, fail-closed on missing key (the EF returns 503).
- **node:test (web pure):** `apps/web/src/lib/integrations/race_match.test.ts` (≥14).
- **Flutter (`apps/mobile_android/test/` + iOS twin):** `race_match_test.dart` (parity-matched ≥14); `races_screen_test.dart` widget test (search renders, near-me gated); a `run_detail_screen_test.dart` assertion for the auto-match prompt + matched-result render. **Bake in the mobile-test gotchas**: store I/O needs `tester.runAsync`, avoid `pumpAndSettle` on map/cursor animations.

## i18n keys to add (all six web locales + all mobile ARBs)

Web `apps/web/src/lib/i18n/locales/{en,de,es,fr,ja,pt-BR}.ts`; mobile `apps/mobile_android/lib/l10n/app_{en,de,es,fr,ja,pt,pt_BR}.arb` (+ iOS twin). Representative:

- `races.title`, `races.searchPlaceholder`, `races.nearMe`, `races.nearPlace`, `races.distance5k/10k/half/marathon/ultra`, `races.kmAway`
- `races.register`, `races.viewResults`, `races.importResult`, `races.submitRace`, `races.unverified`
- `races.findMyResult`, `races.matchPrompt` (`"Was this the {name}? Import your official result."`), `races.matchConfirm`, `races.imported`
- `races.officialResult`, `races.chipTime`, `races.overallPlace`, `races.ageGroupPlace`, `races.bib`
- `integrations.runsignup`, `integrations.runsignupConnect`, `integrations.runsignupUnavailable` (key-unconfigured explainer)

## Docs to update (same turn)

- `docs/product/roadmap.md` — tick item #10 (race discovery + results import), noting RunSignUp gated on the key + per-site scrapers deferred.
- `docs/product/parity.md` — new rows: Race calendar (web ✓ / mobile ✓ / watch ✗); Race results import (web ✓ / mobile ✓ / watch ✗); auto-match (mobile-led, the recording platforms).
- `docs/features/integrations.md` — update the RunSignUp + race-results section from "no writer in source today" to "shipped behind `RUNSIGNUP_API_KEY` gate"; document the `race_listings` table, the import EF, and the auto-match seam.
- `docs/backend/metadata.md § Race fields` — flip the existing four keys' "no writer in source today" notes to point at `race-results-import` as the writer, AND add registry rows for the three new keys (`gun_time`, `age_group_place`, `age_group`) with the same owner-only + `public_runs`-stripped classification. Any new key the importer writes that should stay private must also be added to the `public_runs` strip denylist in this plan's migration (`20260714_001` only strips the original four).
- `docs/backend/api_database.md` — `race_listings` table + RLS + the `runs.race_listing_id` column + `search_race_listings` RPC.
- `docs/architecture/decisions.md` — ADR: *"Race results are stored on the `runs` row (`source='race'`), not a parallel results table; a `race_listings` calendar is publicly discoverable (one `security invoker` RPC, the search_public_events precedent); auto-match-on-record is an inform-tier, layered-resilience-wrapped post-save check that never writes without confirmation; RunSignUp is built fail-closed behind a missing API key, parkrun stays the shipped scraper, per-site scrapers are scoped follow-ups."*
- Root `CLAUDE.md` — add `race_match` to the parity-pair lockstep list.
- `docs/testing/e2e_dev_accounts.md` — add RunSignUp API key to the dev-account checklist.

## Gating / compliance

- **RunSignUp API key is a genuine external blocker** (`integrations.md` says it's blocked on the key) → build the whole code path, gate it fail-closed: `race-results-import` and `race-listings-sync` return `503 provider_not_configured` when `RUNSIGNUP_API_KEY` is unset; the UI card is disabled with an explainer. parkrun + manual-paste paths work without it. This is the "build behind a default-off flag, don't stub" rule.
- **No paywall gate** by default (race discovery + result import is a free, retention-positive feature) — but if it should be Pro, gate via the existing paywall registry (`paywall.md`), not a stub.
- **Privacy**: imported race results carry owner-only metadata. The four original keys (`race_name`/`bib`/`chip_time`/`overall_place`) are already stripped from `public_runs` (`20260714_001`); the three new keys this plan writes (`gun_time`/`age_group_place`/`age_group`) must be **added to the `public_runs` strip in this plan's migration** (they're not stripped today). The auto-match seam writes only on user confirmation (inform tier). Verify the new `runs.race_listing_id` projection in `public_runs`.
- **Scraping hygiene**: reuse parkrun's politeness pattern (User-Agent env, per-user rate limit, body caps, fail-loud on non-2xx) for any URL-fetch path; per-site scrapers stay deferred to avoid brittle/abusive crawling.
- **No compliance sign-off gate** (no money, no new PII sub-processor beyond the public results data the runner already published on the timing site) — unlike the fundraising feature.

## Commit plan (ordered, path-scoped)

1. `git commit -- apps/backend/supabase/migrations/20270203_001_race_calendar.sql apps/backend/supabase/tests/race_listings_rls_test.sql apps/backend/supabase/tests/race_listing_link_test.sql` — schema + RPC + RLS + pgtap.
2. `git commit -- apps/web/src/lib/database.types.ts packages/core_models/lib/src/generated/db_rows.dart apps/web/src/lib/types.ts apps/web/scripts/check_constraint_unions.mjs` — both regenerated type files + unions + PAIRS.
3. `git commit -- apps/web/src/lib/integrations/race_match.ts apps/web/src/lib/integrations/race_match.test.ts apps/mobile_android/lib/race_match.dart apps/mobile_android/test/race_match_test.dart apps/mobile_ios/lib/race_match.dart apps/mobile_ios/test/race_match_test.dart` — parity pair + tests.
4. `git commit -- apps/backend/supabase/functions/race-results-import/ apps/backend/supabase/functions/race-listings-sync/` — import EF (RunSignUp + paste) + sync stub + Deno tests.
5. `git commit -- apps/web/src/lib/core/data.ts` — data.ts helpers.
6. `git commit -- apps/web/src/routes/races/ apps/web/src/lib/components/RaceCalendarCard.svelte apps/web/src/lib/components/RaceListingEditor.svelte apps/web/tests-e2e/races/` — calendar page + components + Playwright.
7. `git commit -- apps/web/src/routes/settings/integrations/+page.svelte apps/web/src/routes/runs/[id]/+page.svelte` + Playwright — RunSignUp card + run-detail result/find-my-result.
8. `git commit -- apps/mobile_android/lib/race_service.dart apps/mobile_android/lib/screens/races_screen.dart apps/mobile_android/lib/screens/run_detail_screen.dart apps/mobile_android/lib/screens/settings_integrations_screen.dart apps/mobile_android/test/... apps/mobile_ios/...` — mobile calendar + auto-match prompt + RunSignUp tile (both twins).
9. `git commit -- apps/web/src/lib/i18n/locales/*.ts apps/mobile_android/lib/l10n/*.arb apps/mobile_ios/lib/l10n/*.arb` — i18n.
10. `git commit -- docs/... CLAUDE.md` — docs sweep.

## Open questions / decisions owed

1. **Calendar seeding** — v1 relies on user-submitted + manual + on-demand RunSignUp import, or do we commit to an auto-sync of RunSignUp's upcoming-races feed (more provider quota, ongoing freshness)? Recommend user-submitted + on-demand first; auto-sync as a follow-up.
2. **Listing trust / moderation** — crowd-submitted listings need a report/verify path (reuse `20270115_001` report-posts infra?) to avoid spam/duplicate listings. How heavy a moderation layer for v1?
3. **Auto-match radius + same-day rule** — is ~5 km from the start point + same date + distance-band the right confidence gate, or do we need bib-aware matching (the user enters their bib once)? Bib entry materially improves RunSignUp matching.
4. **Per-site scrapers** — which timing platform (ChronoTrack? UltraSignup for the ultra persona?) is worth a real scraper next, given the fragility cost?
5. **Mobile placement** — the bottom nav can't grow (hard 4 tabs + centre Log FAB = 5 slots), so Races must live as a sub-route. Confirm the placement: a Social sub-tab (alongside Clubs / Discover) vs the Fitness-hub Runs area.
6. **Migration number collision** with the fundraising plan (both want `20270203_001`) — assign sequentially at landing.

## Sequencing for the implementer

1. Write the race-calendar migration (placeholder name `2027XXXX_001_race_calendar.sql` — assign the next free sequential number at landing; the `20270203_001` used in the commit-plan example is illustrative and collides with the fundraising plan): `race_listings` table + CHECKs + GiST + trgm indexes + RLS + `search_race_listings` RPC + `runs.race_listing_id`, plus the `public_runs` strip additions for the three new race metadata keys. Apply via `safe-migration`.
2. Add `RaceProvider` to `types.ts`; append to `check_constraint_unions.mjs` PAIRS. Run both codegen commands; commit regenerated files. Write + pass pgtap.
3. Build the `race_match` parity pair (web + both Dart twins) with matched tests.
4. Build `race-results-import` (mirror `parkrun-import`; RunSignUp + paste; fail-closed on missing key) + the `race-listings-sync` stub; Deno tests.
5. Add `data.ts` helpers (search, submit, import, find-match-candidates).
6. Build `/races` discovery page (reuse `SocialDiscover` patterns) + cards/editor; Playwright.
7. Wire the RunSignUp card in Settings → Integrations; wire run-detail official-result render + "Find my result".
8. Implement the auto-match-on-record seam: post-save layered-resilience-wrapped candidate check → non-blocking inform-tier prompt → confirm → enrich the run row (web run-detail first, then mobile).
9. Mirror calendar + auto-match prompt + RunSignUp tile to mobile (both twins, byte-identical); widget tests with the `tester.runAsync` gotchas.
10. Add all i18n keys (six web locales + seven ARBs).
11. Docs sweep (roadmap #10, parity, integrations, metadata.md writer flip, api_database, decisions ADR, CLAUDE.md parity entry, e2e dev accounts).
12. Run `/check` before each commit; keep RunSignUp fail-closed (no key in CI/dev).
