# watch_garmin

A **Connect IQ data field** (Monkey C) for existing Garmin watches that shows
**grade-adjusted pace (GAP)** on the native run-recording screen.

This is the scaffold for **strategic Vector 1** of the custom-watch strategy:
reach Garmin's millions of installed watches through Garmin's own marketplace,
at near-zero risk, to test whether our running-software UX beats Garmin's
first-party UI. It is **research-tier** — see
[`apps/watch_garmin/CLAUDE.md`](CLAUDE.md),
[docs/custom_watch/roadmap.md § Vector 1](../../docs/custom_watch/roadmap.md#vector-1--connect-iq-app-or-data-field-for-existing-garmin-owners),
and [decisions.md § 87](../../docs/architecture/decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware).

## Why a data field (not a full watch app)

Connect IQ has four app types. A **data field** is the cheapest: it injects
ONE metric into Garmin's *native* activity screen. Garmin keeps owning the
GPS, the recording, the FIT file, and the sync. We just add a cell. No Garmin
business approval, no NDA, no OAuth — it ships through the Connect IQ Store
like any third-party app.

The full **watch app** shape (our own recording UI + direct Supabase sync) is
the real "is our UX better" test, but it's months of work and a much bigger
sandbox fight (memory ceiling, no mid-activity network without a phone
tether). We start with the field, measure install demand, then decide.

## What GAP is

Grade-adjusted pace = the flat-ground pace equivalent to your current effort
on the current grade. Raw pace lies on hills; GAP corrects it using the
**Minetti et al. 2002** metabolic-cost-of-gradient model
(`source/GradeAdjustedPaceView.mc`). This is the headline thing trail/ultra
runners want that Garmin surfaces poorly.

> Note: GAP is not a web feature yet. On this research-tier surface it's a
> toolchain demo; shipping it to users is gated on it existing on web first
> (followup tracked in [docs/product/followups.md](../../docs/product/followups.md)).

## How sync would work later

A data field can't own sync. If this becomes a watch app, completed runs would
either (a) be handed to Garmin Connect and pulled in via our existing
**Garmin bulk-import / OAuth path** ([parity.md](../../docs/product/parity.md)),
or (b) POST directly to a Supabase Edge Function via
`Communications.makeWebRequest` while the phone is tethered — which requires
adding the `Communications` permission and a phone-issued token (there is no
OAuth-on-watch). The two Garmin efforts are complementary, not duplicative.

## Build & run

See [local_testing.md](local_testing.md). Short version: install the Connect IQ
SDK via the SDK Manager, then `monkeyc` to build a `.prg` and `monkeydo` to run
it in the simulator, or sideload to a real watch.
