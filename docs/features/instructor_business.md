# Instructor business readiness — letting a gym / yoga instructor run their class business in the app

> **Status: PARTIALLY BUILT (content track shipped; money track gated).** As of 2026-06-11 the gate-cleared content + ops milestones have landed: **M0** (the [readiness pack](instructor_business_m0_readiness.md), no code), **M2** (`gym_sets.duration_s`), **M3** (gym routine engine P1, web + mobile), **M4** (session plan engine P1, web + mobile read), **M6** (attendance / check-in, web + mobile). The whole **money track (M1 / M7 / M8 / M9 / M10) remains gated** on the M0 sign-offs + Stripe Connect keys, and **M5** (follow-along execution) has its **pure-logic + runner + metadata layer merged (2026-06-11) and the web session follow-along player shipped (2026-06-12)** — the `gym_adherence` / `gym_progression` parity pairs, `expandRoutineSteps`, `computeSessionAdherence`, `workoutDraftFromSession`, the `GymWorkoutRunner`, and the `gym_workouts.metadata` execution trios are merged, and the web `SessionRunner` player logs a follow-along session as a `gym_workout` — but the web gym-routine runner UI + the mobile follow-along runners are still in progress and stay gated behind the M3/M4 engagement signal. This is a sequencing document, not a new spec — it ties three existing specs ([club_events.md](club_events.md), [gym_programming.md](gym_programming.md), [session_planner.md](session_planner.md)) into one ordered path. Nothing ships without the per-milestone gate being met — and the payment go-live milestone carries a **hard compliance gate** (owner + CISO + counsel sign-off under SOC 2 / GovRAMP).

> **North star check.** Per [multi_modal.md](multi_modal.md) and [club_events.md](club_events.md), the instructor business is **a retention + community layer in service of the individual athlete, not a second business.** We are not building Mindbody/ClassPass. Every milestone below earns its place by deepening the core app — the payoff is that an attended class lands in the student's Train history and feeds the same cross-modal Coach context as their runs and lifts. If a slice doesn't serve that, it doesn't ship.

