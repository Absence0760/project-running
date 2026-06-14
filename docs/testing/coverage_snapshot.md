# Coverage snapshot

**Snapshot, not measured line coverage.** Each percentage answers: "would CI catch a regression in this surface before merge?" Last refreshed 2026-05-19 — the percentages are point-in-time and stale as of that date; the suite has grown roughly 2-3x since (see [test_inventory.md](test_inventory.md) for live aggregate counts). The hard assert counts cited in this chart (e.g. the architecture-guard count) are corrected on edit but the percentages are not re-measured.

Two charts: roll-up by area, then per-feature. The roll-up averages the features inside each area; both views use the same underlying numbers.

## By area

```
                                  0%      25%     50%     75%    100%
                                  ├───────┼───────┼───────┼───────┤
Mobile twin parity (CI guard)     ███████████████████░  95%
Go worker (background + http)     █████████████████░░░  85%
Database (pgtap RLS / RPCs)       ████████████████░░░░  80%
Web app (frontend, Playwright)    ████████████████░░░░  80%
Backend Edge Functions            ███████████████░░░░░  75%
Maps + matching pipeline          ███████████████░░░░░  75%
Mobile (Android, Flutter)         ██████████████░░░░░░  70%
Mobile (iOS, Flutter twin)        █████████████░░░░░░░  65%
Compliance posture                ███████████░░░░░░░░░  55%
Wear OS (Kotlin)                  ██████████░░░░░░░░░░  50%
Integrations (3rd-party)          ███████░░░░░░░░░░░░░  35%
watchOS (Swift)                   █████░░░░░░░░░░░░░░░  25%
```

## By feature

