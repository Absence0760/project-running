# Sub-processor changelog

The list of processors that handle personal data on behalf of Threkir
evolves as we add features. Per GDPR Art 28(2), the data subject has
the right to object to a new sub-processor before it goes live. This
public changelog is the disclosure mechanism — every addition,
replacement, or material region change to a sub-processor must land
here at least **30 days before activation** in production.

If you object to a planned change you can:

1. Email `privacy@<your-domain>` ([live](mailto:privacy@<your-domain>))
   before the activation date listed below — we will pause the rollout
   while we discuss your case.
2. Delete your account via Settings → Account → Delete account before
   the activation date if no acceptable accommodation can be reached.

The current canonical sub-processor list lives at
[`sub-processors.md`](sub-processors.md). This file is the **history**;
the other file is the **snapshot**.

---

## 2026-05-26 — Initial publication

Baseline list as of 2026-05-26 — this is the snapshot any user who
created an account before today has tacitly accepted. Future entries
will diff against this baseline.

- **Supabase** — Postgres + Auth + Storage. Hosting region documented
  in [`sub-processors.md`](sub-processors.md). DPA:
  <https://supabase.com/legal/dpa>.
- **AWS** — S3 + CloudFront + Lambda + Route 53 (web hosting) +
  CloudWatch (logs). DPA: <https://aws.amazon.com/agreement/>.
- **Fly.io** — Go job worker + OSRM map-matching. Map-match jobs see
  GPS tracks transit. DPA: <https://fly.io/legal/dpa/>.
- **Anthropic** — primary AI Coach provider. DPA:
  <https://www.anthropic.com/legal/dpa>.
- **OpenAI** — fallback AI Coach provider when `COACH_PROVIDER=openai`.
  DPA: <https://openai.com/policies/data-processing-addendum>.
- **MapTiler** — base-map tiles + place search. IP + viewport per tile
  fetch. DPA: <https://www.maptiler.com/data-protection/>.
- **Open-Meteo** — elevation API for route building. Swiss controller
  (EU adequacy). Terms: <https://open-meteo.com/en/terms>.
- **Sentry** — error monitoring (US default). Consent-gated on the
  web; opt-out toggle in Settings (see roadmap). DPA:
  <https://sentry.io/legal/dpa/>.
- **RevenueCat** — subscription receipt validation. Forwards Stripe /
  App Store / Play receipts. DPA:
  <https://www.revenuecat.com/dpa/>.
- **Stripe / Apple IAP / Google Play Billing** — payment processors
  (downstream of RevenueCat). Stripe DPA:
  <https://stripe.com/legal/dpa>.
- **Strava / parkrun / Garmin Connect** — third-party integrations
  invoked only when the user explicitly connects them. OAuth scope is
  read-only for activity history.
- **Health Connect (Android) / HealthKit (iOS)** — on-device system
  services. Data lives on the device; we read only when the user opts
  in to the importer surface.
- **Google / Apple Sign-In** — federated identity providers (OAuth
  callback only; no data is shared with Google / Apple beyond what
  their respective sign-in flows require).
- **Supabase Auth email provider** — transactional emails (sign-up
  confirmations, password resets). Provider identity + region pinned
  in [`sub-processors.md`](sub-processors.md).

---

## 2026-06-09 — GraphHopper (self-hosted routing engine) — added (no new sub-processor)

* **What changes**: distance-targeted route-loop generation (`/api/routes/generate`, decisions §137) is served by a **self-hosted GraphHopper `round_trip` engine** running on our existing **Fly.io** infrastructure — the sibling of the self-hosted OSRM map-matcher. **No new third-party sub-processor is introduced**: the only processor in the chain is Fly.io, already disclosed since the 2026-05-26 baseline. Logged here for a complete audit trail, not as an Art 28(2) addition requiring the 30-day objection window.
* **Why**: the in-browser radius-bisect loop heuristic overshot the target distance on lopsided road networks; GraphHopper's `round_trip` hits the requested distance per engine call.
* **Activation date**: n/a — no new sub-processor, so no objection window applies. The feature ships on the normal release cadence.
* **Data categories affected**: route start lat/lng + target distance. **No data egress** — `GRAPHHOPPER_URL` is a server-only env (never `PUBLIC_`), so the browser never reaches the engine and the coordinates stay inside our infra (same posture as the self-hosted OSRM map-matcher).
* **Region**: `lhr` (London) — same Fly.io primary region as OSRM + the Go worker.
* **DPA**: Covered by the existing Fly.io DPA (<https://fly.io/legal/dpa/>); GraphHopper itself processes nothing on our behalf — we self-host it.
* **Opt-out path**: n/a — server-side route building, no personal-data egress; when the engine is unconfigured/down the client falls back to the in-browser OSRM heuristic.

---

## 2026-06-10 — graph_cycle map sidecar (self-hosted routing engine) — added (no new sub-processor)

* **What changes**: the v3 graph-cycle loop generator (`/api/routes/generate`, decisions §137) is served by a **self-hosted Go map sidecar** (`apps/graph_cycle`) running on our existing **Fly.io** infrastructure — a sibling of the self-hosted OSRM map-matcher + the GraphHopper engine. It parses the same regional OSM PBF into an in-memory foot graph and searches it for clean loops; `handleGenerate` tries it ahead of GraphHopper `round_trip`. **No new third-party sub-processor is introduced**: the only processor in the chain is Fly.io, disclosed since the 2026-05-26 baseline. Logged for a complete audit trail, not as an Art 28(2) addition requiring the 30-day objection window.
* **Why**: geometric generators (the retired v2 polygon path + `round_trip`) can't trace the neighbourhood loop on irregular street grids; the sidecar searches the real foot graph and finds it (decisions §137 amendment).
* **Activation date**: n/a — no new sub-processor, so no objection window applies. Ships on the normal release cadence once deployed.
* **Data categories affected**: route start lat/lng + target distance. **No data egress** — `GRAPH_CYCLE_URL` is a server-only env (never `PUBLIC_`), so the browser never reaches the sidecar and the coordinates stay inside our infra (same posture as the self-hosted OSRM + GraphHopper engines).
* **Region**: `lhr` (London) — same Fly.io primary region as OSRM, GraphHopper, + the Go worker.
* **DPA**: Covered by the existing Fly.io DPA (<https://fly.io/legal/dpa/>); the sidecar is our own code self-hosted — it processes nothing on our behalf as a third party.
* **Opt-out path**: n/a — server-side route building, no personal-data egress; when the sidecar is unconfigured/down the handler falls back to GraphHopper round_trip, then the in-browser OSRM heuristic.

---

## Template for future entries

```
## YYYY-MM-DD — <Provider name> — <added | removed | replaced | region-change>

* **What changes**: <one-line description>
* **Why**: <product / cost / compliance reason>
* **Activation date**: <YYYY-MM-DD, at least 30 days after this entry>
* **Data categories affected**: <run tracks / chat history / push tokens / ...>
* **Region**: <provider region>
* **DPA**: <URL>
* **Opt-out path**: <feature toggle / account deletion / "no opt-out — strictly necessary">
```

---

Last updated 2026-05-26. The audit trail of edits to this file is the
git history of `docs/compliance/sub-processor-changelog.md`. If you
need a notarised log of changes prior to a specific date, email
`privacy@<your-domain>`.
