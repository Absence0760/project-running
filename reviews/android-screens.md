# Review: apps/mobile_android/lib/screens/

## Scope
- Files reviewed: 21 (`add_run_screen.dart`, `clubs_screen.dart`, `club_detail_screen.dart`, `dashboard_screen.dart`, `event_detail_screen.dart`, `explore_routes_screen.dart`, `home_screen.dart`, `import_screen.dart`, `onboarding_screen.dart`, `period_summary_screen.dart`, `plan_detail_screen.dart`, `plan_new_screen.dart`, `plans_screen.dart`, `route_detail_screen.dart`, `routes_screen.dart`, `run_detail_screen.dart`, `run_screen.dart`, `runs_screen.dart`, `settings_screen.dart`, `sign_in_screen.dart`, `workout_detail_screen.dart`)
- Focus: bugs (mounted guards, leaked resources, silent swallows), layered-resilience violations, web↔Android feature drift, code↔docs drift, paywall consistency, dead screens, test coverage gaps
- Reviewer confidence: high — every file read in full; cross-referenced against `docs/conventions.md`, `docs/run_recording.md`, `docs/workout_execution.md`, `docs/flows.md`, `docs/parity.md`, `docs/paywall.md`, `apps/mobile_android/CLAUDE.md`

---

## Priority: high

### H1. `_stop()` calls `setState` after three awaits with no `mounted` check
- **File(s)**: `apps/mobile_android/lib/screens/run_screen.dart:1059-1141`
- **Category**: bug
- **Problem**: `_stop()` awaits `_recorder!.stop()` (line 1060), `_hrSub?.cancel()` (line 1095), and `widget.runStore.clearInProgress()` (line 1136) before calling `setState` (line 1138) with no `if (!mounted) return` guard. If the widget is disposed mid-stop (e.g. app killed or the user somehow navigates away), this throws `setState() called after dispose()`.
- **Evidence**:
  ```dart
  Future<void> _stop() async {
    final raw = await _recorder!.stop();          // await 1
    // ... sync work ...
    await _hrSub?.cancel();                        // await 2
    // ...
    await widget.runStore.clearInProgress();       // await 3

    setState(() {                                  // NO mounted check
      _finishedRun = run;
      _state = _ScreenState.finished;
    });
  ```
- **Proposed change**:
  ```diff
     await widget.runStore.clearInProgress();
  +  if (!mounted) return;
     setState(() {
       _finishedRun = run;
       _state = _ScreenState.finished;
     });
  ```
- **Risk if applied**: None. The run is already saved locally at this point (`widget.runStore.save(run)` is called after the `setState`). Skipping the UI state transition on an unmounted widget is safe — the run has been persisted.
- **Verification**: `flutter test test/architecture_guards_test.dart`; manually force-kill the app while tapping Stop and confirm no `setState() called after dispose()` in logcat.

---

### H2. Delete button shown to every signed-in user on any route
- **File(s)**: `apps/mobile_android/lib/screens/route_detail_screen.dart:200-226`
- **Category**: bug
- **Problem**: `build()` declares `final isOwner = widget.apiClient?.userId != null` (line 200), which is `true` for any signed-in user. The public/private toggle is correctly gated on `isOwner`, but the Delete button at lines 221-226 is not gated at all — it renders for every user who views any route, including public routes they browsed via `ExploreRoutesScreen`. The correct guard is the class-level getter `_isOwner` (line 43) which also checks `widget.isOwner`.
- **Evidence**:
  ```dart
  // line 43 — correct getter, never used in build():
  bool get _isOwner => widget.isOwner && widget.apiClient?.userId != null;

  // line 200 — local that shadows it:
  final isOwner = widget.apiClient?.userId != null;

  // line 215 — toggle gated on local 'isOwner' (still wrong, but at least gated)
  if (isOwner)
    IconButton(icon: Icon(_isPublic ? Icons.public : Icons.public_off), ...)

  // lines 221-225 — delete button has NO guard:
  IconButton(
    icon: const Icon(Icons.delete_outline),
    onPressed: () => _confirmDelete(context),
  ),
  ```
