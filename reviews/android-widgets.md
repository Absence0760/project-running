# Review: apps/mobile_android/lib/widgets/

13 widgets across the Android app's shared widget layer. Three real bugs; eight widgets with zero test coverage; three redundant pace formatters when one already exists in `training.dart`.

## Scope
- Files reviewed: 13 (`collapsible_panel.dart`, `error_state.dart`, `fitness_card.dart`, `goal_editor_sheet.dart`, `live_run_map.dart`, `pace_segments.dart`, `plan_calendar.dart`, `run_share_card.dart`, `todays_workout_card.dart`, `upcoming_event_card.dart`, `workout_edit_sheet.dart`, `workout_execution_band.dart`, `workout_review_section.dart`)
- Focus: bugs, reusability fit, layered-resilience violations, test coverage, dead widgets, conventions drift, ui_kit drift
- Reviewer confidence: high — all files read in full; all callers cross-referenced

---

## High

### H1. `_shareFile` has no error handling — any throw is unhandled
- **File(s)**: `apps/mobile_android/lib/widgets/run_share_card.dart:102-119`
- **Category**: bug
- **Problem**: `_shareImage` wraps its entire body in `try/catch` and shows a snackbar on failure. `_shareFile` — which writes to disk and calls `Share.shareXFiles` — has no try/catch at all. A disk-full error, a permission denial from `getTemporaryDirectory`, or a `share_plus` exception propagates to the unhandled-exception handler. In release builds this silently crashes; in debug it shows the red screen inside the sheet.
- **Evidence**:
  ```dart
  Future<void> _shareFile(String format) async {
    final tmp = await getTemporaryDirectory();
    // ... file writes and Share.shareXFiles ...
    await Share.shareXFiles([XFile(file.path)], text: _caption);
    // no try/catch; no error feedback
  }
  ```
- **Proposed change**:
  ```diff
  Future<void> _shareFile(String format) async {
  + try {
      final tmp = await getTemporaryDirectory();
      final run = widget.run;
      final title = widget.title;
      File file;
      switch (format) {
        case 'tcx':
          file = File('${tmp.path}/run-${run.id}.tcx');
          await file.writeAsString(_runToTcx(run, title));
        case 'fit':
          file = File('${tmp.path}/run-${run.id}.fit');
          await file.writeAsBytes(_runToFitBytes(run));
        default:
          file = File('${tmp.path}/run-${run.id}.gpx');
          await file.writeAsString(_runToGpx(run, title));
      }
      await Share.shareXFiles([XFile(file.path)], text: _caption);
  + } catch (e) {
  +   debugPrint('Failed to export run file: $e');
  +   if (mounted) {
  +     ScaffoldMessenger.of(context).showSnackBar(
  +       const SnackBar(content: Text('Could not export file')),
  +     );
  +   }
  + }
  }
  ```
- **Risk if applied**: None — mirrors the existing `_shareImage` catch block exactly.
- **Verification**: `flutter test` passes. Manual test: attempt GPX export with Supabase offline; confirm snackbar appears instead of crash.

---

### H2. Re-center FAB in `LiveRunMap` has no accessibility label
- **File(s)**: `apps/mobile_android/lib/widgets/live_run_map.dart:457-465`
- **Category**: bug (accessibility hole on a primary CTA)
- **Problem**: The "Re-center on runner" `FloatingActionButton.small` shows only `Icons.my_location` with no `tooltip` and no `semanticLabel`. TalkBack announces this as "Button", giving blind runners no indication of what the button does. This is a primary CTA during recording.
- **Evidence**:
  ```dart
  child: FloatingActionButton.small(
    heroTag: 'recenter',
    onPressed: () { ... },
    child: const Icon(Icons.my_location),  // no tooltip, no semanticLabel
  ),
  ```
- **Proposed change**:
  ```diff
  child: FloatingActionButton.small(
    heroTag: 'recenter',
  + tooltip: 'Re-centre on my location',
    onPressed: () { ... },
    child: const Icon(Icons.my_location),
  ),
  ```
- **Risk if applied**: None.
- **Verification**: Enable TalkBack; navigate to run screen; pan map; confirm button is announced as "Re-centre on my location, Button".

---

### H3. `CollapsiblePanel` drag handle has no semantic action
- **File(s)**: `apps/mobile_android/lib/widgets/collapsible_panel.dart:61-78`
- **Category**: bug (accessibility hole on a primary CTA)
- **Problem**: The drag handle is a bare `GestureDetector` wrapping a `SizedBox`. TalkBack sees a touch target with no role, no label, and no action. The panel is the primary stats panel on `run_screen` — the only way for a blind runner to access detailed stats during a run.
- **Evidence**:
  ```dart
  GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _toggle,
    onVerticalDragEnd: _onVerticalDragEnd,
    child: SizedBox(
      height: 28,
      child: Center(child: Container(width: 36, height: 4, ...)),
    ),
  ),
  ```