**Contents:** [The two personas](#the-two-personas) · [What "seamless" means](#what-seamless-means-the-business-journey) · [Current state — verified](#current-state--verified-in-code) · [The three tracks](#the-three-tracks) · [Milestone sequence](#milestone-sequence) · [The compliance gate](#the-compliance-gate-load-bearing) · [Cross-cutting requirements](#cross-cutting-requirements) · [Risks & open questions](#risks--open-questions) · [Rough sizing](#rough-sizing) · [Docs to update](#docs-to-update-as-each-milestone-lands)

## The two personas

Two read-only persona bug-hunters drive this plan (`.claude/agents/personas/`):

- **`gym-class-instructor`** — strength / HIIT / spin / bootcamp coach. Class content is a **gym routine** (exercises × sets × reps × **load**, supersets, planned-vs-actual). Capacity = spots/bikes/racks.
- **`yoga-pilates-instructor`** — the canonical "Dani" the typed-events spec was written around. Class content is a **timed pose sequence** (holds, per-side, breath/alignment cues, flow order — **no load**). Capacity = mats/reformers.

They share ~80% of the journey (scheduling, getting paid to the *host* not the club, capacity/waitlist, refunds, cross-modal logging) and diverge only on the **content engine** (gym routine vs session plan). The plan reflects that: one shared core, two thin content tracks.

## What "seamless" means (the business journey)

The end-to-end loop an instructor must complete without leaving the app or hitting a dead end:

| # | Step | Persona need |
|---|---|---|
| 1 | **Set up to get paid** | Onboard a payout account once; money lands in *my* account, not the club's |
| 2 | **Schedule a class** | Typed `class` event, recurrence, hard capacity, drop-in price |
| 3 | **Members register + pay** | Drop-in without club-join; a paid order *is* the spot; waitlist when full |
| 4 | **Author the class content** | Build/reuse the workout (gym routine) or the sequence (session plan) |
| 5 | **Teach / follow along** | Teach from the content; students follow along at home |
| 6 | **Class lands in student history** | Attending logs a `gym_workout` → feeds their recovery/load curve (the cross-modal payoff) |
| 7 | **Run the day** | See who registered; mark who actually attended |
| 8 | **Handle changes** | Cancel an occurrence → every paid registrant auto-refunded |
| 9 | **Get paid out + reconcile** | See earnings per class / month; trust the payout |
| 10 | **Do it from my phone** | Register / manage on mobile, not only web |

## Current state — verified in code

Confirmed by reading migrations + source on 2026-06-11 (not just trusting the docs):

| Step | State | Evidence |
|---|---|---|
| 1 Payout onboarding | **Built (web), live path dark** | `/settings/payouts/+page.svelte`, `events-connect-onboard`, `instructor_payout_accounts` (`20261229_001`). No Stripe Connect test keys → never exercised live. |
| 2 Schedule typed class | **Shipped** | `events.category`/`discipline` (`20261227_001`), `EventEditor.svelte` type-first, web/mobile read (`event_detail_screen.dart`). |
| 3 Register + pay | **Rail built (web), charge dark** | `events-checkout` (destination charge), `stripe-events-webhook` (idempotent, service-role), `event_pricing`/`event_orders`. Drop-in policy verified. Charge unverified (no keys). |
| 4 Author content | **Shipped (P1, M3+M4)** | Gym routine engine P1 — `gym_routines` / `gym_routine_exercises` / `gym_routine_sets` + `gym_workouts.metadata` (migration `20270101_001`), the `gym_routine` parity helper, `/gym/routines` library + builder + detail, "Save as routine" / "Repeat last", web **and** mobile twin ([gym_programming.md](gym_programming.md)). Session plan engine P1 — `session_plans` / `_blocks` / `_items` (migration `20270103_001`), `expandSessionSteps` parity pair, `SessionPlanEditor` + `/sessions` + class-event attach, web canonical + mobile read ([session_planner.md](session_planner.md)). Both authoring-only (no execution). |
| 5 Teach / follow along | **Web session player shipped; gym runner + mobile in progress (M5)** | The `GymWorkoutRunner` (`packages/run_recorder`) + the adherence/progression/expand/session parity pairs + the metadata trios are merged; the **web session follow-along player shipped** (2026-06-12, `SessionRunner.svelte` + `SessionExecutionBand.svelte` on `/sessions/[id]`, logs a `gym_workout` with the session metadata trio). The web gym runner UI + the mobile follow-along runners are still in progress. Gated on the M3/M4 engagement signal. |
| 6 Cross-modal log | **Partial — substrate improved (M2)** | One-tap "Log this as a workout" from the flat template (`event_gym_template.ts`↔`.dart`, `workoutDraftFromTemplate`) is still the only logging path. M2 added a nullable `gym_sets.duration_s` (`20261231_001`) so a timed hold now has a first-class home, but the rich follow-along log (carry hold-time / per-side / load from authored content) is the M5 execution slice — deferred. |
| 7 Attendance | **Shipped (M6)** | `event_attendees.attendance` (`attended` / `no_show`, NULL until marked, migration `20270102_001`) + the organiser-only `mark_attendance` SECURITY DEFINER RPC (sole write path); host marking UI on web + mobile twin, read-only for non-hosts. Orthogonal to RSVP `status`. |
| 8 Cancel → refund | **Schema P1, coupling P2** | `event_exceptions` cancel + `notify_event_cancel` shipped; automated `refund_orders_for_instance` is deferred (P2). P1 refunds are manual via Stripe dashboard. |
| 9 Earnings / reconcile | **MISSING in-app** | `data.ts` has `fetchPayoutAccount` but no host earnings/registrations summary. Stripe dashboard only. |
| 10 Mobile register | **P3** | Mobile renders read-only + "Register on the web"; create is web-only by design. |

**Also confirmed (now resolved):** `gym_sets` originally had `reps` / `weight_kg` / `rpe` but no `duration_s`. M2 added a nullable `gym_sets.duration_s` (migration `20261231_001`), so a 90 s plank or a timed hold now has a first-class home — this closed `session_planner.md` open question #1.

**Read (updated 2026-06-11):** the content engines (M2/M3/M4) and attendance (M6) have **shipped** web-first (mobile per slice). What remains: (a) turning the money on safely — **Track A, still gated** on the M0 sign-offs + Stripe keys; (b) the follow-along execution + rich cross-modal logging (M5, deferred behind the M3/M4 engagement signal); (c) the remaining operational surfaces (earnings M7, automated refunds M8, mobile register M10).

## The three tracks

- **Track A — Make the money real.** Take the built-but-dark payment rail to a verified, signed-off, production-exposed state. Unblocks steps 1, 3, 8, 9. **This is the gating track** — without it the marketplace is theatre.
- **Track B — Make the class teachable + loggable.** Build the content engines: gym routines for the gym persona, session plans for the yoga persona, plus `gym_sets.duration_s` so both log cleanly. Unblocks steps 4, 5, 6.
- **Track C — Run the day.** Attendance/check-in, in-app earnings summary, automated refund-on-cancel coupling, mobile register. Unblocks steps 7, 9, 10 and hardens 8.

Tracks A and B are **independent** — B (content) needs no Stripe keys and no compliance sign-off, so it can proceed in parallel with (or ahead of) A's legal/ops work. That independence is the key scheduling lever: **B is the safe place to build while A waits on people.**

## Milestone sequence

Ordered by value-per-unit-risk. Each milestone is independently shippable and web-first ([§24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)).

### M0 — Decision + go-live readiness pack (Track A, no code) — ✅ Shipped (2026-06-11)
Delivered as [instructor_business_m0_readiness.md](instructor_business_m0_readiness.md). Get the people-decisions moving before building more. Produce: the sign-off checklist (owner + CISO + counsel — see [the gate](#the-compliance-gate-load-bearing)), the sub-processor / DSAR / financial-retention answers (`club_events.md` Compliance), and the operator task to provision Stripe Connect **test** keys (`sk_test_`/`ca_`/`whsec_`, per [local_testing_stubs.md § Stripe Connect](../testing/local_testing_stubs.md)). **Gate to start:** none. **Gate to exit:** decisions assigned, test keys requested.

### M1 — Verify the payment rail end-to-end in test mode (Track A)
With Connect test keys in place, exercise the dark path: onboard a test Express account, price a class, register with `4242…`, assert the `going` row + `order_id`, replay the webhook (assert one grant), cancel and confirm the (manual, P1) refund. Land the Playwright + Deno coverage `club_events.md § Testing` specifies but that couldn't run without keys. **Gate to start:** M0 test keys. **Gate to exit:** green e2e in test mode; no charge logic changes needed, or bugs found are fixed at root.

### M2 — gym_sets.duration_s — first-class timed work (Track B, foundation) — ✅ Shipped (2026-06-11, migration `20261231_001`)
A small schema change that unblocks clean logging for *both* personas (planks, holds, timed intervals). Add nullable `gym_sets.duration_s`; thread it through `GymEditor` / `gym_compose_sheet`, the history rollup, and the parity helpers. **Decide before M5** — that's the logging/runner step where a timed hold must land in `gym_sets` (`session_planner.md` open Q1 phrases it as "before P2", i.e. before its execution+logging slice). **Gate to start:** none (additive). **Gate to exit:** migration + both type generators + twin parity + tests.

### M3 — Gym routine engine P1 (Track B — gym persona content) — ✅ Shipped (2026-06-11, web + mobile, migration `20270101_001`)
Build [gym_programming.md](gym_programming.md) P1 only: reusable routines (exercises × sets × reps × load) + "repeat last", build/save/reuse, no execution. (Supersets and `expandRoutineSteps` are gym_programming P2, not P1 — they land later under M5's execution work.) This is the gym instructor's "author the class content" step. **Gate to start:** owner sign-off (per that spec). **Gate to exit:** P1 file list complete, web-first, twin helper + tests.

### M4 — Session plan engine P1 (Track B — yoga persona content) — ✅ Shipped (2026-06-11, web + mobile read, migration `20270103_001`)
Build [session_planner.md](session_planner.md) P1 only: `session_plans`/`_blocks`/`_items`, the `expandSessionSteps` parity pair, the editor, no execution. The yoga instructor's "author the sequence" step. **Gate to start:** owner sign-off. **Gate to exit:** P1 file list complete; `SessionItemKind` CHECK↔union lockstep; twin helper + tests.

### M5 — The follow-along + log seam (Track B execution, both personas)
The execution slices that turn authored content into a logged activity: gym routine execution + session follow-along runner (`SessionRunner`), each on finish opening the gym composer pre-filled (`workoutDraftFromSession` falling back to `workoutDraftFromTemplate`). This delivers step 6 richly. Note the gym side spans two of gym_programming.md's slices — supersets/`expandRoutineSteps` (P2) then the `GymWorkoutRunner` (P3) — so M5's gym half inherits both of those gates; the session-plan side is session_planner.md P2. **Pure-logic + runner layer landed 2026-06-11; web session player shipped 2026-06-12:** `expandRoutineSteps` + the `gym_adherence` / `gym_progression` pairs, `computeSessionAdherence`, `workoutDraftFromSession`, the `GymWorkoutRunner`, and the `gym_workouts.metadata` execution trios are merged, and the **web session follow-along player** (`SessionRunner.svelte` + `SessionExecutionBand.svelte` on `/sessions/[id]`) is shipped; what remains is the web gym-routine runner UI + the mobile follow-along runners, still in progress. **Gate to start:** M3/M4 show instructors actually build content (the engagement/validation gate in both specs — for the gym side, P1's repeat-rate clearing the owner threshold). **Gate to exit:** runner state machines + offline + keep-alive + TTS, twin parity, tests.

### M6 — Attendance / check-in (Track C) — ✅ Shipped (2026-06-11, web + mobile, migration `20270102_001`)
Add an attendance concept distinct from RSVP (`attended` / `no_show`, or a check-in timestamp on `event_attendees`) so the instructor can mark who showed — paid ≠ attended. Host-only write, attendee-readable. **Gate to start:** none (additive, no money). **Gate to exit:** migration + RLS + host UI + tests. **Shipped as the lean enum:** nullable `event_attendees.attendance` (`attended`/`no_show`) + the organiser-only `mark_attendance` RPC as the sole write path (the table's column UPDATE on `attendance` is revoked); host UI web + mobile twin; pgtap + Playwright + Flutter tests.

### M7 — In-app earnings / payout summary (Track C)
A host-facing "what I'm owed" surface — registrations + revenue per class / per month, sourced from `event_orders` (host-reads-own-event-orders RLS already exists). A `fetchHostEarnings` in `data.ts` + a `/settings/payouts` or club-host panel. Keeps the instructor out of the Stripe dashboard for the common case. **Gate to start:** M1 (real orders to summarize). **Gate to exit:** read-only summary + tests.

### M8 — Automated refund-on-cancel coupling (Track C, hardens step 8)
[club_events.md](club_events.md) P2: `refund_orders_for_instance`, buyer self-cancel per `refund_policy`, waitlist notify-to-pay, reconciliation sweep. Removes the manual-dashboard-refund risk that most threatens the non-technical instructor's reputation. **Gate to start:** M1 verified + P1 conversion signal. **Gate to exit:** P2 file list + idempotency/refund tests.

### M9 — Production payment go-live (Track A — THE gate)
Flip the marketplace on in production: live Stripe keys, the compliance sign-off complete, sub-processor list + Privacy Policy updated, DSAR export/delete paths cover `event_orders` + `instructor_payout_accounts`. **Gate to start:** M1 green + **owner + CISO + counsel sign-off**. **Strongly recommended before exposing to strangers' money, not a hard prerequisite:** M8 (automated refunds) — see the note below. **Gate to exit:** live, monitored, rollback documented.

> **M8 is a recommendation, not a hard gate on M9 — deliberately, to stay consistent with the spec.** [club_events.md](club_events.md#compliance-soc-2--govramp--privacy) is explicit that P1 ships **manual refunds via the Stripe dashboard** and is exposable in production gated only on the compliance sign-off + operator keys; P2 (automated refunds = our M8) is *deferred* and gated on a **P1 conversion signal**. A conversion signal can only come from P1 being live — so making M8 a hard prerequisite for M9 would deadlock (M9→signal→M8→M9). The honest sequencing: M9 *can* go live on manual refunds the moment M1 is green and sign-off lands, exactly as the spec allows; we **strongly recommend** standing up an operational manual-refund runbook (who refunds, SLA, where it's logged) at go-live and prioritising M8 immediately after, because a manual-only refund path is the biggest reputational risk to a non-technical instructor. Treat "live before M8" as a conscious, signed-off trade, not the default.

### M10 — Mobile register + manage (Track C / club_events P3)
Mobile register via web-checkout handoff (Custom Tab), payout summary read, receipt/refund emails ([email.md](email.md)). Step 10. **Gate to start:** M9 live. **Gate to exit:** mobile read+register, twin parity, no `BYPASS_PAYWALL` override.

**Suggested parallelization:** A (M0→M1) and B (M2→M3→M4) run concurrently. M9 (real money) *can* go live on the spec's manual-refund path once M1 is green and sign-off lands; we **strongly recommend** M8 (automated refunds) lands as fast as possible after, with a manual-refund runbook covering the interim, so we minimise the window in which we hold a stranger's money with only a dashboard refund path (see [M9](#milestone-sequence) and the inline note there). Content (B) can fully ship to free classes regardless of A's legal timeline — a yoga instructor can run a *free* class with a real authored sequence the day M4/M5 land.

## The compliance gate (load-bearing)

Per org policy for SOC 2 / GovRAMP-scoped changes and [club_events.md § Compliance](club_events.md#compliance-soc-2--govramp--privacy): **anything that moves real money (M9, and exposing M1's path in prod) requires owner + CISO + Security Analyst + counsel sign-off before it ships.** Non-negotiable items:

- **PCI:** Stripe-hosted Checkout + onboarding only → stays SAQ A. **Never build a custom card form.**
- **New sub-processor:** Stripe Connect (buyer + host financial/personal data) → sub-processor list + Privacy Policy (`/audit/third-party-data-flows`).
- **DSAR tension:** `event_orders` + `instructor_payout_accounts` enter the GDPR export (Art 20) + deletion (Art 17) paths — but financial/tax/AML retention can override erasure. **Counsel sets the retention term.**
- **GovRAMP:** payment flows are not GovRAMP-scoped and must not process government/regulated data — keep separated.
- **Funds integrity:** webhook is the sole, HMAC-verified, idempotent (on Stripe event id) writer of order status. Already built — verify in M1, don't regress.

Tracks B and C (content, attendance, earnings-read) carry **no** compliance gate — they touch no payments and no new sub-processor. Only the money milestones do.

## Cross-cutting requirements

Every code milestone honours the house rules, so "seamless" doesn't mean "sloppy":

- **Web-first** ([§24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)); **byte-identical mobile twin** ([§39](../architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)) for any Dart edit.
- **Parity pairs** for every pure helper (fee math, `expandSessionSteps`, `expandRoutineSteps`, `workoutDraftFromSession`); the `shared-library-syncer` agent after each.
- **Narrow union + CHECK lockstep** (`check_constraint_unions.mjs`) for `SessionItemKind` and any new status union.
- **i18n** in all six web locales + seven mobile ARBs for every new string (category/discipline already done; content-engine + attendance strings are new).
- **Schema codegen** — both generators after every migration; grow the Dart table list for the new tables ([schema_codegen.md](../architecture/schema_codegen.md)).
- **Layered resilience** — the follow-along runner's TTS/haptics are L4, wrapped per-effect; a cue failure never stops the timer.
- **Test hygiene** — review → unit → e2e per milestone ([conventions.md](../architecture/conventions.md#test-hygiene--review-then-unit-then-e2e)).
- **Category gating is defense-in-depth** — a class stays un-race-able at the data layer, not just hidden (already shipped; don't regress).

## Risks & open questions

1. **The go-live depends on people, not code.** M9 can stall indefinitely on sign-off; that's why Track B is structured to deliver value (free classes, real content) without it.
2. **`gym_sets.duration_s` (M2) touches the gym schema** — decide before M5 (the logging step) so timed holds log cleanly (`session_planner.md` Q1, which phrases it "before P2").
3. **Platform fee rate** (`platform_fee_bps`) — 0% to seed vs a real take-rate. Product + finance (`club_events.md` open Q1).
4. **Validation gate honesty.** M3/M4 are themselves the probe ("do instructors build content?"); if the signal is flat after M4, freeze Track B at authoring and don't build M5 execution.
5. **Attendance model (M6)** — a simple `attended`/`no_show` enum vs a check-in timestamp. Lean enum unless multi-check-in is needed.
6. **Connect account type** — Express (P1 assumption) vs Standard (`club_events.md` Q4).
7. **Is hosting paid events a Pro-host perk?** Ties into the paywall (`club_events.md` Q5).

## Rough sizing

Indicative, not committed (all gated):

| Milestone | Track | Size | Gate |
|---|---|---|---|
| M0 readiness pack | A | ~2-3 days (mostly people) | none |
| M1 verify rail in test mode | A | ~3-5 days | M0 keys |
| M2 gym_sets.duration_s | B | ~2-3 days | none |
| M3 gym routine P1 | B | per gym_programming.md P1 | owner |
| M4 session plan P1 | B | ~1.5-2 wk (per session_planner.md) | owner |
| M5 follow-along + log | B | ~2-3 wk (device-led) | M3/M4 signal |
| M6 attendance | C | ~3-5 days | none |
| M7 earnings summary | C | ~3-5 days | M1 |
| M8 automated refunds (P2) | C | ~2-3 wk | M1 + signal |
| M9 production go-live | A | ~1 wk + sign-off lead time | M1+sign-off (M8 recommended, not required) |
| M10 mobile register (P3) | C | ~2-3 wk | M9 |

## Docs to update as each milestone lands

- [roadmap.md](../product/roadmap.md) — add an "Instructor business" line; tick milestones as they merge.
- [parity.md](../product/parity.md) — flip cells per milestone (web ✓; mobile per M10).
- [club_events.md](club_events.md) / [gym_programming.md](gym_programming.md) / [session_planner.md](session_planner.md) — flip their status blocks as M1/M3/M4/M5/M8 land.
- [api_database.md](../backend/api_database.md) — the M2/M6 schema changes; the new content tables.
- [metadata.md](../backend/metadata.md) — the `gym_workouts.metadata` execution trios `routine_id` / `gym_step_results` / `gym_adherence` and `session_plan_id` / `session_step_results` / `session_adherence` registered at M5 (2026-06-11).
- [decisions.md](../architecture/decisions.md) — lift the proposed ADRs (typed/paid events; session_plans engine; this readiness sequencing if it warrants one) at landing.
- The GDPR posture + sub-processor list at M9 (counsel-reviewed).
- This file — keep the current-state matrix honest as milestones flip.