- **Proposed change**:
  ```diff
  - final isOwner = widget.apiClient?.userId != null;
  + // Use the getter defined at class level: _isOwner checks widget.isOwner too.

    ...

  - if (isOwner)
  + if (_isOwner)
      IconButton(icon: Icon(_isPublic ? ...)),
  + if (_isOwner)
      IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(context),
      ),
  ```
- **Risk if applied**: Legitimate owners must have `widget.isOwner: true` passed from the call-site. `routes_screen.dart:200` already passes `isOwner: true`. `explore_routes_screen.dart:576-584` does NOT pass `isOwner`, which defaults to `false` — that is the correct and intended behaviour. No functional regression for owned routes.
- **Verification**: Launch the app, browse a public route via Explore Routes. Confirm the delete button is absent. Then view an owned route from the Routes tab — confirm delete is present.

---

### H3. `run_detail_screen._updateRun` calls `setState` without a `mounted` check
- **File(s)**: `apps/mobile_android/lib/screens/run_detail_screen.dart:294-295`
- **Category**: bug
- **Problem**: `_updateRun` awaits `widget.runStore.update(updated)` (line 294) then immediately calls `setState(() => run = updated)` (line 295) with no `if (!mounted) return`. If the detail screen is popped mid-edit (e.g. the user presses back while the save is in flight), this throws.
- **Evidence**:
  ```dart
  await widget.runStore.update(updated);
  setState(() => run = updated);   // no mounted guard
  ```
- **Proposed change**:
  ```diff
     await widget.runStore.update(updated);
  +  if (!mounted) return;
     setState(() => run = updated);
  ```
- **Risk if applied**: None. The run has already been saved to the store before the guard.
- **Verification**: `flutter test`; to manually reproduce the race, add a `Future.delayed` before `update()` and tap back during the delay.

---

### H4. `event_detail_screen._pickInstance` calls `setState` after three awaits with no `mounted` checks
- **File(s)**: `apps/mobile_android/lib/screens/event_detail_screen.dart:136-150`
- **Category**: bug
- **Problem**: `_pickInstance` calls `showDatePicker`, `showTimePicker`, and `_service.setEventInstance` sequentially, then calls `setState` updating `_event`. None of the `setState` calls are guarded by `if (!mounted) return`. If the screen is popped while a dialog is open and the user selects a date in the system picker (which can survive navigation), this throws.
- **Evidence**:
  ```dart
  Future<void> _pickInstance() async {
    final date = await showDatePicker(...);    // await 1
    if (date == null) return;
    final time = await showTimePicker(...);    // await 2
    if (time == null) return;
    final updated = await _service.setEventInstance(...);  // await 3
    setState(() => _event = updated);          // no mounted check
  }
  ```
- **Proposed change**:
  ```diff
     final updated = await _service.setEventInstance(...);
  +  if (!mounted) return;
     setState(() => _event = updated);
  ```
- **Risk if applied**: None. If the widget is gone, no UI update is needed.
- **Verification**: `flutter test`; navigate to an event detail screen, start the date picker, pop the parent screen from another route, then confirm in the picker — should not throw.

---

### H5. `_shareRun` silently swallows `makeRunPublic` errors
- **File(s)**: `apps/mobile_android/lib/screens/run_detail_screen.dart:1241-1255`
- **Category**: bug
- **Problem**: `catch (_) {}` with no `debugPrint`. This violates `docs/conventions.md` ("never swallow silently") and hides network errors when marking a run public before sharing. The user shares a link but the web share page may refuse to render the private run.
- **Evidence**:
  ```dart
  try {
    await api.makeRunPublic(run.id);
  } catch (_) {}     // silent swallow
  ```
- **Proposed change**:
  ```diff
  - } catch (_) {}
  + } catch (e) {
  +   debugPrint('makeRunPublic failed: $e');
  + }
  ```
- **Risk if applied**: None. The share sheet still opens; the error now appears in debug logs.
- **Verification**: `grep -r "catch (_)" apps/mobile_android/lib/` — this should be the only remaining instance after fixing. Confirm `flutter test` still passes.