- **Proposed change**:
  ```diff
  - GestureDetector(
  -   behavior: HitTestBehavior.opaque,
  -   onTap: _toggle,
  -   onVerticalDragEnd: _onVerticalDragEnd,
  -   child: SizedBox( ... ),
  - ),
  + Semantics(
  +   label: _expanded ? 'Collapse stats panel' : 'Expand stats panel',
  +   button: true,
  +   child: GestureDetector(
  +     behavior: HitTestBehavior.opaque,
  +     onTap: _toggle,
  +     onVerticalDragEnd: _onVerticalDragEnd,
  +     child: SizedBox( ... ),
  +   ),
  + ),
  ```
  Because `_expanded` is state, the `Semantics` label updates automatically on rebuild.
- **Risk if applied**: None.
- **Verification**: Enable TalkBack; open run screen; confirm panel handle is announced as "Expand stats panel, Button" / "Collapse stats panel, Button" before and after tap.

---

## Medium

### M1. Eight stateful widgets have zero widget test coverage
- **File(s)**:
  - `apps/mobile_android/lib/widgets/collapsible_panel.dart`
  - `apps/mobile_android/lib/widgets/error_state.dart`
  - `apps/mobile_android/lib/widgets/goal_editor_sheet.dart`
  - `apps/mobile_android/lib/widgets/live_run_map.dart`
  - `apps/mobile_android/lib/widgets/run_share_card.dart`
  - `apps/mobile_android/lib/widgets/todays_workout_card.dart`
  - `apps/mobile_android/lib/widgets/upcoming_event_card.dart`
  - `apps/mobile_android/lib/widgets/workout_edit_sheet.dart`
- **Category**: inconsistency (test coverage gap)
- **Problem**: Five widgets that already have tests (`fitness_card`, `plan_calendar`, `workout_execution_band`, `workout_review_section`, `pace_segments`) share similar complexity to the eight above, yet no test files exist for them. The existing tests prove the pattern works — the gap is just not applied consistently. High-value missing cases:
  - `collapsible_panel`: toggle state, flick-up/down velocity threshold
  - `goal_editor_sheet`: save/delete with valid and invalid inputs, unit conversion round-trip
  - `workout_edit_sheet`: pace parse rejection, success path
  - `todays_workout_card`: `done` vs not-done rendering
  - `upcoming_event_card`: `_relativeFromNow` edge cases (< 1 min, exactly 1 hour)
  - `run_share_card`: `RunShareCard` stat rendering, no-track fallback
  - `error_state`: retry callback fires
  - `live_run_map`: GPS-wait state, user-panned re-center button visibility
- **Proposed change**: Create one test file per widget under `apps/mobile_android/test/`. Follow the patterns in `fitness_card_test.dart` (pump widget, verify text/callback). `LiveRunMap` needs `flutter_map` fakes or `flutter_test`'s `pumpAndSettle`; stub `TileCache.store` / `dotenv` before pumping.
- **Risk if applied**: None.
- **Verification**: `flutter test apps/mobile_android` must pass with the new files present.

---

### M2. Three redundant pace `mm:ss` formatters when `training.fmtPace` already exists
- **File(s)**:
  - `apps/mobile_android/lib/widgets/workout_execution_band.dart:218-222` (`_fmtPace`)
  - `apps/mobile_android/lib/widgets/workout_edit_sheet.dart:201-205` (`_fmtPaceMmSs`)
  - `apps/mobile_android/lib/widgets/workout_review_section.dart:248-253` (`formatPace`)
