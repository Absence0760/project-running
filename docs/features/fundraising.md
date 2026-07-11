# Fundraising / donation pages on a run or event — implementation plan

> **Status:** **Built web + mobile-read (gated)** — landed 2026-06-19 (migration `20270213_001_fundraisers.sql`, ADR §167). The full code path ships behind a fail-closed prod gate (live Stripe keys unset + owner/CISO/counsel sign-off — see § Gating). **Client UI gate (2026-07-11, §223):** the whole donation surface is additionally hidden behind the fail-closed `PUBLIC_FUNDRAISING_ENABLED` flag (`src/lib/social/fundraising_flag.ts`) — unset in prod, so `FundraiserSection` renders nothing on run/event detail and the public `/fundraisers/[id]` page falls to its not-found state, and no user reaches a donate button that would 503 on the unconfigured Edge Function. Local dev + e2e set it truthy in `.env.development`. Flip it on the same day Stripe + the sign-off land. **Web:** public `/fundraisers/[id]` page (thermometer + donation feed + amount-picker → Stripe-hosted destination-charge Checkout), create/edit/close via `FundraiserEditor`, attach affordance on run-detail + event-detail. **Mobile (Android + iOS twin):** read + web-handoff card on run-detail + event-detail (donate opens the web page). The sections below were the implementation plan; they now describe shipped behaviour except where a step is explicitly deferred (e.g. mobile authoring, direct-to-charity payout). Tracked in [roadmap.md § Planned features](../product/roadmap.md#planned-features--specced-2026-06-15).

## Goal & user value

Let a runner or club organiser attach a **charity fundraising page** to a run or a club event — a public page with a goal **thermometer** (raised vs goal), a **donation feed** (donor name + amount + optional message), and a **share** affordance. Anyone (including a logged-out stranger) can donate via Stripe-hosted Checkout; the money settles into the **fundraiser owner's** connected Stripe account via the **same destination-charge Connect rail already shipped for paid events** (`docs/features/club_events.md` slice P1 / `decisions.md §139`). This closes the gap flagged by the boston-charity-fundraiser persona ("I want to raise money for a charity tied to my marathon and show my supporters a live total"). Like paid events, the whole live-money path ships behind a **fail-closed prod gate** (Stripe live keys unset + owner+CISO+counsel sign-off), but the code path is fully written and test-mode-verified.

## What already exists to build on (verified)

The Stripe Connect destination-charge marketplace rail is **already built and shipped on web** (test-mode-verified, live-charge-unverified). Reuse it wholesale rather than building a parallel payment stack:

- **Migration `apps/backend/supabase/migrations/20261229_001_paid_events.sql`** — the model to copy: `instructor_payout_accounts` (Connect account + capability flags, `stripe_connect_account_id` revoked from client roles), the `host_can_take_payment(uuid)` SECURITY DEFINER boolean oracle, the `event_orders` ledger with **service-role-only status writes** (the `lock_event_order_status` trigger), and the `is_event_visible(uuid)` helper.
- **`instructor_payout_accounts`** table + `host_can_take_payment(p_user_id uuid)` — **reuse directly** as the donation-recipient payout account. A fundraiser owner uses the *same* user-level payout account they'd use to host paid events. No new payout table.
- **Edge Functions** (all under `apps/backend/supabase/functions/`):
  - `events-connect-onboard/` — Connect Express onboarding + `validateReturnUrl` in its `lib.ts`. **Reuse as-is** (it onboards the user, not an event).
  - `events-checkout/` + its `lib.ts` — destination-charge Checkout Session builder. **`buildCheckoutSessionParams`, `computeApplicationFeeCents`, `checkoutIdempotencyKey`, `reservationExpiry` are directly reusable**; the donation checkout is a thinner variant (no capacity, no sales window — a donation has no seat).
  - `stripe-events-webhook/` + its `lib.ts` — the **one idempotent, HMAC-verified, service-role-only** order-status writer (`verifyStripeSignature`, `orderStatusTransition`, `parseStripeEventEnvelope`, insert-first dedupe via `webhook_events`). The donation webhook extends this same function (one more `checkout.session.completed` branch keyed on order kind) rather than adding a second webhook endpoint + secret.
- **Pure helper `apps/web/src/lib/social/paid_registration.ts`** (`applicationFeeCents`, `salesCloseAt`, `registrationOpen`) — `applicationFeeCents` is reused directly for donation platform fee.
- **`apps/web/src/lib/core/data.ts`** (7937 lines) — existing payout helpers to mirror: `fetchPayoutAccount`, `startConnectOnboarding` (lines ~2284, ~2309), `startEventCheckout`, `fetchMyOrder` (~2376, ~2392).
- **Types `apps/web/src/lib/types.ts`** — `OrderStatus`, `RefundPolicy`, `EventModality` unions + `EventOrder`, `InstructorPayoutAccount`, `EventPricing` overlays already exist (lines 175-282). `host_user_id` already on `events`.
- **`webhook_events`** dedupe table (provider + event id) — reused for donation webhook idempotency.
- **Discover/social surfaces** — `apps/web/src/routes/social/+page.svelte` + `apps/web/src/lib/components/SocialDiscover.svelte` show how a public, anon-readable surface is built.
- **Run-detail web** `apps/web/src/routes/runs/[id]/+page.svelte`; **event-detail web** `apps/web/src/routes/clubs/[slug]/events/[id]/+page.svelte`; mobile `apps/mobile_android/lib/screens/run_detail_screen.dart` + `apps/mobile_android/lib/screens/event_detail_screen.dart` — the surfaces a fundraiser attaches to.

## Data model / migrations

One new migration. **Number is a placeholder — assign sequentially at landing** (e.g. `2027XXXX_001_fundraisers.sql`; latest on `main` at spec time is `20270202_001`, and the race-calendar plan also wants the next slot, so coordinate so the two don't collide).

Two new tables + two narrow unions. A fundraiser is **polymorphic over (run | event)** via a nullable-FK-pair + CHECK (exactly one set), mirroring how `event_results.run_id` / `event_orders.event_id` coexist.

```sql
-- ── fundraisers ────────────────────────────────────────────────────────────
create table fundraisers (
  id              uuid primary key default gen_random_uuid(),
  owner_user_id   uuid not null references auth.users on delete cascade,
  -- exactly one anchor (a run OR a club event); a CHECK enforces it.
  run_id          uuid references runs on delete cascade,
  event_id        uuid references events on delete cascade,
  charity_name    text not null,
  charity_url     text,                 -- http/https CHECK (clubs.website_url pattern, 20270131_001)
  title           text not null,
  story           text,                 -- the fundraiser's pitch (sanitised on render)
  goal_cents      integer not null,
  currency        text not null default 'usd',
  platform_fee_bps integer not null default 0,   -- platform config, not owner-set
  status          text not null default 'open',  -- FundraiserStatus
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

alter table fundraisers add constraint fundraisers_anchor_check
  check ((run_id is not null) <> (event_id is not null));   -- exactly one
alter table fundraisers add constraint fundraisers_status_check
  check (status in ('open', 'closed'));
alter table fundraisers add constraint fundraisers_goal_positive_check
  check (goal_cents > 0);
alter table fundraisers add constraint fundraisers_fee_bps_range_check
  check (platform_fee_bps >= 0 and platform_fee_bps <= 10000);
alter table fundraisers add constraint fundraisers_charity_url_scheme_check
  check (charity_url is null or charity_url ~* '^https?://');

-- one fundraiser per anchor (partial unique on each FK)
create unique index fundraisers_run_uniq on fundraisers (run_id) where run_id is not null;
create unique index fundraisers_event_uniq on fundraisers (event_id) where event_id is not null;

-- ── donations (the ledger — service-role-only status, like event_orders) ─────
create table donations (
  id              uuid primary key default gen_random_uuid(),
  fundraiser_id   uuid not null references fundraisers on delete cascade,
  donor_user_id   uuid references auth.users on delete set null,  -- NULL = anon donor
  owner_user_id   uuid not null references auth.users on delete cascade, -- payout recipient
  display_name    text,                 -- "Jane D." or "Anonymous"; donor-supplied, capped
  message         text,                 -- optional supporter note, capped + sanitised
  stripe_checkout_session_id text,
  stripe_payment_intent_id   text,
  amount_cents    integer not null,
  currency        text not null default 'usd',
  platform_fee_cents integer not null default 0,
  status          text not null default 'pending',  -- DonationStatus
  is_anonymous    boolean not null default false,
  created_at      timestamptz not null default now(),
  paid_at         timestamptz,
  refunded_at     timestamptz
);

alter table donations add constraint donations_status_check
  check (status in ('pending', 'paid', 'refunded', 'failed', 'canceled'));
alter table donations add constraint donations_amount_positive_check
  check (amount_cents > 0 and platform_fee_cents >= 0);

create unique index donations_checkout_session_idx
  on donations (stripe_checkout_session_id) where stripe_checkout_session_id is not null;
create index donations_fundraiser_paid_idx
  on donations (fundraiser_id, paid_at desc) where status = 'paid';
```

**RLS shape (copy the `event_orders` / `event_pricing` patterns from `20261229_001`):**

- `fundraisers` SELECT: **public** when the anchored run/event is itself publicly visible (`is_event_visible(event_id)` for the event case; for the run case, reuse the run-visibility predicate — anon may read a fundraiser whose run `is_public = true`). The fundraiser page is a share target, so a fundraiser on a public anchor is anon-readable. Fail-closed: a fundraiser on a private run is owner-only.
- `fundraisers` INSERT/UPDATE/DELETE: `owner_user_id = auth.uid()` **and** the caller owns the anchor (`exists run/event they own/organise`) **and** (INSERT/price-set) `host_can_take_payment(owner_user_id)` is true (trigger-enforced, copy `enforce_pricing_requires_charges`). You cannot open a money-taking fundraiser without a charges-enabled account.
- `donations` SELECT: the **paid** rows of a publicly-visible fundraiser are readable by anyone (the donation feed is public), **but only the public-safe columns** — `display_name`, `message`, `amount_cents`, `currency`, `paid_at`. Donor identity (`donor_user_id`), Stripe ids, and `owner_user_id` are **revoked from client roles** (the `stripe_connect_account_id` column-lockdown precedent). Expose the feed via a `security definer` RPC `fundraiser_feed(p_fundraiser_id)` returning only the public-safe projection of paid rows (the `get_event_meet_point` / `host_can_take_payment` pattern), and a `fundraiser_totals(p_fundraiser_id)` RPC returning `{ raised_cents, donor_count, goal_cents }` for the thermometer (a `sum`, never per-row).
- `donations` INSERT/UPDATE/DELETE: **no client policy** — service-role-only, written exclusively by the donation webhook. Copy `lock_event_order_status` verbatim as `lock_donation_status` (reject any non-service-role status write; idempotent CAS pending→paid).

**Two new narrow unions** (TS union + CHECK in lockstep; append both to `apps/web/scripts/check_constraint_unions.mjs` `PAIRS`):

```
FundraiserStatus = 'open' | 'closed'
DonationStatus   = 'pending' | 'paid' | 'refunded' | 'failed' | 'canceled'
```

**Two codegen commands (mandatory, both outputs committed — `docs/architecture/schema_codegen.md`):**

```
cd apps/backend && npm run gen:types        # → apps/web/src/lib/database.types.ts
dart run scripts/gen_dart_models.dart       # → packages/core_models/lib/src/generated/db_rows.dart
```

(The Dart generator understands `create table` + the column lists here; it ignores the RLS/trigger/RPC bodies, which is correct — no hand-editing `db_rows.dart`.)

No new `runs.metadata` keys (relational) → no `docs/backend/metadata.md` churn.

## Web implementation (canonical)

Web-first (`decisions.md §24`). All paths under `apps/web/src/`.

**Edge Functions (new, under `apps/backend/supabase/functions/`):**
- `donations-checkout/index.ts` + `donations-checkout/lib.ts` — mirror `events-checkout` but simpler (no capacity, no sales window). Validate: fundraiser visible + `status = 'open'`; owner `host_can_take_payment`; amount within a sane min/max (e.g. 100–10_000_00 cents); donor may be **anon** (no JWT required — a donation has no seat, unlike a paid registration). Insert a `pending` `donations` row (service role), build the destination-charge session via the reused `buildCheckoutSessionParams` (destination = owner's `stripe_connect_account_id`, `application_fee_amount` from `computeApplicationFeeCents`), `mode: 'payment'`, metadata `{ kind: 'donation', donation_id }`. Idempotency key = `donations-checkout:{donation_id}` (the row id is generated server-side before the Stripe call). SAQ A — no card form.
- **Extend** `stripe-events-webhook/index.ts` + `lib.ts` — add a branch keyed on `session.metadata.kind === 'donation'`: CAS `pending → paid` on the `donations` row, set `paid_at`, `stripe_payment_intent_id`. `charge.refunded` → `refunded`. Reuse the existing insert-first `webhook_events` dedupe + `verifyStripeSignature`. **One webhook, one secret** — do not add a second endpoint.

**`data.ts` helpers (append to `apps/web/src/lib/core/data.ts`):**
- `fetchFundraiserForRun(runId)` / `fetchFundraiserForEvent(eventId)` → `Fundraiser | null`
- `fetchFundraiserById(id)` → public page load
- `createFundraiser(input)` / `updateFundraiser(id, patch)` / `closeFundraiser(id)`
- `fetchFundraiserTotals(id)` → `{ raisedCents, donorCount, goalCents }` (calls `fundraiser_totals` RPC)
- `fetchFundraiserFeed(id, limit)` → public donation feed (calls `fundraiser_feed` RPC)
- `startDonationCheckout(fundraiserId, amountCents, { displayName, message, isAnonymous })` → `{ url }` (invokes `donations-checkout`)
- Reuse existing `fetchPayoutAccount` / `startConnectOnboarding`.

**types.ts overlays (`apps/web/src/lib/types.ts`):**
- `FundraiserStatus`, `DonationStatus` unions
- `Fundraiser = Omit<FundraiserRow, 'status'> & { status: FundraiserStatus }`
- `Donation = Omit<DonationRow, 'status'> & { status: DonationStatus }`
- `FundraiserFeedEntry` / `FundraiserTotals` projection interfaces (RPC row shapes)

**Routes / components (new):**
- `apps/web/src/routes/fundraisers/[id]/+page.svelte` + `+page.ts` — the **public fundraiser page**: hero (title, charity, story rendered with the existing markdown/HTML-sanitise path used elsewhere — never raw `{@html}`), **thermometer** (`GoalThermometer.svelte`, raised/goal bar with a11y `role="progressbar"` + aria-valuenow/max), **donation feed** (`DonationFeed.svelte`, name + amount + message), **"Donate" CTA** → amount picker → `startDonationCheckout` → Stripe → `?donated=1` success poll (the `<5s` poll pattern `fetchMyOrder` uses). Owner sees a Close + Edit control.
- `apps/web/src/lib/components/FundraiserCard.svelte` — compact thermometer + Donate button, embedded on run-detail + event-detail.
- `apps/web/src/lib/components/FundraiserEditor.svelte` — create/edit (charity name, url, title, story, goal). A "Set up payouts first" gate that links to `/settings/payouts` and is **disabled until `host_can_take_payment`** (reuse the EventEditor Charge-toggle gate).
- **Run-detail** `apps/web/src/routes/runs/[id]/+page.svelte` — owner gets "Raise money for a charity" → FundraiserEditor; if a fundraiser exists, render `FundraiserCard` for all viewers.
- **Event-detail** `apps/web/src/routes/clubs/[slug]/events/[id]/+page.svelte` — same affordance, organiser-gated; renders `FundraiserCard`.
- **Share**: the public `/fundraisers/[id]` page is the share URL; add it to the existing share/copy-link affordance pattern (no new infra).

## Mobile implementation (Android + iOS twin)

Per `decisions.md §39`, every Dart change lands **byte-identical** in `apps/mobile_android/lib/` and `apps/mobile_ios/lib/` (+ tests). Mobile is **read + share only in this slice** — donation checkout routes to the web page in a Custom Tab / in-app browser, mirroring how paid-event registration is web-checkout-only (P3 in `club_events.md`). **No in-app purchase flow, no `BYPASS_PAYWALL`-style override** (the in-person/real-world-service IAP exemption is for paid events; a charitable donation through a third party is also outside IAP, but to contain blast radius we keep mobile read-only here).

- **Service** `apps/mobile_android/lib/social_service.dart` (+ iOS twin) — add `fetchFundraiserForRun/Event`, `fetchFundraiserById`, `fetchFundraiserTotals`, `fetchFundraiserFeed`. (No `createFundraiser` on mobile in this slice — authoring is web-canonical; mobile can come in a follow-up.)
- **Screen** `apps/mobile_android/lib/screens/run_detail_screen.dart` + `event_detail_screen.dart` (+ iOS twins) — render a read-only fundraiser card (Dart `_FundraiserCard` widget: thermometer + donor feed + a "Donate on web" button that `url_launcher`-opens `/fundraisers/[id]` in a Custom Tab, the existing handoff pattern).
- **Nav placement**: none. Fundraisers are sub-surfaces of existing run-detail / event-detail screens — **no new bottom-nav destination** (the mobile shell has a hard ceiling of 4 nav tabs + the centre Log FAB = 5 slots; see `apps/mobile_android/CLAUDE.md` and `decisions.md §63` — clubs is a sub-tab of Social, not its own slot, so it does not count against the ceiling).

## TS↔Dart parity helpers

- **`fundraiser_progress`** — new parity pair: web `apps/web/src/lib/social/fundraiser_progress.ts` ↔ mobile `apps/mobile_android/lib/fundraiser_progress.dart` (+ iOS twin). Pure logic computing thermometer state from `(raisedCents, goalCents)`: `pct` (clamped 0–100, but allow display of "118% — over goal!"), `remainingCents`, and a `ThermometerState` (`'starting' | 'progressing' | 'met' | 'exceeded'`) for the bar styling/label. Deterministic, no I/O. **Matching test counts** both sides (e.g. 10 each), and add the pair to the lockstep list in the root `CLAUDE.md`.
- `applicationFeeCents` (fee math) stays in `paid_registration.ts` (web-only for now) — reused by `donations-checkout`, no Dart twin needed (mobile doesn't checkout).

## Tests (in the same commit as each piece)

- **Playwright (web, `apps/web/tests-e2e/`):**
  - `fundraising/fundraiser-create.spec.ts` — owner creates a fundraiser on a run; gated until payouts onboarded; thermometer renders at 0.
  - `fundraising/fundraiser-page-public.spec.ts` — anon can view a public fundraiser page (thermometer, feed, Donate CTA); a fundraiser on a private run is not reachable by a non-owner.
  - `fundraising/donation-checkout.spec.ts` — **Stripe test mode** end-to-end: donate with `4242…`, assert the donation appears in the feed + thermometer advances (stubs per `docs/testing/local_testing_stubs.md § Stripe Connect`).
- **pgtap (`apps/backend/supabase/tests/`):**
  - `fundraisers_rls_test.sql` — anon reads a public-anchor fundraiser; cannot read a private-anchor one; non-owner cannot insert/close; donor identity columns revoked.
  - `donations_status_lock_test.sql` — a user-JWT cannot write `donations.status` (service-role-only); feed RPC returns only public-safe columns.
  - `fundraiser_pricing_requires_charges_test.sql` — opening a fundraiser without a charges-enabled account is rejected.
- **Deno (next to the functions):**
  - `donations-checkout/lib.test.ts` — fee math, amount-bounds validation, idempotency key (mocked Stripe).
  - `stripe-events-webhook/lib.test.ts` — extend with a donation-branch idempotency test (replay = one paid donation, no double-count).
- **node:test (web pure):** `apps/web/src/lib/social/fundraiser_progress.test.ts` — thermometer math (≥10 cases).
- **Flutter (`apps/mobile_android/test/` + iOS twin):** `fundraiser_progress_test.dart` (parity-matched, ≥10), and a `run_detail_screen_test.dart` / `event_detail_screen_test.dart` widget assertion that the read-only card renders.
- **Parity:** the `fundraiser_progress` pair test counts must match across TS/Dart.

## i18n keys to add (all six web locales + all mobile ARBs)

Web (`apps/web/src/lib/i18n/locales/{en,de,es,fr,ja,pt-BR}.ts`) and mobile (`apps/mobile_android/lib/l10n/app_{en,de,es,fr,ja,pt,pt_BR}.arb`). Representative keys:

- `fundraiser.title`, `fundraiser.charityName`, `fundraiser.charityUrl`, `fundraiser.goal`, `fundraiser.story`
- `fundraiser.raisedOfGoal` (`"{raised} of {goal} raised"`), `fundraiser.donorCount` (`"{count} supporters"`), `fundraiser.overGoal`
- `fundraiser.donate`, `fundraiser.donateAmount`, `fundraiser.donateAnonymously`, `fundraiser.donateMessage`, `fundraiser.thanksTitle`
- `fundraiser.createCta` (`"Raise money for a charity"`), `fundraiser.payoutsRequired`, `fundraiser.setUpPayouts`, `fundraiser.close`, `fundraiser.closed`
- `fundraiser.feedEmpty`, `fundraiser.share`, `fundraiser.anonymous`
- `fundraiser.donateOnWeb` (mobile handoff label)

## Docs to update (same turn the code lands)

- `docs/product/roadmap.md` — add a "Charity fundraising pages" row under Clubs/social, ticked web-shipped (gated).
- `docs/product/parity.md` — new row: web ✓, mobile read/share ✓ + donate ✗ (web handoff), watch ✗.
- `docs/features/club_events.md` — cross-reference: fundraising reuses the slice-P Connect rail; note the shared webhook + payout account.
- `docs/backend/api_database.md` — the two new tables, RLS, the revoked donor-identity columns, the two feed/totals RPCs.
- `docs/features/integrations.md` — Stripe Connect now also powers donations (alongside paid events).
- `docs/architecture/decisions.md` — one new ADR: *"Charity fundraising pages reuse the paid-events Stripe Connect destination-charge rail (one shared webhook + the user-level payout account); a fundraiser is polymorphic over (run | event); donation status is service-role-only; live charges are gated on the same owner+CISO+counsel sign-off + live Stripe keys as paid events."*
- Root `CLAUDE.md` — add `fundraiser_progress` to the parity-pair lockstep list.
- GDPR posture / sub-processor docs — `donations` is a new personal-data table (covered by the existing Stripe sub-processor entry; add the table to Art 20 export + Art 17 deletion, with the same financial-retention caveat as `event_orders`).

## Gating / compliance

**Fail-closed, identical posture to paid events (`club_events.md` Compliance + the CLAUDE.md "compliance sign-offs gate prod, not code" rule):**

- **Build the whole code path now**, behind the gate. The gate is config, not missing code.
- `donations-checkout` returns `503 stripe_not_configured` when `STRIPE_SECRET_KEY` is unset, and requires `STRIPE_EVENTS_ALLOWED_REDIRECTS` (reuse the events allowlist). In P1 the key must be `sk_test_`. The webhook fails closed (`503`) when `STRIPE_EVENTS_WEBHOOK_SECRET` is unset.
- **Live charges require operator `sk_live_` / `whsec_` keys** (default unset) **AND** owner + CISO + counsel sign-off (new money flow, charity-fundraising regulatory surface — counsel must confirm whether platform-facilitated charitable solicitation triggers state charitable-registration rules; this is a **pre-deploy checklist item**, not a reason to leave code unwritten).
- **PCI**: Stripe-hosted Checkout only → SAQ A. **No custom card form** (hard constraint).
- **Funds-flow integrity**: webhook is the sole, idempotent, service-role-only writer of `donations.status`.
- **Privacy**: donor identity + Stripe ids revoked from client roles; the public feed shows only donor-supplied `display_name` + message + amount. An anon donor's payment-intent email never surfaces.
- Mobile is read/share-only → no IAP exposure in this slice.

## Commit plan (ordered, path-scoped)

1. `git commit -- apps/backend/supabase/migrations/20270203_001_fundraisers.sql apps/backend/supabase/tests/fundraisers_rls_test.sql apps/backend/supabase/tests/donations_status_lock_test.sql apps/backend/supabase/tests/fundraiser_pricing_requires_charges_test.sql` — schema + RLS + pgtap.
2. `git commit -- apps/web/src/lib/database.types.ts packages/core_models/lib/src/generated/db_rows.dart apps/web/src/lib/types.ts apps/web/scripts/check_constraint_unions.mjs` — both regenerated type files + unions + PAIRS.
3. `git commit -- apps/web/src/lib/social/fundraiser_progress.ts apps/web/src/lib/social/fundraiser_progress.test.ts apps/mobile_android/lib/fundraiser_progress.dart apps/mobile_android/test/fundraiser_progress_test.dart apps/mobile_ios/lib/fundraiser_progress.dart apps/mobile_ios/test/fundraiser_progress_test.dart` — parity pair + tests (one commit, both twins).
4. `git commit -- apps/backend/supabase/functions/donations-checkout/ apps/backend/supabase/functions/stripe-events-webhook/` — checkout EF + webhook donation branch + Deno tests.
5. `git commit -- apps/web/src/lib/core/data.ts` — data.ts helpers.
6. `git commit -- apps/web/src/routes/fundraisers/ apps/web/src/lib/components/FundraiserCard.svelte apps/web/src/lib/components/FundraiserEditor.svelte apps/web/src/lib/components/GoalThermometer.svelte apps/web/src/lib/components/DonationFeed.svelte apps/web/tests-e2e/fundraising/` — public page + components + Playwright.
7. `git commit -- apps/web/src/routes/runs/[id]/+page.svelte apps/web/src/routes/clubs/[slug]/events/[id]/+page.svelte` + relevant Playwright — attach affordance on run/event detail.
8. `git commit -- apps/mobile_android/lib/social_service.dart apps/mobile_android/lib/screens/run_detail_screen.dart apps/mobile_android/lib/screens/event_detail_screen.dart apps/mobile_android/test/... apps/mobile_ios/...` — mobile read/share card + tests (both twins).
9. `git commit -- apps/web/src/lib/i18n/locales/*.ts apps/mobile_android/lib/l10n/*.arb apps/mobile_ios/lib/l10n/*.arb` — i18n (all locales + ARBs).
10. `git commit -- docs/... CLAUDE.md` — docs sweep.

(Tests ship in the same commit as the piece they cover — the commits above bundle each piece's tests with its code.)

## Open questions / decisions owed

1. **Platform fee on donations** — almost certainly **0 bps** (you don't skim a charity donation), but confirm. If 0, the platform-fee plumbing still exists but defaults to nothing.
2. **Charity verification** — do we verify the named charity is real, or is it free-text owner-attested (with a report path)? Free-text + report is the low-friction default; verification is a heavy follow-up. Counsel input.
3. **Where does the money actually go?** In this rail funds settle to the *fundraiser owner's* Connect account, not the charity's — i.e. the runner collects and is trusted to forward. The honest alternative (Stripe Climate-style direct-to-charity / a charity-verified Connect account) is a larger build. **Owner decision** — this changes the trust + regulatory story materially.
4. **Charitable-solicitation registration** — does platform-facilitated fundraising trigger US state charitable-registration / disclosure obligations? **Counsel** (pre-deploy gate).
5. **Should opening a fundraiser be a Pro-only perk?** Ties into `paywall.md` (same open question paid events has).
6. **Refunds** — manual via Stripe dashboard in v1 (matches paid-events P1), or do we need a buyer-facing refund path on day one? Default: manual.

## Sequencing for the implementer

1. Write the fundraisers migration (placeholder name `2027XXXX_001_fundraisers.sql` — assign the next free sequential number at landing, the `20270203_001` used in the commit-plan example is illustrative): tables, CHECKs, partial unique indexes, RLS, the `lock_donation_status` trigger, the `enforce_fundraiser_requires_charges` trigger, the `fundraiser_feed` + `fundraiser_totals` SECURITY DEFINER RPCs. Apply locally via the `safe-migration` flow.
2. Add `FundraiserStatus` / `DonationStatus` to `types.ts`; append both to `check_constraint_unions.mjs` PAIRS. Run **both** codegen commands; commit the regenerated files. Write the pgtap tests; verify they pass.
3. Build the `fundraiser_progress` parity pair (web + both Dart twins) with matched tests.
4. Build `donations-checkout` (reusing `events-checkout/lib.ts` helpers) + extend `stripe-events-webhook` with the donation branch; add Deno tests (mocked Stripe).
5. Add the `data.ts` helpers.
6. Build the public `/fundraisers/[id]` page + `GoalThermometer` / `DonationFeed` / `FundraiserCard` / `FundraiserEditor` components; wire the success-poll. Add Playwright (incl. test-mode Stripe donate).
7. Add the attach affordance to run-detail + event-detail (web).
8. Mirror the read/share card to mobile (`social_service.dart` + the two detail screens), byte-identical across both twins; add widget tests.
9. Add all i18n keys to six web locales + seven ARBs.
10. Docs sweep (roadmap, parity, api_database, club_events cross-ref, integrations, a decisions.md ADR, the CLAUDE.md parity-list entry, GDPR docs).
11. Run `/check` against the working diff before each commit; keep the live charge path fail-closed (no live keys).
