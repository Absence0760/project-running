# Social / training / domain — audit

Files reviewed:
- `apps/mobile_android/lib/social_service.dart`
- `apps/mobile_android/lib/training_service.dart`
- `apps/mobile_android/lib/training.dart`
- `apps/mobile_android/lib/goals.dart`
- `apps/mobile_android/lib/recurrence.dart`
- `apps/mobile_android/lib/preferences.dart`
- `apps/mobile_android/lib/mock_data.dart`
- `apps/mobile_android/lib/screens/clubs_screen.dart`
- `apps/mobile_android/lib/screens/club_detail_screen.dart`
- `apps/mobile_android/lib/screens/event_detail_screen.dart`
- `apps/mobile_android/lib/screens/plans_screen.dart`
- `apps/mobile_android/lib/screens/plan_detail_screen.dart`
- `apps/mobile_android/lib/screens/plan_new_screen.dart`
- `apps/mobile_android/lib/screens/workout_detail_screen.dart`
- `apps/mobile_android/lib/widgets/todays_workout_card.dart`
- `apps/mobile_android/lib/widgets/upcoming_event_card.dart`
- `apps/mobile_android/lib/widgets/goal_editor_sheet.dart`
- `apps/mobile_android/test/training_test.dart`
- `apps/mobile_android/test/goals_test.dart`

Date: 2026-04-21
Auditor scope: mobile_android social + training + goals + prefs

## Summary

The training engine (VDOT, Riegel, plan generation) and goal evaluation logic are correct and well-tested. The offline-resilience pattern from commit a3116ec is applied consistently across all five screen `_load()` methods with proper timeout handling and error state display. The main structural problems are: a timezone bug in `recurrence.dart` that causes weekly recurring event instances to be queried with wrong timestamps for any user outside UTC; a `_busy` flag in `ClubDetailScreen._leave()` that is never reset on error, permanently disabling the Leave button after a network failure; an unhandled exception in `_sendReply`; and two screens (`plan_detail_screen`, `workout_detail_screen`, `todays_workout_card`) that display training distances and paces exclusively in km/km regardless of the user's `preferred_unit` setting. The `mock_data.dart` file is entirely dead code (no imports). No paywall gating issues exist (the paywall is disabled app-wide).

---

## Findings

### P0 — bugs / data loss / security

---

**P0-1: Weekly recurrence instances serialized as local ISO strings cause attendee-count and RSVP queries to miss for users outside UTC**

`apps/mobile_android/lib/recurrence.dart:147-155`

`expandInstances()` constructs instance `DateTime` objects using the `startsAt` field's UTC components to build a **local** (unzoned) `DateTime`:

```dart
final stamped = DateTime(
  d.year,
  d.month,
  d.day,
  e.startsAt.hour,   // UTC hour from a UTC-parsed DateTime
  e.startsAt.minute,
  e.startsAt.second,
);
```

`e.startsAt` is parsed from a Supabase `timestamptz` string by `DateTime.parse`, which returns an **isUtc=true** object whose `.hour` is UTC. Constructing `DateTime(year, month, day, hour, ...)` without a `isUtc: true` argument produces a **local** datetime with those UTC field values — which is the wrong wall-clock time for any user outside UTC.

The resulting local `DateTime` is then serialized with `.toIso8601String()`, which emits a no-offset string (e.g. `2026-03-01T10:00:00.000`). Supabase interprets a no-offset timestamptz as the database server's timezone (UTC). For a user in UTC+2 an event at 10:00 UTC becomes `DateTime(year, month, day, 10, 0, 0)` in local time = UTC 08:00, so the query fires against `instance_start = '2026-03-01T10:00:00'` (local) while the DB row stores `2026-03-01T10:00:00+00:00`. The query misses, returning attendeeCount=0 and viewerRsvp=null.

The monthly path is not affected because `cursor` is the original UTC `DateTime` and is inserted directly into results, so its `.toIso8601String()` emits `+00:00`.

Fix: replace the `stamped` construction with:

```dart
// e.startsAt is UTC; convert to local first so .hour/.minute/.second are local.
final localStart = e.startsAt.toLocal();
final stamped = DateTime(
  d.year,
  d.month,
  d.day,
  localStart.hour,
  localStart.minute,
  localStart.second,
);
```

Apply the same fix to the anchor computation at line 131 (currently uses `e.startsAt.year/month/day` — UTC fields — to build a local date):

```dart
final localStart = e.startsAt.toLocal();
final anchor = DateTime(localStart.year, localStart.month, localStart.day)
    .subtract(Duration(days: localStart.weekday % 7));
```

The TS port in `apps/web/src/lib/recurrence.ts` uses `start.getHours()` which already returns local hours, so the fix aligns Dart with the web behavior. After fixing, verify with a test fixture using a UTC event time and a user in a non-UTC timezone.

---

**P0-2: `ClubDetailScreen._leave()` sets `_busy = true` with no try/finally — UI permanently locked on network error**

`apps/mobile_android/lib/screens/club_detail_screen.dart:131-133`

```dart
setState(() => _busy = true);
await widget.social.leaveClub(c.row.id);  // throws on network error
await _load();                             // never reached
// _busy is never reset
```

`_join()` (line 95) and `_submitPost()` (line 141) both wrap their bodies in `try/finally { setState(() => _busy = false); }`. `_leave()` does not. Any exception from `leaveClub` or `_load` leaves `_busy = true` permanently, disabling the Leave button for the session without any visible error.

Fix: wrap the body of `_leave()` after the dialog confirmation in a try/finally:

```dart
setState(() => _busy = true);
try {
  await widget.social.leaveClub(c.row.id);
  await _load();
} catch (e) {
  if (mounted) setState(() => _error = e.toString());
} finally {
  if (mounted) setState(() => _busy = false);
}
```

---

### P1 — resilience violations, correctness

---

**P1-1: `ClubDetailScreen._sendReply()` has no error handling — network failure crashes silently**

`apps/mobile_android/lib/screens/club_detail_screen.dart:166-182`

`_sendReply` calls `createPost` and `fetchPostReplies` without a try/catch. A network failure, RLS rejection, or Supabase error propagates to Flutter's unhandled-exception handler and surfaces as a red screen in debug or a silent no-op in release. The user gets no feedback and their reply is lost.

Fix: add a try/catch with a `ScaffoldMessenger` snackbar on error:

```dart
try {
  await widget.social.createPost(clubId: c.row.id, parentPostId: postId, body: body);
  ctrl?.clear();
  final replies = await widget.social.fetchPostReplies(postId);
  if (!mounted) return;
  setState(() => _threads[postId] = replies);
  _load();
} catch (e) {
  if (mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Reply failed: $e')));
  }
}
```

---

**P1-2: `EventDetailScreen._pickInstance()` has no error handling — instance-switch silently stalls**

`apps/mobile_android/lib/screens/event_detail_screen.dart:126-138`

```dart
Future<void> _pickInstance(DateTime dt) async {
  setState(() => _activeInstance = dt);
  final attendees = await widget.social.fetchAttendees(e.row.id, dt);
  final results  = await widget.social.fetchEventResults(e.row.id, dt);
  // no try/catch
  if (mounted) setState(() { _attendees = attendees; _results = results; });
}
```

If either fetch throws (network, timeout), the UI stays showing the previous instance's data while `_activeInstance` has already been updated, creating an inconsistent display state. The error is unhandled.

Fix: add a try/catch. On error, revert `_activeInstance` and show a snackbar:

```dart
Future<void> _pickInstance(DateTime dt) async {
  final previous = _activeInstance;
  setState(() => _activeInstance = dt);
  try {
    final attendees = await widget.social.fetchAttendees(e.row.id, dt);
    final results   = await widget.social.fetchEventResults(e.row.id, dt);
    if (mounted) setState(() { _attendees = attendees; _results = results; });
  } catch (err) {
    if (mounted) {
      setState(() => _activeInstance = previous);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Couldn\'t load instance: $err')));
    }
  }
}
```

---

