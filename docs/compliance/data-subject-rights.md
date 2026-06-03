# Data-subject rights — handling SOP

How each GDPR data-subject right is satisfied, and the operator runbook
for the two rights that have **no self-service product surface** today
(Art 18 restriction, Art 21 objection). Surfaced by audit-findings
2026-05-30 Medium.

**Status**: scaffold. Self-service paths (access/export/erasure/
rectification) are implemented in code; the Art 18/21 manual SOP below is
operator process, not a legal opinion. Counsel review before EU launch.

## Rights map

| Right | Article | How it's satisfied | Surface |
|---|---|---|---|
| Access / copy | 15 | Full export (every personal-data table + run-photo bytes + tracks) | Settings → "Export data" → `data-export` (Go worker `/v1/export`) |
| Portability | 20 | Same machine-readable export (JSON + GPX + zip) | as above |
| Rectification | 16 | Profile + preference edits; run title/notes edit | Settings, run detail |
| Erasure | 17 | Account deletion (cascade + Storage drain + third-party deauth + audit log) | Settings → Delete account (email re-entry challenge) → `delete-account` EF |
| Restriction | 18 | **No self-service toggle** — manual SOP below | operator |
| Objection | 21 | **No self-service toggle** — manual SOP below | operator |
| Withdraw consent | 7(3) | Disconnect integrations; **AI-coach consent is self-service withdrawable** (Settings → Account → AI Coach consent → Withdraw, backed by the `withdraw_coach_consent()` RPC — clears `coach_consent_at`, after which the coach handler's 403 gate re-blocks the Coach); telemetry opt-out in Settings | Settings |

## Art 18 (restriction) + Art 21 (objection) — operator SOP

Until a "pause processing" product toggle exists, restriction/objection
requests are handled manually:

1. **Intake.** Request arrives at `privacy@threkir.com`. Log it (date,
   user id, right invoked, scope) in the breach/rights register.
2. **Verify identity** — match the requesting email to the account email;
   if unsure, send a confirmation link to the account email.
3. **Scope the restriction.** Most Art 18/21 requests target a specific
   processing purpose. The realistic levers today:
   - **Stop the AI-coach processing** — the user can do this themselves:
     Settings → Account → AI Coach consent → Withdraw calls
     `withdraw_coach_consent()`, which clears `coach_consent_at`; the coach
     request handler then returns 403 until they re-consent. No operator
     action needed. Their prompts are not retained by us (provider-side
     ~30d, see [retention.md](retention.md)).
   - **Stop social/feed processing** — set the account's runs to private
     (`is_public = false`) and remove follow edges if requested.
   - **Stop marketing/telemetry** — flip the Sentry/telemetry opt-out.
   - **Full processing freeze** — if a true Art 18 "store but don't
     process" is required and no narrower lever fits, the conservative
     action is to suspend the account (block sign-in) while retaining the
     data, pending resolution. There is no automated suspend flag yet —
     this is a manual DB action by an operator with service-role access.
4. **Confirm** to the data subject within one month (Art 12(3)),
   describing what was restricted.
5. **Lift** the restriction only on the data subject's instruction or
   when the legal ground resolves; log the lift.

**Follow-up (tracked, not in this doc):** a first-class "pause my data
processing" account toggle + an `account_status` suspended flag would make
Art 18/21 self-service. Until then this manual SOP is the control.

## Records of Processing Activities (Art 30)

A single consolidated RoPA is **not yet assembled** — the inputs are
split across [sub-processors.md](sub-processors.md) (recipients/transfers),
[retention.md](retention.md) (storage periods), and [dpia.md](dpia.md)
(purposes + risk for the high-risk processing). Assembling `ropa.md` from
these is a documentation task for the controller-of-record before EU
launch; it needs the legal-entity identity (the same blocker as the
Privacy Policy controller field) so it isn't fabricated here.
