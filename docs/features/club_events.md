# Club events — typed sessions with optional paid registration

> **Goal / north star.** The product's north star is a **personal multi-modal training app whose differentiator is cross-modal intelligence** — a Coach that reasons across one athlete's runs, lifts, and nutrition (see [multi_modal.md](multi_modal.md)). That is the wedge no incumbent owns. This plan serves that goal by making clubs a **retention and community layer in service of the individual athlete — not a second business.** Typed events let a club be about *fitness* rather than only running (a runner who also does a weekly pilates class stays in one app), and paid registration lets the instructors who anchor those communities sustain them. We are deliberately **not** pivoting into a standalone fitness marketplace (ClassPass / Mindbody territory); the marketplace mechanics exist only to keep athletes and the people who train them inside the one app where the cross-modal intelligence lives. Every gate below answers to that — if a slice doesn't deepen engagement with the core app, it doesn't ship.

A **club is a generic container.** A club hosts events of different *types* — a group run, a yoga class, a pilates class, a social meetup — and **any** event, of any type, can require **paid** registration where the money goes to the **instructor who hosts it**, not the club. This spec has two coupled halves:

- **Slice E — event-type generalization.** Today the event model is running-specific: every event editor shows route / distance / target pace / race-mode / results-leaderboard fields. A yoga instructor scheduling a class is forced through running concepts that make no sense. E makes events *typed*, with fields that **self-hide** to the chosen type — the same progressive-disclosure rule the multi-modal redesign uses ([multi_modal.md](multi_modal.md)).
- **Slice P — paid registration.** A marketplace layer (Stripe Connect) so a host can charge for any event type; the charge settles into the *host's* account, the platform takes a fee, and a completed payment is what grants the RSVP.

> **Status:** Slice E **shipped** (web create + web/mobile read) and Slice P1's rail **built on web** (gated — see below). The schema foundation (migration `20261227_001`: `events.category`/`discipline`/`host_user_id`/`gym_template` + the athletic-only data-layer guards + pgtap) and the pure `isAthleticCategory` predicate (web + mobile twin) have landed; the **mobile** category-gated read-only event-detail surface has also landed (`event_detail_screen.dart` on both twins — athletic affordances gated behind `isAthleticEventCategory(category)`, a `class` shows its free-text discipline via `EventDisciplineLabel`); the **web** type-first editor (`EventEditor.svelte` — category segmented picker as the first control, discipline free-text for a `class`, athletic fields self-hide + clear on category change, `createEvent` persists `category` + `discipline`) and the **web** category-gated event-detail surface (`/clubs/[slug]/events/[id]` — distance/pace/route, race panel + banner, and the whole results/leaderboard/Submit-my-time/certificate/claims section gate on `isAthleticCategory(event.category)`; a non-athletic event shows its discipline in the hero + an attendance-only note) have now landed. The earlier `EVENT_SELECT_COLS` gap is closed: it now selects `category` + `discipline`, and migration `20261228_001` grants cross-user SELECT on those two columns (the column-locked `events` table left them deny-by-default; `host_user_id`/`gym_template` stay revoked, reserved for slice P). The **mobile** create-event surface has now reached write parity for the typed model: `widgets/event_form_sheet.dart` (the `EventEditor` Dart twin) exposes the category segmented picker + `class` discipline free-text, and `SocialService.createEvent` persists `category` / `discipline` / `gym_template` (the latter built via `gymTemplateFromInputs` for a `class`) — so a typed event can be authored on Android, not just read. Slice **P1 (paid registration) has now shipped on web**: migration `20261229_001` lays the three tables (`instructor_payout_accounts` / `event_pricing` / `event_orders`) + `event_attendees.order_id` + the charges_enabled-gated pricing trigger + the service-role-only `event_orders.status` lock + the revoked `stripe_connect_account_id` column surfaced via `host_can_take_payment()`; the three Edge Functions (`events-connect-onboard`, `events-checkout` destination charge, `stripe-events-webhook` — the one idempotent, service-role-only, HMAC-verified order-status writer, deduped on the Stripe event id via the `webhook_events` table) are built; the web surfaces (`/settings/payouts` Connect onboarding + status, the EventEditor "Charge" toggle disabled until `charges_enabled`, the event-detail "Register · $X" flow with a `?paid=1` success poll) are built; the pure `paid_registration.ts` fee/sales-window/refund helper + `data.ts` methods (`fetchPayoutAccount` / `startConnectOnboarding` / `fetchEventPricing` / `setEventPricing` / `startEventCheckout` / `fetchMyOrder`) are built. **In-person only; web checkout only; refunds in P1 are MANUAL via the Stripe dashboard.** The **live charge path is UNVERIFIED** — no Stripe Connect test keys are configured (the existing Stripe surface is the RevenueCat-aggregated Pro path, not Connect), so real Connect onboarding + destination-charge Checkout + the webhook grant need operator `sk_test_` / `ca_` / `whsec_` keys ([local_testing_stubs.md § Stripe Connect](../testing/local_testing_stubs.md)); the schema rail, RLS (pgtap), pure helpers (node:test), the webhook/checkout pure libs (mocked-Stripe Deno tests), and the non-charge UI (Playwright) are verified. Compliance gate (owner + CISO + counsel sign-off for the new sub-processor under SOC 2 / GovRAMP) still applies before this is exposed in production. Slice **P2's buyer self-cancel + automated refund has now shipped on web** (migration `20270303_001`, decisions §187): the `events-cancel` Edge Function initiates a Stripe refund (refund-eligible `paid` order, `refund_application_fee: true`) or expires the soft reservation (`pending` order), and the `stripe-events-webhook` — still the sole status writer — handles `charge.refunded` to CAS `paid->refunded` + release the seat; the migration adds `event_orders.refund_initiated_at` (a non-status "refund requested" stamp the buyer may write) by widening `lock_event_order_status` from a status-lock to a column-lock; the web event-detail page gains a "Cancel registration" affordance (ConfirmDialog with refundable/no-refund/pending copy, `cancelEventOrder` in `data.ts`, a "Refund in progress" badge during the async gap). **The live refund round-trip is UNVERIFIED** — like P1's charge path it needs operator `sk_test_` / `whsec_` keys; the pure libs (Deno), the column-lock + buyer policy (pgtap `event_order_self_cancel_test.sql`), and the UI states (Playwright `event-self-cancel.spec.ts`) are verified, and the EF 503s fail-closed with keys unset. The remaining P2 work (waitlist notify-to-pay, reconciliation sweep) and P3–P4 (mobile register, virtual paid events, club-level pooled payouts) remain deferred. Supersedes the `followups.md` "Paid event registration (~2-3 wk)" note (and corrects its sizing — E is a prerequisite the note missed, and the marketplace foundation is larger than the registration form). **E shipped first as the gate probe** (do non-running clubs even form?); P1's rail is now built behind it but stays gated on the compliance sign-off + operator Stripe keys before any production exposure. This replaces the earlier `paid_events.md` draft, which treated payments as the whole story and missed that events are running-shaped. **Cross-club discovery has now shipped (web)**: a `/social` **Discover** tab over the `search_public_events` RPC (migration `20270110_001`) lets anyone find public-club events across the typed model — filter by category (run/cycle/class/social), discipline (e.g. "pilates", pg_trgm index), cadence, weekday, free/paid, and **time-of-day** (local, anchored to a new `events.timezone` column captured at create time — migration `20270111_001`), and **proximity** ("near me / near a place" via `p_center_lng/p_center_lat/p_radius_m`, default 50km — migration `20270112_001`) — answering "find a paid pilates class on Sundays at 7pm near me" / "a weekly evening group run", which was previously impossible (events were reachable only inside a club you already knew). Proximity filters by the **club's** public `clubs.location_point` (geocoded by ClubEditor, GiST-indexed), **never** the event's revoked precise `meet_lat/meet_lng` — discovery is club-granularity by design so a class's exact studio/home address is never exposed; the web UI resolves a center via `geocodePlace` (typed place) or `navigator.geolocation` ("Use my location"). `security invoker` + public-club-scoped, so no new exposure; a mobile discovery surface is deferred. See [decisions.md §147](../architecture/decisions.md#147-cross-club-activity-discovery-is-one-security-invoker-rpc-scoped-to-public-clubs-surfaced-as-a-social-discover-tab).
>
> **Reused by charity fundraising ([fundraising.md](fundraising.md), migration `20270213_001`, ADR §167):** the Slice-P1 Connect rail is the foundation for fundraising/donation pages. A fundraiser uses the **same** user-level `instructor_payout_accounts` payout account + `host_can_take_payment()`, the same `events-connect-onboard` onboarding + `events-checkout/lib.ts` helpers, and the **same single `stripe-events-webhook` endpoint + secret** — extended with one `metadata.kind==='donation'` branch (`isDonationSession` → `donationStatusTransition`, the donation analogue of `orderStatusTransition`), not a second webhook. The `donations` ledger copies the `event_orders` discipline (service-role-only CAS status, donor identity / Stripe ids revoked, public feed via a SECURITY DEFINER RPC). Same fail-closed prod gate (live keys unset + owner/CISO/counsel sign-off).