**P1-3: Monthly recurrence end-of-month overflow produces wrong instance dates (both Dart and TS)**

`apps/mobile_android/lib/recurrence.dart:114-122`

```dart
cursor = DateTime(
  cursor.year,
  cursor.month + 1,   // Jan 31 -> DateTime(year, 2, 31) -> March 3 in non-leap year
  cursor.day,
  cursor.hour, cursor.minute, cursor.second,
);
```

Dart `DateTime` overflows month+day combinations: `DateTime(2026, 2, 31)` normalizes to `2026-03-03`, which skips February entirely and shifts all subsequent occurrences. The same overflow exists in the TS port (`Date.setMonth`), so both implementations share this bug and produce consistent (but wrong) dates.

The web's `addMonths` function at `apps/web/src/lib/recurrence.ts:132-135` has the same behavior. Events created on the 29th, 30th, or 31st of a month will drift. The `clubs.md` doc says monthly recurrence uses the day-of-month of `starts_at` — the correct behavior for a 31st-of-month event is to fall on the last day of shorter months.

Fix (Dart):

```dart
int clampedDay(int year, int month, int targetDay) {
  final lastDay = DateTime(year, month + 1, 0).day; // day 0 of next month = last of this
  return targetDay > lastDay ? lastDay : targetDay;
}

cursor = DateTime(
  cursor.year,
  cursor.month + 1,
  clampedDay(cursor.year, cursor.month + 1, e.startsAt.toLocal().day),
  ...
);
```

Apply the same fix in `apps/web/src/lib/recurrence.ts`'s `addMonths`. After fixing, verify with a test: event starting Jan 31 should produce Feb 28 (non-leap), Mar 31, Apr 30, May 31.

---

**P1-4: Training screens display distances and paces exclusively in km, ignoring `preferred_unit`**

`apps/mobile_android/lib/screens/workout_detail_screen.dart:114`
`apps/mobile_android/lib/screens/plan_detail_screen.dart:151,270,327,398`
`apps/mobile_android/lib/widgets/todays_workout_card.dart:84,94`
`apps/mobile_android/lib/screens/plan_new_screen.dart:305-309`

All four surfaces call `fmtKm()` and `fmtPace()` from `training.dart`, which are hardcoded to km and sec/km respectively. No `Preferences` or `UnitFormat` is injected. A user who has set `preferred_unit = 'mi'` sees all training plan distances and paces in metric, while the rest of the app (run history, goal editor, dashboard) correctly uses miles.

Fix: inject `Preferences` into `PlanDetailScreen`, `WorkoutDetailScreen`, and `TodaysWorkoutCard`. Replace `fmtKm(metres)` with `UnitFormat.distance(metres, prefs.unit)` and replace `fmtPace(secPerKm)` with `UnitFormat.pace(secPerKm?.toDouble(), prefs.unit)` for display. Keep the internal `training.dart` functions in sec/km — only the display layer converts.

---

**P1-5: `goals.dart` `weekStartLocal()` ignores the `week_start_day` setting — Sunday-start users see wrong week boundaries**

`apps/mobile_android/lib/goals.dart:360-364`

```dart
DateTime weekStartLocal(DateTime now) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  final daysFromMonday = (now.weekday - DateTime.monday) % 7;
  return startOfToday.subtract(Duration(days: daysFromMonday));
}
```

The `week_start_day` key (`'monday' | 'sunday'`) is registered in `docs/settings.md` and editable on the web settings page. `weekStartLocal()` always uses Monday regardless. A user who configures Sunday start will see: goal progress reset on Monday (not Sunday), a different week boundary than the web dashboard's mileage rollup, and the `period_summary_screen` (which has its own `periodStart` logic — also Monday-anchored) disagrees with the goal card.

`weekStartLocal()` is the documented "single source of truth for this week across goals, the history filter, and the dashboard summary cards." Fix it to accept the preference:

```dart
DateTime weekStartLocal(DateTime now, {String weekStartDay = 'monday'}) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  final anchorWeekday = weekStartDay == 'sunday' ? DateTime.sunday : DateTime.monday;
  final daysFromAnchor = (now.weekday - anchorWeekday) % 7;
  return startOfToday.subtract(Duration(days: daysFromAnchor));
}
```