---

### H6. `explore_routes_screen._loadPopularTags` silently swallows all errors
- **File(s)**: `apps/mobile_android/lib/screens/explore_routes_screen.dart:64-72`
- **Category**: bug
- **Problem**: `catch (_) {}` with no `debugPrint`. Same convention violation as H5.
- **Evidence**:
  ```dart
  try {
    final tags = await api.fetchPopularRouteTags();
    if (mounted) setState(() => _popularTags = tags);
  } catch (_) {}
  ```
- **Proposed change**:
  ```diff
  - } catch (_) {}
  + } catch (e) {
  +   debugPrint('fetchPopularRouteTags failed: $e');
  + }
  ```
- **Risk if applied**: None. Tags are cosmetic; degrading silently is fine, but the error must be logged.
- **Verification**: Same grep as H5.

---

## Priority: medium

### M1. Auto-pause setting subtitle is false — feature was removed from Android
- **File(s)**: `apps/mobile_android/lib/screens/settings_screen.dart:1076-1085`
- **Category**: inconsistency
- **Problem**: The `SwitchListTile` for "Auto-pause" has subtitle `'Stops the clock when you stop moving. Moving time is also recomputed from the GPS trace at save time.'`. Per `docs/run_recording.md` and the `CLAUDE.md` notes, auto-pause was removed from Android. The switch may persist in preferences but the recording stack no longer honours it, so the subtitle description is actively misleading.
- **Evidence**:
  ```dart
  SwitchListTile(
    title: const Text('Auto-pause'),
    subtitle: const Text(
      'Stops the clock when you stop moving. Moving time is also '
      'recomputed from the GPS trace at save time.',
    ),
  ```
- **Proposed change**: Either remove the tile entirely, or change the subtitle to `'Not available on this device.'` and disable the switch. If removal, also remove the `preferences.autoPause` read/write that this tile drives.
- **Risk if applied**: Users who had the switch toggled on will lose it. But since auto-pause does nothing in the recorder, the only effect is cleaning up dead UI.
- **Verification**: Confirm `run_recording.md` states auto-pause is removed; search `packages/run_recorder/lib/` for any remaining auto-pause logic that would need to be re-enabled before re-exposing the setting.

---

### M2. No sign-up path on Android — new users cannot register
- **File(s)**: `apps/mobile_android/lib/screens/sign_in_screen.dart` (entire file, 204 lines)
- **Category**: inconsistency
- **Problem**: The screen only handles sign-in (email+password, Google). There is no "Create account" route. `docs/parity.md` lists sign-up under "Auth" and marks it as implemented on web but does not explicitly mark Android — however `docs/flows.md` describes an Android sign-in sequence that implies accounts already exist. A user who installs the app cold with no account has no path forward except to use the web app first.
- **Evidence**: The file contains `_signInWithEmail`, `_signInWithGoogle`, and no `_signUp` or equivalent. The scaffold has no navigation to any registration screen.
- **Proposed change**: Add a "Create account" text button below the sign-in form that navigates to a new `SignUpScreen` (email + password + confirm password → `ApiClient.signUp`). Alternatively, add an inline toggle that flips the form between Sign in and Create account modes — the web implementation (`apps/web/src/routes/login/+page.svelte`) is the reference.
- **Risk if applied**: New screen needs widget tests; `ApiClient.signUp` must already exist (verify before implementing).
- **Verification**: Fresh install with no existing account — user should be able to create an account without touching the web app.

---

### M3. `plans_screen.dart` reads auth state via `Supabase.instance.client` instead of `ApiClient`
- **File(s)**: `apps/mobile_android/lib/screens/plans_screen.dart:77`
- **Category**: inconsistency
- **Problem**: `final signedIn = Supabase.instance.client.auth.currentUser != null;` bypasses the `ApiClient` abstraction. `docs/flows.md` and `CLAUDE.md` designate `ApiClient` as the single auth façade for all mobile screens. If `ApiClient` ever wraps or overrides the session (e.g. for test injection or session refresh), this bypass will diverge.
- **Evidence**:
  ```dart
  // plans_screen.dart:77
  final signedIn = Supabase.instance.client.auth.currentUser != null;
  ```