- **Category**: duplication
- **Problem**: All three implement the same `secPerKm → "m:ss/km"` or `"m:ss"` conversion independently. `training.dart` already exports `fmtPace(int? secPerKm)` which handles null, zero, and appends `/km`. The three private copies will drift (one already omits the `/km` suffix, one omits the null guard).
- **Evidence**:
  ```dart
  // workout_execution_band.dart
  static String _fmtPace(int secPerKm) {
    final m = secPerKm ~/ 60;
    final s = secPerKm % 60;
    return '$m:${s.toString().padLeft(2, '0')}/km';
  }

  // workout_edit_sheet.dart
  static String _fmtPaceMmSs(int secPerKm) {
    final m = secPerKm ~/ 60;
    final s = secPerKm % 60;
    return '$m:${s.toString().padLeft(2, '0')}';  // no /km
  }

  // workout_review_section.dart
  String formatPace(int? secPerKm) {
    if (secPerKm == null || secPerKm <= 0) return '—';
    final m = secPerKm ~/ 60;
    final s = secPerKm % 60;
    return '$m:${s.toString().padLeft(2, '0')}/km';
  }

  // training.dart — already exists
  String fmtPace(int? secPerKm) {
    if (secPerKm == null || secPerKm <= 0) return '—';
    final m = secPerKm ~/ 60;
    final s = (secPerKm % 60).toString().padLeft(2, '0');
    return '$m:$s/km';
  }
  ```