Thread `Preferences.weekStartDay` (a new getter reading the `week_start_day` key from `user_settings.prefs` via `SettingsSyncService`) through to every `evaluateGoal` call site. Update `goals_test.dart` to cover both `monday` and `sunday` week-start configurations.

---

**P1-6: `submitEventResult` swallows the `runs` back-link update error without logging**

`apps/mobile_android/lib/social_service.dart:528-535`

```dart
try {
  await _c.from('runs').update({'event_id': eventId}).eq('id', runId).eq('user_id', uid);
} catch (_) {}
```

The convention (`docs/conventions.md § Isolate auxiliary effects`) requires `debugPrint` on catch, not a silent swallow. Without the log there is no way to detect a systematic failure (e.g. RLS regression on `runs` update) in production.

Fix:

```dart
} catch (e, s) {
  debugPrint('submitEventResult: runs back-link failed for runId=$runId: $e\n$s');
}
```

---

**P1-7: No recurrence test coverage — DST transitions, end-of-month, count limit, biweekly stepping are untested**

`apps/mobile_android/lib/recurrence.dart` has no corresponding test file. The existing test suite lists `training_test.dart` and `goals_test.dart` but there is no `recurrence_test.dart`. The only `expandInstances` consumer (`social_service.dart:_enrichEvents`) is also untested.

Critical missing cases:
- A weekly event spanning a DST spring-forward boundary (the local-time hour should stay constant, not shift by 1h).
- Monthly event on Jan 31 (currently produces March 3 as noted in P1-3).
- `recurrence_count` cap: verify expansion stops at `count` occurrences.
- Biweekly with `byday=['MO','WE']` — only alternating weeks should fire.
- An event whose `until` falls mid-week — verify no instance is emitted after `until`.

Create `apps/mobile_android/test/recurrence_test.dart`. Minimum 8 test cases covering the above.

---

### P2 — maintainability, duplication, code smell

---

**P2-1: `_enrichEvents` fires 2N parallel Supabase queries (1 count + 1 RSVP per event)**

`apps/mobile_android/lib/social_service.dart:343-370`

For a club with N upcoming events the method fires `2N` round-trips in parallel. While parallelized via `Future.wait`, each is a separate network call. With 10 events that's 20 calls. The attendee counts for all events for a given instance start could be retrieved in a single call using a group-by RPC or a Postgres view. At small N this is acceptable, but it will be noticeable as clubs grow.

No immediate fix required, but before this path hits 10+ events per club regularly, introduce an `event_attendee_counts(event_ids, instance_starts)` RPC that returns `(event_id, count)` rows in one round-trip. The RSVP check (per-user) can remain per-event since it's user-scoped.

---

**P2-2: `mock_data.dart` is entirely dead code with a frozen `now` date**

`apps/mobile_android/lib/mock_data.dart:125,133,141`

```dart
final now = DateTime(2026, 4, 8);   // hardcoded — already in the past
```

`mockRuns`, `mockRoutes`, `weeklyDistanceMetres`, `weeklyRunCount`, `weeklyDuration` are defined but not imported by any file in `lib/` or `test/`. The CLAUDE.md notes it as "fallback data when Supabase returns nothing (dev only)" but the wiring no longer exists. The frozen date means the weekly computed values would be wrong even if wired.

Delete `mock_data.dart`. It has no callers. If a future developer re-introduces mock data, they should use `DateTime.now()` and a relative offset rather than a hardcoded date.

---

**P2-3: Training plan input allows unrealistically small race times, producing garbage pace data**

`apps/mobile_android/lib/screens/plan_new_screen.dart:194-209`
`apps/mobile_android/lib/training_service.dart:169-172`

`_numField` for goal time uses `min=0`. A user entering `0h 0m 1s` passes the `goalTimeSec > 0` check in `createPlan`, but `resolveTrainingPaces` produces pace values that round to 0 sec/km for all zones, and the plan is saved to the DB with zero paces. The preview preview would show `0:00/km` for all zones, but a user who ignores this can still tap Create.