```
                                  0%      25%     50%     75%    100%
                                  ├───────┼───────┼───────┼───────┤

AUTH + IDENTITY
  Email signup (with age gate)    ██████████████████░░  90%
  Email sign-in                   ██████████████████░░  90%
  Password reset (Mailpit flow)   █████████████████░░░  85%
  Session refresh / auth walls    █████████████████░░░  85%
  Google OAuth                    ████░░░░░░░░░░░░░░░░  20%
  Apple OAuth                     ██░░░░░░░░░░░░░░░░░░  10%

RECORDING + RUN PERSISTENCE
  Architecture guards (145 asserts)██████████████████░  95%
  LocalRunStore persistence       █████████████████░░░  85%
  run_stats helpers               █████████████████░░░  85%
  Live run screen widget (idle)   █████████████████░░░  85%
  Run state machine + GPS filters ████████████████░░░░  80%
  BLE chest-strap HR              ███████████████░░░░░  75%
  Crash-safe persistence          ██████████████░░░░░░  70%
  Wear OS feature parity          █████████░░░░░░░░░░░  45%
  watchOS recording flow          ███░░░░░░░░░░░░░░░░░  15%

RUNS (web)
  Kudos / comments / engagement   █████████████████░░░  85%
  List / detail / new / cascade   █████████████████░░░  85%
  Privacy-zone clipping           █████████████████░░░  85%
  Track preview + decorations     ████████████████░░░░  80%
  Pace segments / heatmap         ████████████████░░░░  80%
  HR zones                        ███████████████░░░░░  75%
  Run photos                      ███████████████░░░░░  75%

ROUTES
  Heatmap                         ██████████████████░░  92%
  Segments + leaderboards         ██████████████████░░  92%
  Public/private toggle + share   ███████████████░░░░░  75%
  Library / detail / import       ██████████████░░░░░░  70%
  Route builder (OSRM)            █████████████░░░░░░░  65%

TRAINING PLANS
  Calendar                        ██████████████████░░  92%
  Workout runner state machine    ██████████████████░░  92%
  VDOT + Riegel (TS↔Dart parity)  ██████████████████░░  90%
  Wizard / week grid / editor     ██████████████████░░  90%
  Adherence + workout review      ██████████████░░░░░░  70%

CLUBS / EVENTS / SOCIAL
  Activity feed                   ██████████████████░░  92%
  Profile (/u/[id])               ██████████████████░░  92%
  Race control (arm/start/end)    ██████████████████░░  92%
  Clubs CRUD + posts + invites    ██████████████████░░  90%
  Events (one-off + recurring)    █████████████████░░░  85%

AI COACH
  Chat surface mount              ██████████████████░░  92%
  SSE streaming (mocked)          ██████████████████░░  92%
  Paywall gating                  ████████████████░░░░  80%
  429 daily-cap path              ███████████████░░░░░  75%
  Real Anthropic response         █████████░░░░░░░░░░░  45%

LIVE SPECTATOR
  Mobile spectator screen         ██████████████████░░  92%
  Multi-client realtime delivery  ██████████████████░░  92%
  Go live-hub (auth/privacy/Redis)█████████████████░░░  85%
  Web /live/[id] render           ██████████████░░░░░░  70%

SETTINGS
  Account / preferences / devices █████████████████░░░  85%
  Integrations tab                ██████████████████░░  92%
  Privacy zones picker            ████████████████░░░░  80%
  Pro upgrade (currency-localised)████████████████░░░░  80%
  Data export (Go endpoint)       ███████████████░░░░░  75%
  Restore backup                  ██████████████░░░░░░  70%

INTEGRATIONS
  Strava ZIP import               ███████████████░░░░░  75%
  parkrun athlete-number          ████████░░░░░░░░░░░░  40%
  Health Connect (Android)        ████████░░░░░░░░░░░░  40%
  Stripe + RevenueCat paywall     ████████░░░░░░░░░░░░  40%
  HealthKit (iOS)                 ██████░░░░░░░░░░░░░░  30%
  Strava live OAuth + webhook     ██████░░░░░░░░░░░░░░  30%
  Apple IAP / Google Play Billing ████░░░░░░░░░░░░░░░░  20%
  Garmin Connect                  █░░░░░░░░░░░░░░░░░░░   5%

MAPS + MATCHING
  Privacy-zone clipping RPC       ██████████████████░░  90%
  OSRM matcher (Go)               ████████████████░░░░  80%
  Run-match pipeline (jobs queue) ████████████████░░░░  80%
  MapTiler tile render            ████████████░░░░░░░░  60%

BACKEND
  EF pre-side-effect guards (5)   ██████████████████░░  92%
  Schema codegen drift detector   ██████████████████░░  90%
  Go job worker                   █████████████████░░░  85%
  EF pure helpers                 ████████████████░░░░  80%
  pgtap RLS suite                 ████████████████░░░░  80%
  EF handler envelopes (auth)     █████████████░░░░░░░  65%

WEB PUBLIC PAGES
  /recap/[year]                   ██████████████████░░  90%
  Legal pages                     █████████████████░░░  85%
  Sitemap + robots.txt            █████████████████░░░  85%
  Landing                         ████████████████░░░░  80%
  /share/run, /share/route        ████████████████░░░░  80%
  /compare, /guided               ██████████████░░░░░░  70%

CROSS-CUTTING + COMPLIANCE
  Mobile twin byte-parity         ███████████████████░  95%
  Age gate (GDPR Art 8)           ██████████████████░░  90%
  Dev/prod isolation guard        ██████████████████░░  90%
  Cookie consent + Sentry gate    █████████████████░░░  85%
  Currency localisation           █████████████████░░░  85%
  Paywall gating (server-side)    ████████████████░░░░  80%
  Compliance audits (advisory)    ██████░░░░░░░░░░░░░░  30%
  Compliance docs (DPIA, etc.)    ████░░░░░░░░░░░░░░░░  20%
```

## What's blocked, what's addressable

| Area | Blocker | Unblocks |
|---|---|---|
| Google / Apple OAuth | Need Google Cloud + Apple Developer creds | ~70 points across two rows |
| Garmin Connect | Developer-program approval (multi-week) | One row from 5% → ~60% |
| Strava live OAuth | Strava developer creds | One row from 30% → ~80% |
| Stripe + RevenueCat | Sandbox keys (~1 day setup) | Two rows from 20–40% → ~80% |
| Health Connect / HealthKit | Real-device + bench setup | Two rows; mock-only without |
| Mobile e2e (Android) | `flutter integration_test` in CI (~1 day infra) | All "no integration_test" notes across mobile features |
| Mobile e2e (iOS) | macOS runner (~$70/mo) | iOS twin parity to mobile rows |
| watchOS automation | macOS runner + Swift test wiring | watchOS row from 25% → ~50% |
| Wear OS e2e | Emulator-driven test surface (no widget-test on Wear today) | Wear OS row from 50% → ~70% |
| Compliance docs | Counsel review + product TODOs | Two compliance rows |

Everything else (Playwright deepening, more pgtap, mocked-API specs, helper unit tests) is in-code addressable without external dependencies.