**Contents:** [The two problems](#the-two-problems) · [Product contract](#product-contract) · [Slice E — typed events](#slice-e--typed-events) · [Slice P — paid registration](#slice-p--paid-registration) · [The load-bearing decision: the app-store tax](#the-load-bearing-decision-the-app-store-tax) · [The validation gate](#the-validation-gate-stated-honestly) · [Money movement — to the host, not the club](#money-movement--to-the-host-not-the-club) · [Capacity, waitlist & the payment race](#capacity-waitlist--the-payment-race) · [Refunds & cancellation coupling](#refunds--cancellation-coupling) · [Data model](#data-model) · [Web & mobile UI](#web--mobile-ui) · [Compliance](#compliance-soc-2--govramp--privacy) · [Gotchas & anti-patterns](#gotchas--anti-patterns) · [Failure modes](#failure-modes) · [Testing](#testing) · [File list](#file-list) · [Phasing](#phasing--rollout) · [Open questions](#open-questions) · [Rough sizing](#rough-sizing) · [Appendix A — proposed ADR](#appendix-a--proposed-adr) · [Appendix B — roadmap edits](#appendix-b--roadmap-edits) · [Appendix C — docs-to-update](#appendix-c--docs-to-update-when-each-slice-lands)

## The two problems

1. **Events are running-specific.** The `/clubs/[slug]/events/new` editor and the event-detail page assume a *run*: attached route, distance, target pace, a race-mode arm/GO/finish loop, a results leaderboard with "Submit my time", finisher certificates, results CSV import/export, result claims ([clubs.md](clubs.md)). For a yoga or pilates class **none of that applies** — and worse, the event-detail page renders the results leaderboard + race-control affordances *unconditionally*, so a class would show a "Submit my time" button and an arm-as-race control. The domain leaks.
2. **No event is payable.** The only money column in the schema is `user_profiles.subscription_tier`; there is no per-event price, no host payout, no marketplace ([paywall.md](paywall.md)).

The user's framing resolves both: **clubs hold generic, typed events; the type drives which fields exist; price is orthogonal to type; payout follows the instructor.**

> **Related:** the race-director operations feature ([race_director_ops.md](race_director_ops.md), decisions §154) extends this same events layer in the other direction — turning "a club hosts an event" into "a race director runs a race" with offline aid-station check-in (`event_checkpoints` + `checkpoint_crossings`) feeding live results + cutoff projection, monetizable through the same Stripe Connect events rail.

## Product contract

Persona-led, so the design stays honest about who's using it:

- **Pilates instructor (Dani) with a studio club.** New event → picks **Class** → discipline "Reformer Pilates", Tuesdays 6:00pm, 50 min, studio address, **10 mats** capacity, **$22**. Members see "Register · $22", pay, and a paid registration *is* their spot; over capacity → waitlist. Dani never sees route / distance / pace / race controls. She onboarded a payout account once in her own settings; the $22 (minus the platform fee) lands in *her* Stripe account, not the club's. If she cancels Thursday's class, every paid registrant for that occurrence is auto-refunded.
- **Run club (the existing user).** New event → **Group run** → route, distance, target pace, optional race mode + leaderboard — exactly as today. Optionally free or paid (a coached track session, a supported long run). Nothing about the run flow regresses.
- **Casual meetup organiser.** New event → **Social** → just title, time, place, capacity. No athletic fields, no results.

Across all of them, **the create form shows only the fields the chosen type needs** (self-hiding), and **free vs paid is one flow** — paid just inserts a charge before the RSVP is granted.

## Slice E — typed events

Add a behaviour-driving **category** plus a free-text **discipline label**, and gate the athletic features on category.

### The category

`events.category` — a narrow client-side union **and** a CHECK constraint, kept in lockstep ([CLAUDE.md](../../CLAUDE.md), append to `check_constraint_unions.mjs` `PAIRS`):

```
EventCategory = 'run' | 'cycle' | 'class' | 'social'
```

The category names **align with the existing `ActivityType` union** (`run | walk | hike | cycle | stroller`, `types.ts`) deliberately — `cycle`, not `ride`, so the app does not grow two parallel vocabularies for the same concept. `EventCategory` is the *coarser, behaviour-driving* superset (it adds `class` + `social`, which aren't activity types); see the mapping below.

- **`run` / `cycle`** — distance-based athletic events. Course-shaped: route, distance, target pace, optional race-mode + results leaderboard + finisher certificate. Produce a `run`-family activity + `event_results`.
- **`class`** — instructor-led, fixed-location session (yoga, pilates, spin, strength, mobility, …). The *specific* discipline is the free-text label, not a category. No route/distance/pace/race/results. Capacity = mats/spots. Attendance, not ranking.
- **`social`** — a meetup. Title, time, place, capacity only.

`events.discipline` — **free text** (`'Vinyasa Yoga'`, `'Reformer Pilates'`, `'Track Tuesday'`). Display label only; **not an enum** (see [anti-patterns](#gotchas--anti-patterns) — hardcoding disciplines is the trap). Mirrors gym's free-text exercise names (`normaliseExerciseName`).

### Field & feature matrix by category

| Field / feature | run | cycle | class | social |
|---|:--:|:--:|:--:|:--:|
| Title, date/time, duration | ✓ | ✓ | ✓ | ✓ |
| Location / meet point + directions | ✓ | ✓ | ✓ (studio) | ✓ |
| Capacity + waitlist | ✓ | ✓ | ✓ (mats) | ✓ |
| Recurrence (weekly/biweekly/monthly) | ✓ | ✓ | ✓ | ✓ |
| RSVP + attendee list | ✓ | ✓ | ✓ | ✓ |
| Club feed posts + cancel-occurrence | ✓ | ✓ | ✓ | ✓ |
| **Discipline label (free text)** | optional | optional | ✓ | optional |
| **Attached route / distance / target pace** | ✓ | ✓ | — | — |
| **Race mode (arm/GO/finish)** | optional | optional | — | — |
| **Results leaderboard / "Submit my time"** | ✓ | ✓ | — | — |
| **Finisher certificate / CSV import-export / claims** | ✓ | ✓ | — | — |
| **Paid registration (price)** | ✓ | ✓ | ✓ | ✓ |

Everything in the top block is **shared** by every category (the genuinely generic event machinery — already built). Everything athletic self-hides for `class` / `social`. **Paid is orthogonal** — the last row applies to every category.

### Category → modality mapping (one type system, not two)

`EventCategory` is a coarse, behaviour-driving superset of `ActivityType`; the mapping is explicit so the two never drift:

| EventCategory | Maps to modality | Activity it produces when attended | Post-event artifact |
|---|---|---|---|
| `run` | running (`ActivityType` `run`/`walk`/`hike`) | a `run` row | `event_results` (race / leaderboard / certificate) |
| `cycle` | running modality, `ActivityType` `cycle` | a `run` row tagged `cycle` | `event_results` |
| `class` | **gym modality** | a `gym_workout` (see below) | attendance (no `event_results`) |
| `social` | none | nothing | attendance |

This is why category names track `ActivityType` (`cycle`, not `ride`): an event's category names *which modality it belongs to*, and the multi-modal app already has a vocabulary for that.

### Post-event artifact by category

- `run` / `cycle` → a logged `run`-family activity + an `event_results` row (race mode, leaderboard, rank, certificate). Unchanged.
- `class` → **attendance** + an **optional logged `gym_workout`** (the designed cross-modal seam — see next). The `event_attendees` `going` row is the attendance record. **No rank, no certificate, no `event_results` row** — a class is not a race.
- `social` → attendance only.

### The class → gym seam is designed, not a footnote

A paid pilates class the user attends **must be able to land in their Train → Gym history and feed the same recovery/load curve their runs do** — otherwise clubs are a bolt-on and the cross-modal-intelligence thesis ([multi_modal.md](multi_modal.md)) doesn't hold for the marketplace. So the connection is part of the contract, even though the *write* may ship after P1:

- A `class` event carries an optional **`gym_template`** hint on the event — a typed `{discipline, duration_min}` jsonb shape (the free-text discipline doubles as the workout title; the default duration is its own field). The host sets it in the editor; an attendee one-tap-creates a `gym_workout` from it (their own row, their own data — the event only *suggests* it, never writes to the attendee's log without consent).
- **This now ships (web + mobile).** The host write goes through `EventEditor` → `createEvent` (class-only; a class the host didn't template writes `gym_template = NULL`, not `{}`, so the attendee affordance self-hides). The attendee read goes through the event-detail "Log this as a workout" button (web `/clubs/[slug]/events/[id]`, mobile `event_detail_screen.dart`), gated on `category === 'class'` **AND** a non-null `gym_template` **AND** a signed-in viewer — a run/cycle/social event never shows it. The button **pre-fills the canonical composer** (web `GymEditor`, mobile `gym_compose_sheet`) from the template (`workoutDraftFromTemplate`: discipline||event-title → title, duration_min×60 → duration_s; sets stay empty); nothing writes until the user confirms inside the composer.
- The typed contract lives in a parity-paired pure helper — web `social/event_gym_template.ts` ↔ mobile `event_gym_template.dart` (`parseGymTemplate` / `gymTemplateFromInputs` / `workoutDraftFromTemplate`) — so the host-write and attendee-read paths share one tolerant parser instead of poking raw jsonb at each call site.
- The read path needs a column grant: `events` is column-SELECT-locked (`20260818_001`), and `20261228_001` left `gym_template` revoked ("reserved for slice P"). Migration **`20261230_001`** grants `SELECT (gym_template)` to `authenticated` + `anon` (mirrors the category/discipline grant); `host_user_id` stays revoked. Pinned by pgtap `event_gym_template_grants_test.sql`.
- This keeps the [§63 data-trust tiers](multi_modal.md#integration-model--inform-tier-1-vs-command-tier-2) intact: attending-logs-a-workout is *inform* (the user confirms in the composer); nothing auto-mutates a plan or the attendee's log.

### Backfill

Every existing event predates the column and is run-shaped → migration defaults `category = 'run'`. The editor must never strand a legacy event without a category.

### Defense in depth, not just hidden UI

Hiding the leaderboard/race controls for a class in the client is **not enough** — a non-athletic event must be *un-race-able and un-result-able at the data layer too*. Extend the `race_sessions` and `event_results` write paths (RLS / trigger) to reject inserts when the parent `events.category NOT IN ('run','cycle')`. A yoga class arm-as-race via a direct API call must 403, not just be invisible.

## Slice P — paid registration

Free and paid registration are **one primitive, two flows** — never a separate "tickets" entity divorced from RSVP:

- **Free event:** "I'm in" → `event_attendees` row (`going` / `waitlisted`), exactly as today.
- **Paid event:** "Register · $X" → Stripe Checkout → a completed order is what writes the `going` row (with an `order_id` FK). No payment, no slot.

The price lives on the event (per-occurrence, with an optional per-instance override for a recurring class — a one-off workshop priced higher than the weekly session). The host must have a payout account with `charges_enabled` before a price can be set (CHECK-backed trigger, not just UI).

### Drop-in registration — no club-join required (verified)

The marketplace's core case is a **drop-in**: someone pays for one class without joining the club as a member. This already works at the policy layer — the `event_attendees` INSERT policy is `auth.uid() = user_id OR organiser`, gated only by event *visibility* (`is_public` club OR member, per `20260428_001`). So a **signed-in non-member can register for (and pay for) a public club's class** today; slice P inherits that. Two constraints to honour:

- **Checkout must not silently join the club.** Registering for a class is a *purchase*, not a membership act — a drop-in student is a customer, not a community member. Don't bundle a `club_members` insert into the registration flow (the host can invite them to join separately).
- **A logged-out stranger must sign up before paying.** Registration requires `auth.uid()` (you can't charge or seat an anonymous attendee). The class link → "Sign in to register" → checkout. This is the marketplace's top-of-funnel and the one unavoidable friction; private-club classes stay member-only by design.

## The load-bearing decision: the app-store tax

A paid thing unlocked *inside* a mobile app is, by default, a **digital good** — and Apple Guideline 3.1.1 / Google Play Billing then force their **30% IAP cut** and forbid routing to Stripe (the same rule that forces the Pro subscription through RevenueCat → StoreKit, see [paywall.md § Regional availability](paywall.md#regional-availability--international-payments)).

**The escape hatch — and it fits classes even better than runs.** Apple and Google both *exempt* **real-world / in-person services and physical event tickets** from IAP (Apple 3.1.3(e) "real-time person-to-person services" / 3.1.5(a) physical services; Google Play physical-goods-and-services carve-out). A live **in-person yoga/pilates class** is the canonical real-world service — closer to a gym day-pass or a concert ticket than to unlocking a feature. So Stripe-on-web is permissible even from mobile for these.

Consequences:

1. **P1 is in-person only** (`event_modality = 'in_person'`). A **virtual / livestream** class *is* a digital good and re-opens the 30% requirement — deferred (P4, behind a legal decision).
2. **The classification is legally load-bearing — counsel signs off before P1.** Starting web-first contains the risk: web carries no app-store tax regardless of how Apple classifies it.
3. **Web takes Stripe directly** (~2.9% + Connect fees, no 30% cut). P1 is web-checkout only even from mobile (see [UI](#web--mobile-ui)).

## The validation gate (stated honestly)

The roadmap has **zero** commitment to typed/paid events ([roadmap.md](../product/roadmap.md)). This is net-new product surface + money movement + third-party-merchant onboarding under SOC 2 / GovRAMP scope — it does not ship on momentum.

Mirroring the gym engine's "relocate the gate, don't jump it" sequencing ([gym_programming.md § The validation gate](gym_programming.md#the-validation-gate-stated-honestly)):

- **Slice E is the cheap probe.** It ships typed events with no money and asks: *do non-running clubs / events even get created?* A yoga instructor can run a **free** class properly the day E lands — a self-contained win. If meaningful non-`run` event creation appears over 4-6 weeks, the marketplace (P) is justified. If every event stays a `run`, freeze at E; the payment build is unwarranted.
- **The bet:** clubs with a professional instructor want to schedule (and eventually monetize) non-running sessions.
- **The explicit tradeoff:** E builds the typed model before any monetization signal — but it's low-cost, additive, and independently useful, so the downside is small. P (the expensive Connect + compliance work) stays gated on E's signal.
- **Owner + CISO + counsel sign-off before P** — the IAP classification, PCI scope, and the expanded sub-processor / DSAR footprint (see [Compliance](#compliance-soc-2--govramp--privacy)).

## Money movement — to the host, not the club

**Stripe Connect, destination charges, with `application_fee_amount`.** The buyer's card is charged on the platform account; funds transfer immediately to the **host's** connected account; the platform's cut is the application fee. This keeps **the host (instructor) as merchant of record** (they own refunds, chargebacks, and the tax relationship) while the platform never touches their banking data.

**The payout account is on the host, not the club** — this is the core of "clubs shouldn't have anything specific":

- `events.host_user_id` (default = creator) names who gets paid. A studio club with a yoga instructor *and* a pilates instructor → each instructor hosts their own classes and receives their own money. The club is just the container they're listed under.
- Onboarding is a **user-level** surface (`/settings/payouts`), done once, reused across every club the host teaches in. **Not** a club setting.
- A **club-level pooled payout account** (for clubs that want all event revenue to land in one place) is a deliberate **P4 deferral** — most instructor cases want money to the person, and pooling adds a "who controls the club's bank account" governance problem.

Flow:

- **Onboard:** `events-connect-onboard` Edge Function → Stripe Account Link (Express account) → hosted KYC/bank/tax. `account.updated` webhook flips `charges_enabled` / `payouts_enabled` in `instructor_payout_accounts`.
- **Checkout:** `events-checkout` validates the sales window + capacity, creates a destination-charge Checkout Session against the host's account with the platform fee, inserts a `pending` order holding a reserved slot (TTL).
- **Confirm:** `stripe-events-webhook` (separate from `revenuecat-webhook`, own HMAC secret, idempotent on Stripe event id) handles `checkout.session.completed` → `paid` + write attendee row; `charge.refunded` → demote + promote waitlist; `account.updated` → sync flags; `checkout.session.expired` → release slot.
- **Payouts:** Stripe's job, on the host's schedule. The platform fee is new company marketplace revenue — **loop in finance** (distinct from subscription revenue, new tax treatment).

## Capacity, waitlist & the payment race

Reuses the shipped `enforce_event_capacity` + `promote_event_waitlist` machinery ([clubs.md § Event detail capabilities](clubs.md#event-detail-capabilities)). Hard studio capacity (10 mats) makes correctness *more* important for classes than for group runs:

- **Soft reservation:** creating a Checkout Session inserts a `pending` order that **counts toward capacity** for `reserved_until` (~15 min, matching Stripe's session TTL), so two buyers can't pay for the last mat simultaneously. Expired pendings are swept (a `jobs` kind or a `reserved_until < now()` read filter).
- **Confirm-time capacity recheck** at `checkout.session.completed` (not at session creation). If the class filled via another path, the paid registrant is **auto-refunded and notified** — holding a stranger's money for a maybe-slot is the wrong default.
- **Waitlist promotion never auto-charges.** When a mat frees, a waitlisted user is **notified to complete payment** (`event_waitlist_slot` notification + checkout link + short claim window), never charged silently.

## Refunds & cancellation coupling

Extends the shipped cancel-occurrence (`event_exceptions`) + `notify_event_cancel` flow:

- **Host cancels an occurrence** → `refund_orders_for_instance(event_id, instance_start)` full-refunds every `paid` order for that instance (the host cancelled, so policy is overridden to full), marks orders `refunded`, demotes RSVPs, and the existing cancel notification carries a "you've been refunded" line.
- **Buyer self-cancels** → honoured per `event_pricing.refund_policy` (`full_until_start | full_until_24h | no_refund`); freeing the slot triggers waitlist promotion → notify-to-pay.
- **Refunds reverse the application fee** (`refund_application_fee: true`) so the platform doesn't profit on a cancelled class. Chargebacks are the host's liability (merchant of record), but the platform fee is clawed back — state this in onboarding copy.

## Data model

Additive columns on `events` (slice E):

- `category` (`EventCategory`, NOT NULL, default `'run'`, CHECK-constrained).
- `discipline` (text, nullable — free-text display label).
- `host_user_id` (uuid FK → `auth.users`, default = creator; names the payout recipient).
- `gym_template` (jsonb, nullable — only meaningful for `category = 'class'`; the typed `{discipline, duration_min}` an attendee's one-tap "log this as a workout" pre-fills. **Shipped (web + mobile, inform-tier).** Cross-user `SELECT` granted by `20261230_001` (the column-locked `events` table left it deny-by-default); parsed through the `event_gym_template.ts` ↔ `.dart` parity pair).

Additive column on `event_attendees` (slice P):

- `order_id` (nullable FK → `event_orders`; NULL for free events; CHECK-backed trigger requires a `paid` order for a `going`/`waitlisted` row on a priced event).

New tables (slice P; both type generators must run — [schema_codegen.md](../architecture/schema_codegen.md)):

- **`instructor_payout_accounts`** — `user_id` PK, `stripe_connect_account_id`, `charges_enabled` / `payouts_enabled` / `details_submitted` (mirrored from Stripe by webhook), `country`, `default_currency`, `onboarded_at`. **No bank/tax/SSN data** — Stripe holds it. RLS: own-row only; the connected-account id is revoked from `anon`/`authenticated` SELECT (surface a boolean "can take payment" via a view, the `get_event_meet_point` pattern in [clubs.md](clubs.md)).
- **`event_pricing`** — `(event_id, instance_start)` (NULL instance = whole series; non-null overrides one occurrence), `price_cents` (>0), `currency`, `modality ∈ {in_person}` (v1; `virtual` reserved), `platform_fee_bps` (platform config, not host-set), `refund_policy ∈ {full_until_start, full_until_24h, no_refund}`, `sales_close_offset_minutes`. RLS: readable with the event; writable by `is_event_organiser(club_id)` **and** only when the host has `charges_enabled` (trigger-enforced).
- **`event_orders`** — the ledger. `id` PK, `event_id`, `instance_start`, `buyer_user_id`, `host_user_id`, `stripe_checkout_session_id`, `stripe_payment_intent_id`, `amount_cents`, `currency`, `platform_fee_cents`, `status ∈ {pending, paid, refunded, partially_refunded, failed, canceled}`, `created_at`, `paid_at`, `refunded_at`, `reserved_until`. RLS: buyer reads own; host reads orders for their events; **writes are service-role only** (webhook is the sole writer — the `subscription_tier` lock pattern, [paywall.md § Tiers](paywall.md#tiers)).

New narrow unions (TS + CHECK lockstep; append to `check_constraint_unions.mjs` `PAIRS`):

- `EventCategory = 'run' | 'cycle' | 'class' | 'social'` (names track `ActivityType`)
- `OrderStatus = 'pending' | 'paid' | 'refunded' | 'partially_refunded' | 'failed' | 'canceled'`
- `RefundPolicy = 'full_until_start' | 'full_until_24h' | 'no_refund'`
- `EventModality = 'in_person'` (`'virtual'` added when P4 lands)

No new `runs.metadata` keys (relational, not jsonb) → no [metadata.md](../backend/metadata.md) churn.

## Web & mobile UI

Web-first per [decisions.md § 24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive):

- **`EventEditor` (web, `/clubs/[slug]/events/new` + edit)** — **type-first**: step 1 picks the category (Group run · Cycle · Class · Social) with a one-line description each; the rest of the form is rendered *by category* so a Class never shows route/distance/pace/race. A free-text "Discipline" field appears for Class. A "Charge for this event" toggle (disabled with an explainer until the host has `charges_enabled`) reveals price / currency / refund policy / sales-close offset. Per-series vs per-occurrence pricing follows the existing recurrence picker.
- **`/clubs/[slug]/events/[id]` (web)** — the page composes **by category**: a Class shows time / studio map / capacity / attendee list / register button — and **no** leaderboard, race control, or "Submit my time"; a run shows the existing athletic surface. On a priced event the RSVP row becomes "Register · $X" → Stripe → `?paid=1` success reflecting the confirmed RSVP (poll fallback for webhook latency, the <5s pattern in [paywall.md](paywall.md)).
- **`/settings/payouts` (web, user-level)** — Connect onboarding entry ("Set up payments to host paid events"), `charges_enabled` status, re-entry to Stripe's dashboard. **User-level, not per-club.**
- **Mobile (Android/iOS)** — typed-event *creation* now ships on mobile too: `widgets/event_form_sheet.dart` exposes the category picker + `class` discipline and `SocialService.createEvent` writes `category` / `discipline` / `gym_template`. Mobile also **renders typed events read-only and composes by category** (a class hides the athletic surface, same gating logic, byte-identical twin per [§ 39](../architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)). **Paid registration on mobile is P3** and routes to **web checkout in a Custom Tab / in-app browser** (the in-person-service exemption permits it, but it's deferred to keep P1's blast radius + IAP-classification risk contained). In P1, mobile has no register/checkout flow — a priced event shows the price read-only (no purchase path), and registration + payment happen on web. Never add a `BYPASS_PAYWALL`-style override here ([paywall.md § Mobile](paywall.md#mobile--watch--other-web-endpoints)).
- **Watch** — out of scope entirely (no purchase, no creation).

## Compliance (SOC 2 / GovRAMP / privacy)

Money movement + a new sub-processor make slice P the most compliance-heavy feature in the app. **Loop in the CISO / Security Analyst and counsel before P1** (org policy for SOC 2 / GovRAMP-scoped changes):

- **PCI scope:** **Stripe-hosted Checkout + onboarding keeps us at SAQ A** (card data never touches our servers/bundle). **Do not build a custom card form** — that escalates PCI scope dramatically. Hard constraint.
- **New sub-processor:** Stripe Connect processes buyer *and* host personal/financial data → add to the sub-processor list + Privacy Policy (`/audit/third-party-data-flows`).
- **DSAR / deletion:** `event_orders` + `instructor_payout_accounts` are new personal-data tables → into the GDPR export (Art 20) + deletion (Art 17) paths (`/audit/data-export-completeness`, `/audit/account-deletion-completeness`). **Tension:** financial records carry a legal retention requirement (tax/AML) that can override erasure — orders likely retain (anonymized) past account deletion; counsel sets the term, documented in the GDPR posture.
- **GovRAMP:** payment flows are not GovRAMP-scoped and must not process government/regulated data — standard separation.
- **Funds-flow integrity:** webhook is the sole writer of order status (service-role RLS), HMAC-verified, **idempotent on Stripe event id** (a replayed `checkout.session.completed` must not double-grant a mat or double-count revenue).

## Gotchas & anti-patterns

The user explicitly asked these be ironed out. **Anti-patterns (do not do):**

1. **Don't build a parallel "Classes" feature / table / tab.** One `events` table; `category` drives behaviour. *Why events keeps a `category` column when `runs.kind` was dropped (§63, migration `20261206_001`):* `runs.kind` was a cross-table polymorphism replaced by the `activities` view injecting a literal per UNION branch — different problem. `events.category` drives **UI field visibility within one editor + one detail page**, where the optional field sets genuinely diverge. It's a discriminant for presentation + feature-gating, not a join key.
2. **Don't hardcode yoga / pilates / spin as enum values.** Broad `category` for behaviour + **free-text `discipline`** for the label (the gym free-text-exercise precedent). A rigid discipline enum needs a migration for every new class style — exactly the brittleness to avoid.
3. **Don't make "paid" a separate entity from the event / RSVP.** Price is a property of the event; a completed order gates the existing RSVP. No parallel "tickets" model.
4. **Don't put the payout account on the club.** Money follows the **host** (`host_user_id`); onboarding is user-level. Clubs stay generic. (Club-level pooling is a P4 governance decision, not a default.)
5. **Don't render athletic affordances on non-athletic events.** Route / distance / pace / race mode / leaderboard / "Submit my time" / certificate / CSV / claims must each be gated on `category` — **today they render unconditionally**, which is a live bug for a class. Gate in UI *and* at the data layer (next item).
6. **Don't rely on hidden UI for safety.** Block `race_sessions` + `event_results` writes for `category NOT IN ('run','cycle')` at RLS/trigger level — a class must be un-race-able via direct API, not merely invisible.
7. **Don't build a custom card form.** Stripe-hosted Checkout = SAQ A; a custom form explodes PCI scope.
8. **Don't auto-charge a waitlisted attendee on promotion.** Notify-to-pay with a claim window.
9. **Don't reuse the RevenueCat / subscription path, and don't make the platform merchant of record.** Stripe Connect destination charges; host is merchant of record.
10. **Don't let a user-JWT write `event_orders.status`.** Webhook-only (service role), idempotent.
11. **Don't give a class a rank / certificate / `event_results` row.** Classes are attendance, not results.

**Gotchas (watch for):**

- **Backfill** existing events to `category = 'run'`; the editor + detail page must handle a legacy event gracefully (never a null category).
- **`runs.event_id` assumes a run** — a class produces no run, so don't require the backlink or a `run_id` for class attendance.
- **Recurrence + per-instance pricing:** a weekly class priced per session; a cancelled occurrence refunds *only that instance's* orders (the `event_exceptions` coupling), not the series.
- **Confirm-time capacity** for paid classes — hard studio capacity makes oversell worse; reserve at checkout, recheck at webhook.
- **Currency:** host's settlement currency vs buyer's card currency — Stripe converts + shows the buyer their localized amount; store the order in the host's currency.
- **Time zones:** a recurring class's `instance_start` is ISO; ensure attendee/spectator surfaces render it in the viewer's local zone (a 6pm class must not show as 1am to a member in another zone).
- **Host loses `charges_enabled` mid-series** (KYC lapse) → block new registrations with a clear host-facing error; existing paid registrations unaffected.
- **DSAR vs financial retention** (above) — orders aren't freely erasable.
- **Twin parity** for any Dart pure helper (fee math / sales window / category-gating predicate); **i18n** for the new category labels + discipline placeholder + register/price strings in all six web gen-l10n catalogues + all mobile ARBs.
- **Accessibility:** the category picker + price field need labels; the register button needs explicit loading / sold-out / sales-closed states (`/audit/accessibility`, the `/ux-hunt` checklist).
- **Webhook replay idempotency** on Stripe event id (above).

## Failure modes

Per the [layered-resilience contract](../architecture/conventions.md#layered-resilience) — a payment-layer failure must never corrupt the free-event flow:

- **Charge succeeds, attendee write fails** → idempotent webhook retries; reconciliation grants the slot or refunds if the event vanished. Never a `paid` order with no slot and no refund.
- **Webhook never arrives** → success-page poll + periodic reconciliation vs Stripe's API; buyer sees "processing", not a false failure.
- **Capacity race** → soft reservation + confirm-time recheck; invariant: never oversell.
- **Refund fails at Stripe** → surfaced to host + ops, order flagged `refund_failed`, retried; user told a refund is in progress, never silently dropped.
- **A class accidentally created as a `run`** (or vice-versa) → category is editable; switching to a non-athletic category hides + (at the data layer) blocks the athletic features, and warns if results/race data already exists.

## Testing

Per the [test-hygiene rule](../architecture/conventions.md#test-hygiene--review-then-unit-then-e2e) (review → unit → e2e):

- **Unit (web):** the category→field-visibility predicate, capacity-reservation math, sales-window logic, refund-policy resolution, fee computation. Pure, no Stripe.
- **e2e (web, Playwright):** create a Class (assert no route/distance/pace/leaderboard rendered) and a Group run (assert they *are*); Stripe **test mode** end-to-end — onboard a test Connect account, price a class, register with `4242…`, assert the RSVP; cancel the occurrence, assert refund + demotion. Stubs per [local_testing_stubs.md](../testing/local_testing_stubs.md).
- **e2e (backend, Deno/pgtap):** category-gated race/result writes 403 for a class; webhook idempotency (replay = one grant); RLS (buyer can't read another's order; non-host can't price; user-JWT can't write order status); confirm-time capacity decision.
- **Twin parity:** any Dart pure helper joins the [lockstep list](../../CLAUDE.md). E's category-gating predicate that lands in Dart is the first such pair.

## File list

Slice E (web + backend):

- `apps/backend/supabase/migrations/20261227_001_typed_events.sql` — `events.category` / `discipline` / `host_user_id` / `gym_template` + CHECK + backfill + the `race_sessions`/`event_results` category guards; `20261228_001_typed_events_column_grants.sql` grants cross-user `SELECT (category, discipline)` (the column-locked `events` table left them deny-by-default); `20261230_001_grant_gym_template_select.sql` grants `SELECT (gym_template)` for the class→gym seam.
- `apps/web/src/lib/social/event_category.ts` — pure category→capabilities predicate (parity-paired).
- `EventEditor` + `/clubs/[slug]/events/[id]` (web) + mobile `event_detail_screen.dart` — compose by category.
- Regenerate both type files; add `EventCategory` to `types.ts` + `check_constraint_unions.mjs`.

Slice P (web + backend):

- `apps/backend/supabase/migrations/20261229_001_paid_events.sql` — the three tables + `event_attendees.order_id` + RLS + CHECK + capacity/refund trigger extensions.
- `apps/backend/supabase/functions/events-connect-onboard/index.ts`, `events-checkout/index.ts`, `stripe-events-webhook/index.ts` (separate from `revenuecat-webhook`).
- `apps/web/src/lib/social/paid_registration.ts` — pure fee/sales-window/refund helpers.
- `apps/web/src/lib/core/data.ts` — `fetchEventPricing` / `startEventCheckout` / `fetchPayoutAccount` / `startConnectOnboarding` / host registrations summary.
- `apps/web/src/routes/settings/payouts/+page.svelte`; `EventEditor` price toggle; `/clubs/[slug]/events/[id]` register button.
- Add `OrderStatus` / `RefundPolicy` / `EventModality` to `types.ts` + `check_constraint_unions.mjs`.
- Secrets: `STRIPE_SECRET_KEY`, `STRIPE_CONNECT_CLIENT_ID`, `STRIPE_EVENTS_WEBHOOK_SECRET` — Supabase function env, never client-readable.

Slice P2 (web + backend) additions:

- `apps/backend/supabase/migrations/20270303_001_event_order_self_cancel.sql` — `event_orders.refund_initiated_at` + the buyer refund-stamp UPDATE policy + `lock_event_order_status` widened to a column-lock.
- `apps/backend/supabase/functions/events-cancel/{index,lib,lib.test}.ts` — buyer self-cancel EF (initiate-only; never writes status); `stripe-events-webhook` extended to handle `charge.refunded` (sole status writer).
- `apps/backend/supabase/tests/event_order_self_cancel_test.sql` — pgtap for the column-lock + buyer policy.
- `apps/web/src/lib/core/data.ts` — `cancelEventOrder`; `apps/web/src/routes/clubs/[slug]/events/[id]/+page.svelte` — Cancel-registration affordance + refund-pending badge; `apps/web/tests-e2e/clubs/event-self-cancel.spec.ts`.

## Phasing & rollout

| Slice | Scope | Gate |
|---|---|---|
| **E** (proposed first) | Typed events (`category` + `discipline`), self-hiding athletic fields, data-layer race/result guards, backfill. **No money.** Web create + web/mobile read. A free yoga/pilates/social event works properly. | Owner sign-off (low-risk, additive) |
| **P1** ✅ shipped on web (live charge path unverified — needs operator Stripe test keys) | Stripe Connect onboarding + destination-charge checkout + one webhook, **in-person only**, **host payouts**, web checkout only, manual refunds via Stripe dashboard. Migration `20261229_001` + the three Edge Functions + `/settings/payouts` + the EventEditor Charge toggle + the event-detail Register flow. | E shows non-`run` events get created; owner + CISO + counsel sign-off |
| **P2** ✅ buyer self-cancel + automated refund coupling shipped on web (live refund round-trip unverified — needs operator Stripe test keys); waitlist notify-to-pay + reconciliation sweep still deferred | Buyer self-cancel per `refund_policy` → `events-cancel` EF initiates the Stripe refund / reservation release; `stripe-events-webhook` (still the sole status writer) flips `paid->refunded` on `charge.refunded` + frees the seat. Migration `20270303_001` (`event_orders.refund_initiated_at` + the status-lock→column-lock + buyer refund-stamp policy) + the event-detail Cancel affordance. Decisions §187. | P1 conversion signal |
| **P3** | Mobile register (web-checkout handoff), payout summary, receipt + refund emails (extend [email.md](email.md)). **The class→gym seam (attended class → one-tap log a `gym_workout` from `gym_template`) has SHIPPED early** (web + mobile, inform-tier — it's orthogonal to the paid path, so it didn't wait on P2). | P2 stable |
| **P4** | Class-pass / recurring memberships (re-opens the IAP subscription bucket), **virtual/livestream paid events** (digital-good IAP decision), discount codes, **club-level pooled payouts**. | Separate product + legal decision |

## Open questions

1. **Platform fee rate** (`platform_fee_bps`) — 0% to seed adoption vs a real take-rate. Product + finance.
2. **Paid-buyer-lands-on-waitlist** — auto-refund (spec default) vs hold-as-paid-waitlisted. Confirm.
3. **Account-deletion vs financial retention** term for `event_orders`. Counsel.
4. **Connect account type** — Express (Stripe-hosted dashboard, fastest; P1 assumption) vs Standard.
5. **Is hosting paid events itself a Pro-host perk?** — ties into the existing paywall.
6. **Do we need `cycle` in v1**, or is `run | class | social` enough until cycling events appear? (Adding a category later is a migration + union + CHECK triple.)

## Rough sizing

- **Slice E:** ~1-1.5 wk (column + backfill + category-gated rendering on web + mobile + the data-layer guards + tests). Low risk, additive.
- **P1:** ~4-5 wk to a defensible slice — the registration flow (~2-3 wk the followup noted) **plus** the Connect foundation (onboarding, webhook, capability sync, reconciliation) **plus** the compliance/legal pass that can't be skipped.
- **P2-P3:** ~2-3 wk each. **P4:** a separate initiative.

## Appendix A — proposed ADR

Ready to lift into [decisions.md](../architecture/decisions.md) at the next free number when approved (the gym + multi-modal-redesign specs also hold unlanded numbers — assign sequentially at landing):

> **§N. Club events are typed (`run | cycle | class | social`, names aligned to `ActivityType`) with self-hiding fields; paid registration is an orthogonal Stripe Connect marketplace whose payouts go to the event host, not the club.** Clubs are generic containers. The event model was running-specific (route/distance/pace/race/results rendered unconditionally), which broke instructor-led classes. Decision: add `events.category` (a presentation + feature-gating discriminant — *not* a join key, distinct from the dropped `runs.kind`; names track the existing `ActivityType` union so the app keeps one type vocabulary, with an explicit category→modality mapping where a `class` maps to the gym modality) + a free-text `events.discipline` label (no discipline enum, mirroring gym's free-text exercises); gate every athletic affordance on category in UI **and** at the data layer (a class is un-race-able via direct API). A `class` event is attendance-only with a designed (if later-built) seam to log a `gym_workout` for the attendee, so the marketplace participates in the cross-modal model rather than bolting on. Paid registration is orthogonal to category: price is a property of the event, a completed Stripe Checkout order gates the existing RSVP (no separate tickets entity), and funds settle into the **host's** connected account (`events.host_user_id`) via destination charges with an application fee — the host is merchant of record, not the platform or the club. Onboarding is user-level (`/settings/payouts`), reusable across clubs; club-level pooled payouts are deferred (P4). P1 is in-person-only + web-checkout-only because in-person services are IAP-exempt (Apple 3.1.3(e)/3.1.5; Play physical-services carve-out) whereas a virtual class is not; web carries no app-store tax regardless. Hosted Stripe Checkout keeps PCI scope at SAQ A; the webhook is the sole, idempotent, service-role-only writer of order status. Supersedes the `followups.md` "Paid event registration" note. Slice E (typing, no money) ships first as the gate probe; P (the marketplace) is gated on E showing non-running events get created.

## Appendix B — roadmap edits

When E lands: in [roadmap.md](../product/roadmap.md) under Clubs and events, add a "Typed events (run / class / social)" row (E-shipped). When P1 lands, add "Paid events (marketplace)" (P1-shipped / P2-P4 planned) and **remove the `followups.md` "Paid event registration" line** (this spec supersedes it). Flip [parity.md](../product/parity.md) cells (web ✓; mobile read ✓ / register ✗ until P3; watch ✗).

## Appendix C — docs-to-update (when each slice lands)

- [clubs.md](clubs.md) — the event model is now typed; the athletic surface (race mode, results, certificates) is `run`/`cycle`-only; mobile Social no longer hosts routes (per the [multi_modal.md redesign](multi_modal.md#proposed-redesign-pending-sign-off--the-train-hub--routes-relocation)); add the paid-registration subsection.
- [paywall.md](paywall.md) — cross-reference: the marketplace path is separate from the Pro/RevenueCat path; note the two webhooks.
- [api_database.md](../backend/api_database.md) — the new columns + three tables + RLS + the revoked connected-account-id column + the category-gated race/result guards.
- [integrations.md](integrations.md) — Stripe Connect as a payment integration (distinct from data-sync integrations).
- [email.md](email.md) — P3 receipt + refund job kinds.
- The GDPR posture docs + sub-processor list (counsel-reviewed).
- `parity.md`, `roadmap.md` per Appendix B; both type files regenerated; `check_constraint_unions.mjs` `PAIRS` updated for `EventCategory` / `OrderStatus` / `RefundPolicy`.