`createPlan` already validates `goalTimeSec > 0`. Tighten to a plausible minimum (the world record for any goal distance is a reasonable floor):

```dart
// Fastest plausible 5K is ~12 min; add a universal 10-min floor with a clear message.
if (goalTimeSec != null && goalTimeSec < 600) {
  throw Exception('Goal time seems too fast. Check the hours/minutes/seconds fields.');
}
if (recent5kSec != null && recent5kSec < 600) {
  throw Exception('Recent 5K time seems too fast. Check the minutes/seconds fields.');
}
```

Apply in `training_service.dart:createPlan` (where the other validations live), not in the screen.

---

**P2-4: `_evalCumulative` "behind pace" feedback shows total remaining, not the pace deficit**

`apps/mobile_android/lib/goals.dart:264-266`

```dart
feedback = delta > 0
    ? '${format(delta)} ahead of pace'
    : '${format(target - current)} to go';
```

When the user is behind pace, the feedback shows how much they still need to hit the goal (target − current), not how far behind pace they are. Example: target 20km, halfway through the week, user has run 2km. Expected: 10km. Actual delta: −8km. Feedback: "18.0 km to go" — which conveys neither pace deficit nor urgency.

The "ahead of pace" branch does show the pace delta correctly. The "behind" branch should show the same concept (distance/time behind pace):

```dart
: '${format(expected - current)} behind pace';
```

This is currently tested with a "contains 'to go'" assertion in `goals_test.dart:115`. Update that test to `contains('behind pace')` after the change.

---

**P2-5: Training screens and cards display pace in sec/km hardcoded label, no unit label suffix**

`apps/mobile_android/lib/training.dart:577-580`

```dart
String fmtPace(int? secPerKm) {
  ...
  return '$m:$s/km';
}
```

The `/km` suffix is baked in. Imperial users will see `8:00/km` while expecting `12:52/mi`. This compounds the P1-4 unit bug — even after fixing the numeric conversion, the label will still read `/km` unless this function is replaced with a unit-aware formatter at the call sites. Address alongside P1-4 by retiring `fmtPace()` from display paths in favour of `UnitFormat.pace(sec, unit)` + `UnitFormat.paceLabel(unit)`.

---

### P3 — nits

---

**P3-1: `withOpacity` deprecation (acknowledged tech debt)**

`apps/mobile_android/lib/screens/plan_detail_screen.dart:377`

```dart
theme.colorScheme.primaryContainer.withOpacity(0.5)
```

Acknowledged as tech debt in CLAUDE.md (`deprecated_member_use` category). Replace with `.withValues(alpha: 0.5)` when doing a theme pass. Not urgent.

---

**P3-2: Misleading pace feedback message when running activities exist but pace is incalculable**

`apps/mobile_android/lib/goals.dart:291-293`

```dart
feedback = runningRuns == 0
    ? 'Log a running activity to track pace'
    : 'Log a run to start tracking';
```

The `runningRuns > 0` branch fires when running activities are in the period but total pacing distance is under 10m (the `paceMetres > 10` guard). Telling the user to "Log a run to start tracking" when they have logged runs is confusing. Change to:

```dart
: 'Not enough distance data to calculate pace';
```

---

**P3-3: `fmtRelative` in `social_service.dart` and event-list in `club_detail_screen.dart` parse `fmtEventDate` with `.split(',')` which is fragile**

`apps/mobile_android/lib/screens/club_detail_screen.dart:728,735`

```dart
fmtEventDate(e.nextInstanceStart).split(',').first   // "Apr 7"
fmtEventDate(e.nextInstanceStart).split(', ').last   // "11:30 am"
```

`fmtEventDate` returns e.g. `"Apr 7, 11:30 am"`. Splitting on `','` and `', '` is brittle if the format ever changes. Extract the day label and time label as separate format functions instead of re-parsing a pre-formatted string.

---

## Stats
- P0: 2
- P1: 7
- P2: 5
- P3: 3
