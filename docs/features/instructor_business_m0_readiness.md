# M0 — instructor-business go-live readiness pack (Track A, no code)

> **Status: readiness pack (no code).** This is the M0 deliverable from [instructor_business.md](instructor_business.md) — the people-decisions and operator tasks that have to move *before* the payment rail can be exercised (M1) or exposed in production (M9). Nothing here ships code. Its job is to unblock Track A by assigning the sign-offs and requesting the test keys, in parallel with Track B (content engines) which carries no compliance gate.
>
> **This pack does not authorize turning money on.** Per org policy for SOC 2 / GovRAMP-scoped changes and [club_events.md § Compliance](club_events.md#compliance-soc-2--govramp--privacy), any flow that moves real money requires **owner + CISO + Security Analyst + counsel sign-off** before it ships. **Loop in the CISO and Security Analyst before acting on anything in this pack.**

**Contents:** [Where the rail stands](#where-the-rail-stands-verified) · [Sign-off checklist](#sign-off-checklist-the-gate) · [Compliance answers needed](#compliance-answers-needed) · [Verified gaps to close before prod-exposure](#verified-gaps-to-close-before-the-m1-path-is-prod-exposed) · [Operator task: Stripe Connect test keys](#operator-task-stripe-connect-test-keys-m0-exit) · [Open product decisions](#open-product-decisions) · [M0 exit criteria](#m0-exit-criteria)

## Where the rail stands (verified)

Confirmed by reading migrations + source on 2026-06-11. The payment **rail is built but dark** — no Stripe Connect keys exist, so the live path has never been exercised:

| Piece | State | Evidence |
|---|---|---|
| Payout onboarding | Built (web), live path dark | `instructor_payout_accounts` (`20261229_001_paid_events.sql`), `events-connect-onboard` |
| Pricing + orders schema | Built | `event_pricing`, `event_orders`, `event_attendees.order_id` (`20261229_001`) |
| Checkout (destination charge) | Built, charge unverified | `events-checkout` (`index.ts` + `.lib.ts` + `.lib.test.ts`) |
| Webhook (sole order-status writer) | Built, HMAC + idempotent | `stripe-events-webhook` — service-role-only, idempotent on Stripe event id |

The pure helpers (signature verify, idempotency CAS, fee math, capacity, sales window) have Deno tests in CI. The **live end-to-end is not exercisable in CI** — it needs operator-supplied test keys.

## Sign-off checklist (the gate)

Each row needs a named owner and a recorded decision. M1 (test-mode exercise) can begin on the operator keys alone; **the production-exposure gate (M9, and any prod exposure of the M1 path) requires all four sign-offs below.**

| # | Decision | Decider | Status |
|---|---|---|---|
| 1 | Approve PCI scope classification (Stripe-hosted Checkout + onboarding → SAQ A) and the IAP/marketplace classification | Owner | ☐ |
| 2 | Accept Stripe Connect as a new sub-processor (buyer + host financial/personal data) + the expanded DSAR footprint | CISO + Security Analyst | ☐ |
| 3 | Set the financial-record retention term for `event_orders` (tax/AML hold that can override GDPR Art 17 erasure) | Counsel | ☐ |
| 4 | Confirm payment flows stay out of GovRAMP scope (no government/regulated data through the marketplace) | CISO | ☐ |
| 5 | Sign off the go-live runbook: who refunds manually, the SLA, where refunds are logged (P1 ships manual refunds via the Stripe dashboard; automated refunds are M8) | Owner + CISO | ☐ |

## Compliance answers needed

These come straight from [club_events.md § Compliance](club_events.md#compliance-soc-2--govramp--privacy) and must be answered/documented before M9:

- **PCI:** Stripe-hosted Checkout + onboarding only → stays **SAQ A**. **Never build a custom card form** — hard constraint, escalates PCI scope. (No custom form exists today; don't regress.)
- **New sub-processor:** Stripe Connect → add to the sub-processor list + Privacy Policy, with the 30-day Art 28(2) notice. Run `/audit/third-party-data-flows` at M9.
- **DSAR tension:** `event_orders` + `instructor_payout_accounts` enter the GDPR export (Art 20) + deletion (Art 17) paths. Financial/tax/AML retention can override erasure — **counsel sets the term**, documented in the GDPR posture. Likely outcome: orders retained (anonymized) past account deletion.
- **GovRAMP:** payment flows are not GovRAMP-scoped and must not process government/regulated data — keep separated.
- **Funds integrity:** the webhook is the sole, HMAC-verified, idempotent (on Stripe event id) writer of order status. Built — **verify in M1, don't regress.**

## Verified gaps to close before the M1 path is prod-exposed

These are real, code-level gaps found on 2026-06-11. They are **M1/M9 work (gated)** — listed here so the sign-off owners know what "go-live" actually costs. Do **not** fix these as part of M0.

1. **DSAR export is incomplete.** `event_orders` and `instructor_payout_accounts` are **not** in `exportPersonalDataSpecs()` (`apps/job_worker/internal/supabase.go`). They must be added (subject to the counsel-set retention term) before prod exposure, and `personal_data_export_guard_test.go` must pass. Verify with `/audit/data-export-completeness`.
2. **Account-deletion path must cover both tables** (subject to the financial-retention override). Verify with `/audit/account-deletion-completeness`.
3. **Sub-processor not yet disclosed.** Stripe Connect must be added to the sub-processor list + changelog (30-day notice) and the Privacy Policy.

## Operator task: Stripe Connect test keys (M0 exit)

Request **test-mode** keys (never live keys at M0) and wire them locally per [local_testing_stubs.md § Stripe Connect](../testing/local_testing_stubs.md). This is what unblocks M1.

```bash
# apps/backend/.env.local
STRIPE_SECRET_KEY=sk_test_...            # Stripe dashboard → API keys (test mode)
STRIPE_CONNECT_CLIENT_ID=ca_...          # Stripe dashboard → Connect → Settings
STRIPE_EVENTS_WEBHOOK_SECRET=whsec_...   # from `stripe listen` (below) or the dashboard endpoint
STRIPE_EVENTS_ALLOWED_REDIRECTS=http://localhost:7777

# serve with keys loaded
cd apps/backend && supabase functions serve --env-file .env.local

# forward Stripe events to the webhook (prints the whsec_ to paste above, then restart)
stripe listen --forward-to http://127.0.0.1:54321/functions/v1/stripe-events-webhook

# the three handled event types
stripe trigger checkout.session.completed
stripe trigger checkout.session.expired
stripe trigger account.updated
```

These keys are confidential. Keep them out of shell config and out of any committed file — `.env.local` only.

## Open product decisions

Not compliance-gated, but they must be answered before M9 prices a real class:

| # | Question | Decider |
|---|---|---|
| Q1 | Platform fee rate (`platform_fee_bps`) — 0% to seed adoption vs a real take-rate | Product + Finance |
| Q4 | Connect account type — Express (P1 assumption, fastest) vs Standard | Product + CISO |
| Q5 | Is hosting paid events itself a Pro-host perk? (ties into the paywall) | Product |

## M0 exit criteria

M0 is done — and M1 can start — when:

- [ ] All five sign-off rows have a named decider assigned (decisions themselves can land during M1/M9; assignment is the M0 bar).
- [ ] The operator has requested and provisioned the three Stripe Connect **test** keys (`sk_test_` / `ca_` / `whsec_`).
- [ ] Counsel is engaged on the retention term (the answer can follow; engagement is the M0 bar).
- [ ] The CISO + Security Analyst are looped in on the sub-processor + DSAR footprint.

M0 has **no code gate** and **no dependency on Track B** — the content engines (M2/M3/M4) proceed in parallel and can ship free classes regardless of this pack's timeline.