- **Proposed change**:
  ```diff
  - final signedIn = Supabase.instance.client.auth.currentUser != null;
  + final signedIn = widget.apiClient?.userId != null;
  ```
  This requires `plans_screen` to receive `ApiClient? apiClient` as a constructor parameter — check the call-site in `home_screen.dart` to add the prop.
- **Risk if applied**: `ApiClient.userId` returns the same value (`Supabase.instance.client.auth.currentUser?.id`) — semantically identical. The only risk is if the `PlansScreen` constructor call in `home_screen.dart` doesn't yet pass `apiClient`.
- **Verification**: `flutter test`; verify `PlansScreen` receives `apiClient` at its call-site in `home_screen.dart` and passes it through.

---

### M4. `_stop()` in `run_screen.dart` calls `widget.raceController?.submitResult` after `setState` with no mounted check
- **File(s)**: `apps/mobile_android/lib/screens/run_screen.dart:1173-1177`
- **Category**: bug
- **Problem**: After the `setState` that marks the run finished (line 1138), the code falls through to `api.saveRun` (guarded), then `widget.raceController?.submitResult` (line 1173) — which is an awaited async call with no `mounted` check before or after. If the widget disposes mid-sync this is benign (no setState follows), but `submitResult` can itself call back into `setState` via the `raceController` listener; this path is worth auditing.
- **Evidence**:
  ```dart
  await widget.raceController?.submitResult(
    runId: run.id,
    durationS: run.duration.inSeconds,
    distanceM: run.distanceMetres,
  );
  // no mounted check; end of _stop()
  ```
- **Proposed change**: Add `if (!mounted) return;` immediately before the `submitResult` call, consistent with the guarded `saveRun` block immediately above it.
  ```diff
  + if (!mounted) return;
    await widget.raceController?.submitResult(...)
  ```
- **Risk if applied**: If the widget is unmounted when a race is active, the finisher time won't be auto-submitted. The race director can still submit it manually. Acceptable trade-off versus a potential crash.
- **Verification**: End a run while a live race is active; confirm the leaderboard updates.

---

### M5. Test coverage — 10 screens with non-trivial state have no widget tests
- **File(s)**: `apps/mobile_android/test/` (entire directory)
- **Category**: dead-code / test gap
- **Problem**: `CLAUDE.md` lists existing widget tests only for `plan_calendar`, `workout_execution_band`, `workout_review_section`, and `fitness_card`. The following screens have non-trivial multi-async state, conditional UI, and/or permission flows with zero widget coverage:
  - `run_screen.dart` — the most complex file in the app; countdown, recording, finish states
  - `run_detail_screen.dart` — edit form, chart interactions, sharing
  - `sign_in_screen.dart` — auth flows
  - `settings_screen.dart` — preference toggles, dangerous actions (delete account)
  - `club_detail_screen.dart` — realtime feed, reply threads
  - `event_detail_screen.dart` — RSVP, race control (arm/fire/end)
  - `clubs_screen.dart` — search + tab switching
  - `explore_routes_screen.dart` — pagination, mode switching, filter chips
  - `import_screen.dart` — progress tracking, error reporting
  - `route_detail_screen.dart` — owner-gated actions (the H2 bug above was not caught by tests)
- **Proposed change**: Add a `test/screens/` subdirectory. Minimum viable coverage per screen:
  - A "renders without throwing" smoke test with mocked store/apiClient props
  - One test per major conditional: signed-in vs guest state, empty vs populated list, error state
  - One test per dangerous action (delete confirms before executing, owner guard on route detail)
  The H2 bug (delete shown to non-owners) would have been caught by a widget test that passes `isOwner: false` and asserts the delete button is absent.
- **Risk if applied**: None. Additive only.
- **Verification**: `flutter test test/screens/`

---

## Priority: low

