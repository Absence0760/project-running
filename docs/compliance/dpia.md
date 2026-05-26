# Data Protection Impact Assessment (DPIA)

GDPR Art 35 requires a DPIA whenever a processing activity is "likely to result in a high risk to the rights and freedoms of natural persons". The EDPB's WP248 guidance flags live-location tracking and biometric/health processing as automatic DPIA triggers — this project does both.

**Status**: scaffold. Counsel must sign off before publishing the live build.

## Scope of this DPIA

| Processing activity | Why a DPIA is mandatory |
|---|---|
| **Live GPS recording** (`run_recorder` package → `runs.track_url`) | Continuous high-precision location data. WP248 explicit trigger. |
| **Heart rate from BLE chest strap** (`ble_heart_rate.dart`) | Biometric / health data; Art 9 special category. |
| **HealthKit / Health Connect import** | Inbound aggregation of health data from third-party fitness apps. |
| **AI Coach** (`apps/web/src/lib/coach/handler.ts`) | Automated processing of health data sent to a US sub-processor for response generation. |
| **Live spectator tracking** (`live_run_pings` → web `/live/[id]` + Go live-hub) | Real-time location data shared with public viewers. |
| **Public route + run sharing** (`is_public = true` rows) | Voluntary publication of historical location data. |

## Necessity + proportionality

For each activity, the standard test:

1. Is the personal data **necessary** for the stated purpose? — yes (location is the product).
2. Is it **proportionate**? — yes if the user explicitly initiates a recording. No if processing continues after the recording ends without consent (verify there is no background-location capture outside a recording session).
3. Is there a **less-intrusive alternative**? — for indoor / treadmill runs the app already supports a no-GPS mode; surface it more prominently.

## Risks identified

| Risk | Severity | Likelihood | Existing mitigation | Residual |
|---|---|---|---|---|
| Home / work address inferred from recurring run start points | **High** | High | Privacy zones (decisions §33) — non-owner viewers see clipped tracks via `clip_track_for_user` | Medium — user must enable + configure |
| Live spectator URL guessing reveals real-time location | High | Low | Anon JWT enforced server-side by `apps/job_worker/internal/livehub/auth.go` for non-public runs | Low |
| Coach prompts sent to Anthropic include HR + dob + gender | Medium | High | Anthropic DPA + no-training-on-customer-data commitment; data retained 30 days | Medium — disclose to user before use |
| Sentry breadcrumbs leak signed-URL tokens | Medium | Low | `apps/web/src/lib/sentry/redact.ts` strips signed URLs server- and client-side | Low |
| Apple Watch / Wear OS run continues recording when paired phone is locked | Medium | Medium | Foreground service notification + wakelock — user is aware via lock-screen UI | Low |
| Background-location permission granted on Android leaks beyond recording | High | Medium | `ACCESS_BACKGROUND_LOCATION` requested with rationale + Play Console justification | Medium — requires user education in the rationale dialog |
| Public route's `waypoints` reveal home start point | High | Medium | Privacy zones clip the path in public render | Medium — depends on user opt-in |
| Coach chat history (`coach_messages`) accumulates without auto-purge | Medium | High | 18-month purge via `purge-stale-coach-messages` cron (migration `20260922_001_data_retention_purge_jobs.sql`) | Low |
| Strava token leaked after account deletion | High | Low | Strava `/oauth/deauthorize` called from `delete-account/index.ts`; outcome recorded in `deletion_audit_log.third_party_outcomes.strava_deauth` (Art 17(2) evidence) | Low — call site confirmed + per-call outcome auditable |

## Mitigations to implement

Items the DPIA itself flags for action:

1. ~~**Coach-message retention**: add a `pg_cron` purge job; expose retention period in Privacy Policy + Settings.~~ **Done** — migration `20260922_001_data_retention_purge_jobs.sql` + privacy-policy entry, 2026-05-26.
2. ~~**Sentry user-opt-out toggle** in Settings → Privacy.~~ **Done** — web `/settings/preferences` has a "Privacy & telemetry" card bound to `consent.set()` (the existing cookie-banner consent primitive). Mobile twin mirrors via `Settings → Privacy → Send error reports`. The hooks (`hooks.server.ts` + `hooks.client.ts`) already gate Sentry on this state; the toggle adds the post-acceptance withdrawal path required by Art 7(3) / Art 21.
3. ~~**Live-ping retention**: confirm Postgres purge + Redis TTL both deliver the documented 24h window.~~ **Done** — `cleanup_stale_live_run_pings()` cron (`20260602_001_pg_cron_schedules.sql`); Go live-hub Redis TTL matches.
4. ~~**Strava deauthorize on delete**: verify the call site in `delete-account/index.ts`.~~ **Done** — confirmed; outcome now recorded in `deletion_audit_log.third_party_outcomes` (Art 17(2) evidence), migration `20260928_001_gdpr_dsar_closeouts.sql`.
5. **Privacy-zone first-run prompt**: on the first run that records within (e.g.) 200 m of the registered home location, prompt the user to configure a privacy zone.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Controller | TODO | TODO |
| DPO (if appointed) | TODO | TODO |
| Counsel | TODO | TODO |

A DPIA is a living document. Trigger re-review on:
- New personal-data column (use `/audit/data-export-completeness` to find).
- New sub-processor with health-data scope.
- A material change to recording behaviour (e.g. always-on background tracking).