- **Proposed change**:
  - In `workout_execution_band.dart`: delete `_fmtPace`; add `import '../training.dart' show fmtPace;`; call `fmtPace(step.targetPaceSecPerKm)`.
  - In `workout_edit_sheet.dart`: `_fmtPaceMmSs` drops the `/km` suffix by design (it's an editable field input, not display). Keep it private but rename to make intent clear: `_paceToEditText`. The parse side `_parsePaceMmSs` is unique (not in `training.dart`) — keep it.
  - In `workout_review_section.dart`: delete `formatPace`; add `import '../training.dart' show fmtPace;`; replace calls to `formatPace` with `fmtPace`.
- **Risk if applied**: `training.fmtPace` returns `'—'` for `null` and `<=0`; `workout_execution_band._fmtPace` currently takes a non-nullable `int` and would have returned `'0:00/km'` for zero — check that `step.targetPaceSecPerKm` is never 0 in practice (it is not; it's a required field from the plan generator).
- **Verification**: `flutter test apps/mobile_android` passes. `workout_execution_band_test.dart` line testing `_fmtPace` directly via the `em-dash for null pace` case still passes because `fmtPace(null)` returns `'—'`.

---

### M3. `kBackendLoadTimeout` constant lives in `error_state.dart` — wrong home
- **File(s)**: `apps/mobile_android/lib/widgets/error_state.dart:7`
- **Category**: inconsistency
- **Problem**: `kBackendLoadTimeout` is a network timeout constant used by 7 screen files. It is defined in a widget file because callers import `error_state.dart` to get both the widget and the constant. A timeout constant is not a widget concern. Any new screen that needs the timeout must import the widget file even if it renders no `ErrorState`.
- **Evidence**:
  ```dart
  // error_state.dart
  const kBackendLoadTimeout = Duration(seconds: 15);
  ```
  Seven screens import this file: `clubs_screen`, `club_detail_screen`, `event_detail_screen`, `plan_detail_screen`, `plans_screen`, `explore_routes_screen`, `workout_detail_screen`.
- **Proposed change**: Move `kBackendLoadTimeout` to a small `lib/backend_timeout.dart` (or collocate it in `preferences.dart` / `api_client` if that fits better). Update imports in all 7 screens plus `error_state.dart` itself to the new location.
  ```diff
  // error_state.dart
  - const kBackendLoadTimeout = Duration(seconds: 15);
  + // removed — see lib/backend_timeout.dart
  ```
  Actually per conventions: don't leave a comment. Just remove it and update imports.
- **Risk if applied**: Compile error in any screen that uses `kBackendLoadTimeout` without updating its import — this is the full set of files to update (the grep above lists them all).
- **Verification**: `dart analyze apps/mobile_android` shows no new errors. `flutter test` passes.

---

## Low

### L1. Export button renders as visually disabled due to `OutlinedButton.onPressed: null`
- **File(s)**: `apps/mobile_android/lib/widgets/run_share_card.dart:158-170`
- **Category**: inconsistency
- **Problem**: The Export file format picker is a `PopupMenuButton` whose `child` is `OutlinedButton.icon(onPressed: null, ...)`. The `PopupMenuButton` intercepts the tap through its own gesture recogniser so the menu opens correctly, but `OutlinedButton` with `onPressed: null` is rendered in the disabled/greyed state by Material3 regardless. Users see a grey "Export" button and may assume it is unavailable. Every other `PopupMenuButton` usage in the app (filter chips in `explore_routes_screen`) uses a `Chip` child, which has no disabled visual state.
- **Evidence**:
  ```dart
  PopupMenuButton<String>(
    onSelected: _capturing ? null : _shareFile,
    child: OutlinedButton.icon(
      onPressed: null,          // always null → always visually disabled
      icon: const Icon(Icons.route_outlined),
      label: const Text('Export'),
    ),
  ),
  ```
- **Proposed change**:
  ```diff
  - child: OutlinedButton.icon(
  -   onPressed: null,
  -   icon: const Icon(Icons.route_outlined),
  -   label: const Text('Export'),
  - ),
  + child: OutlinedButton.icon(
  +   onPressed: _capturing ? null : () {},
  +   icon: const Icon(Icons.route_outlined),
  +   label: const Text('Export'),
  + ),
  ```
  The empty `() {}` is the idiomatic Flutter workaround: a non-null `onPressed` enables the visual state; the `PopupMenuButton` captures the actual tap before `OutlinedButton` fires its callback.
- **Risk if applied**: None — the `onPressed` callback body is never reached.
- **Verification**: Open run detail → Share → confirm Export button has active visual state matching the Image button.

---

### L2. `withOpacity` used in `_PulsingDot` (deprecated, `info`-level lint)
- **File(s)**: `apps/mobile_android/lib/widgets/live_run_map.dart:491,504`
- **Category**: inconsistency
- **Problem**: Two `Color.withOpacity()` calls survive in `_PulsingDot` while the rest of the widget already uses `withValues(alpha: ...)`. Per `CLAUDE.md`, these are acknowledged `info`-level lint — flagging here because the file already shows the correct pattern internally and the inconsistency is one line per site.
- **Evidence**:
  ```dart
  color: const Color(0xFF818CF8).withOpacity(animation.value),
  // ...
  color: const Color(0xFF818CF8).withOpacity(0.4),
  ```
- **Proposed change**:
  ```diff
  - color: const Color(0xFF818CF8).withOpacity(animation.value),
  + color: const Color(0xFF818CF8).withValues(alpha: animation.value),
  
  - color: const Color(0xFF818CF8).withOpacity(0.4),
  + color: const Color(0xFF818CF8).withValues(alpha: 0.4),
  ```
- **Risk if applied**: None.
- **Verification**: `dart analyze apps/mobile_android` should drop 2 `deprecated_member_use` entries for this file.

---

### L3. `toleranceSecPerKm` is not serialised into `workout_step_results` JSON, so `workout_review_section` hardcodes `10` and silently uses the wrong threshold for any workout with a custom tolerance
- **File(s)**: `apps/mobile_android/lib/widgets/workout_review_section.dart:240` / `packages/run_recorder/lib/src/workout_runner.dart:325-347`
- **Category**: inconsistency
- **Problem**: `WorkoutStep.toleranceSecPerKm` defaults to 10 but is configurable per step. `WorkoutStepResult.toJson()` does not emit `tolerance_sec_per_km`. `paceDeltaOf()` in `workout_review_section.dart` hardcodes `final tol = 10`. If a future workout uses a non-default tolerance (e.g. 15s for an easy step), the live `PaceAdherence` calculation in `workout_runner.dart` uses the actual value while the post-run review uses 10 — the colour coding will disagree.
- **Evidence**:
  ```dart
  // workout_runner.dart — toJson() does not include tolerance
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'target_pace_sec_per_km': step.targetPaceSecPerKm,
      'actual_pace_sec_per_km': actualPaceSecPerKm,
      // toleranceSecPerKm absent
    };
  }

  // workout_review_section.dart
  final tol = 10; // matches recorder default
  ```
- **Proposed change**: Add `'tolerance_sec_per_km': step.toleranceSecPerKm` to `WorkoutStepResult.toJson()`. Add `toleranceSecPerKm` to `WorkoutStepReview.fromMap()`. Replace the hardcoded `tol` in `paceDeltaOf`:
  ```diff
  // workout_runner.dart toJson()
  + 'tolerance_sec_per_km': step.toleranceSecPerKm,

  // workout_review_section.dart WorkoutStepReview
  + final int toleranceSecPerKm;

  // paceDeltaOf
  - final tol = 10;
  + final tol = s.toleranceSecPerKm;
  ```
  Add `tolerance_sec_per_km` to `docs/metadata.md` under `workout_step_results` entries. Update `metadata_registry_test.dart` if it scans that key.
- **Risk if applied**: Old `workout_step_results` JSON rows (written before this change) will not have the key; `fromMap` must default to 10 for missing entries. `(raw['tolerance_sec_per_km'] as num?)?.toInt() ?? 10` handles this.
- **Verification**: `flutter test apps/mobile_android` passes. `workout_review_section_test.dart` tone-classification tests still pass (they currently use the default 10, so no change needed unless new tests are added for non-default tolerance).

---

## Counts
H: 3  M: 3  L: 3
