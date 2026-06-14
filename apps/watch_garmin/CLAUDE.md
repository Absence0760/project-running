# watch_garmin — AI session notes

> **Research-tier, strategic Vector 1 spike.** Native **Monkey C / Connect IQ**
> app for *existing Garmin watches* — **not** Flutter, **not** a shipping
> product yet, and **not** the own-hardware firmware (that's
> [`apps/custom_watch/`](../custom_watch/CLAUDE.md), Rust + Embassy). This
> exists to test one hypothesis cheaply: *is our running-software UX
> meaningfully better than Garmin's hostile first-party UI?* See
> [../../docs/custom_watch/roadmap.md § Vector 1](../../docs/custom_watch/roadmap.md#vector-1--connect-iq-app-or-data-field-for-existing-garmin-owners)
> and [decisions.md § 87](../../docs/architecture/decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware).

## What this is (and is not)

A Connect IQ **data field**: it injects ONE metric — grade-adjusted pace —
into Garmin's *native* run-recording screen. Garmin still owns the activity,
the GPS, the FIT file, and the sync to Garmin Connect. We add a cell. This is
the cheapest, near-zero-risk shape of Vector 1 (distributed via Garmin's own
Connect IQ Store, no Garmin business approval needed).

The other Connect IQ shapes, deliberately out of scope for this spike:

- **Watch app** — takes over the screen, owns its own recording UI + data
  screens, and could POST runs directly to a Supabase Edge Function. This is
  the real "our UX vs Garmin's" test but is months of work; revisit only once
  the data field proves install demand.
- **Widget / glance** — read-only companion surface.

## Scope — read before writing code

This is research-tier and therefore **exempt from the web-first rule** the
same way `apps/custom_watch/` is: it's a strategic probe, not a parity client,
so it does not appear in [parity.md](../../docs/product/parity.md). That
exemption is narrow — it covers *proving the platform*, not pioneering product
features. **Any metric this field ships to real users must first exist as a
concept on web** (grade-adjusted pace is not on web yet — tracked as a
followup, see [followups.md](../../docs/product/followups.md)). Until then GAP
here is a demo of the toolchain, not a launched feature.

**Build here:**

- Connect IQ data fields / widgets / (eventually) a watch app in Monkey C.
- Pure on-watch computation over `Activity.Info` (speed, altitude, distance,
  HR, cadence).
- If/when this grows a sync path: opportunistic `Communications.makeWebRequest`
  to a Supabase Edge Function while the phone is tethered. That needs the
  `Communications` permission added to `manifest.xml` and a token handed from
  the phone app — there is no OAuth-on-watch.

**Don't build here:**

- A pocket-app mirror. Same wrist-only rule as `watch_wear` / `watch_ios`.
- Shared code with Dart/TS. Monkey C can't import them; any logic copied here
  (the Minetti GAP model in `GradeAdjustedPaceView.mc` is the first instance)
  becomes a **third** hand-maintained copy. Keep such copies tiny and comment
  the source-of-truth so a future schema/algorithm change knows to update it.
- Anything that assumes network access mid-activity. CIQ apps are sandboxed:
  no raw sockets, web requests only via the phone tether or Wi-Fi devices, and
  a per-device memory ceiling in the tens-to-low-hundreds of KB.

## Layout

```
manifest.xml                         app id, type=datafield, device list, perms
monkey.jungle                        build config (source + source-test paths, `test` excludeAnnotation)
resources/strings/strings.xml        AppName + field label
resources/drawables/                 launcher_icon.png + drawables.xml
source/RunGarminApp.mc               AppBase entry (getInitialView → the field)
source/GradeAdjustedPaceView.mc      SimpleDataField: Minetti-model GAP
source-test/GradeAdjustedPaceTest.mc CIQ (:test) unit tests for the GAP model
```

The Minetti GAP math (`costAtGrade` / `gradeFactor` / `gapPace` / `formatPace`)
is exposed as **static** functions so `source-test/GradeAdjustedPaceTest.mc` can
unit-test it host-pure (no `Activity.Info` / simulator sensor feed). Expected
values are pinned to the TS/Dart parity oracle (`grade_adjusted_pace.ts` +
`grade_adjusted_pace.dart`); keep all three in lockstep. Run via
`monkeyc --unit-test` + `monkeydo … -t` (see [local_testing.md § 6](local_testing.md)).
These were authored but **not executed** — the Connect IQ SDK is not installed
on the dev workstation yet.

## Toolchain

Not part of Melos, npm, or Gradle. Build/test is the **Connect IQ SDK**
(`monkeyc` / `monkeydo`) + the CIQ simulator, driven from VS Code with the
Garmin "Monkey C" extension. Full setup + simulator + sideload steps in
[local_testing.md](local_testing.md). The SDK is not installed on this
workstation yet — `local_testing.md` covers getting it via the SDK Manager
(no dnf/flatpak package exists; it's a vendor download).
