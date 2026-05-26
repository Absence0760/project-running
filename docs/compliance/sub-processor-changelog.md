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