### L1. `onboarding_screen.dart` has no `mounted` check after `Permission.location.request()`
- **File(s)**: `apps/mobile_android/lib/screens/onboarding_screen.dart:57-60`
- **Category**: bug
- **Problem**: `_next()` awaits two permission requests then calls `widget.onDone()` (a callback into `main.dart`) with no `mounted` check. This is low risk because onboarding is a one-shot screen and the callback doesn't call `setState`, but it's inconsistent with the pattern used everywhere else.
- **Evidence**:
  ```dart
  await Permission.location.request();
  await Permission.locationAlways.request();
  await widget.preferences.setOnboarded(true);
  widget.onDone();   // no mounted check
  ```
- **Proposed change**:
  ```diff
     await widget.preferences.setOnboarded(true);
  +  if (!mounted) return;
     widget.onDone();
  ```
- **Risk if applied**: None.
- **Verification**: `flutter test`

---

### L2. `explore_routes_screen._loadMore` swallows errors without logging
- **File(s)**: `apps/mobile_android/lib/screens/explore_routes_screen.dart:164-175`
- **Category**: bug
- **Problem**: The `catch (_)` block in `_loadMore` shows a snackbar but never calls `debugPrint`. Convention requires both.
- **Evidence**:
  ```dart
  } catch (_) {
    if (mounted) {
      setState(() { _loading = false; _hasMore = false; });
      ScaffoldMessenger.of(context).showSnackBar(...);
    }
  }
  ```
- **Proposed change**:
  ```diff
  - } catch (_) {
  + } catch (e, s) {
  +   debugPrint('ExploreRoutesScreen._loadMore failed: $e\n$s');
      if (mounted) {
  ```
- **Risk if applied**: None.
- **Verification**: Trigger a pagination load with no network.

---

### L3. `import_screen.dart` uses deprecated `withOpacity`
- **File(s)**: `apps/mobile_android/lib/screens/import_screen.dart:178,247`
- **Category**: inconsistency
- **Problem**: Two calls to `.withOpacity(0.15)` — flagged as `deprecated_member_use` by the analyzer. Per `CLAUDE.md` this is acknowledged tech debt, but worth noting here so a future deps-cleanup pass can include this file.
- **Evidence**:
  ```dart
  color: const Color(0xFFFC4C02).withOpacity(0.15),  // line 178
  color: theme.colorScheme.primary.withOpacity(0.15),  // line 247
  ```
- **Proposed change**: Replace with `.withValues(alpha: 0.15)`.
- **Risk if applied**: None — visual equivalence for alpha-only change.
- **Verification**: Visual inspection; `dart analyze` should go quiet on these two lines.

---

### L4. `routes_screen._fetchRemoteRoutes` missing `mounted` check in finally block
- **File(s)**: `apps/mobile_android/lib/screens/routes_screen.dart:55-69`
- **Category**: bug
- **Problem**: The `finally` block calls `setState` guarded by `if (mounted)` — this is correct. But the `catch (e)` block calls `debugPrint` only; no user-facing error state is set. If `api.getRoutes()` fails, the spinner disappears (via `finally`) but the routes list just stays empty with no explanation. Low severity since routes sync is a background operation and the list shows cached routes.
- **Evidence**:
  ```dart
  } catch (e) {
    debugPrint('Fetch routes failed: $e');
  } finally {
    if (mounted) setState(() => _syncing = false);
  }
  ```
- **Proposed change**: On catch, show a brief snackbar so the user knows sync failed (consistent with `clubs_screen.dart` and `explore_routes_screen.dart` which both surface errors):
  ```diff
   } catch (e) {
     debugPrint('Fetch routes failed: $e');
  +  if (mounted) {
  +    ScaffoldMessenger.of(context).showSnackBar(
  +      const SnackBar(content: Text('Could not sync routes — working offline')),
  +    );
  +  }
   } finally {
  ```
- **Risk if applied**: None.
- **Verification**: Disable network, tap the sync button on Routes tab — expect a snackbar instead of silent failure.

---

## Counts
H: 6  M: 5  L: 4
