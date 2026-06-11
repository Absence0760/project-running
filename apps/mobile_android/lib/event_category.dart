/// Event-category behaviour for typed club events.
///
/// Web twin: `apps/web/src/lib/social/event_category.ts` — keep both in
/// lockstep (same set, same order, same athletic split). Categories are raw
/// `String`s (no Dart enum, per the narrow-union convention); the DB CHECK
/// constraint (migration `20261227_001`) is the validator.
library;

/// Event categories, in the order shown in the create-event picker.
const List<String> kEventCategories = ['run', 'cycle', 'class', 'social'];

/// Distance-based athletic events (run / cycle) carry a course — route,
/// distance, target pace — can be run as a live race, and carry a results
/// leaderboard + finisher certificates. Instructor-led classes and social
/// meetups do none of that; they are attendance-only.
///
/// Single source of truth the event surfaces gate every athletic affordance
/// on. The database enforces the same split via the race_sessions /
/// event_results triggers, so a non-athletic event is un-race-able even via a
/// direct API call — this predicate only governs what the UI shows.
bool isAthleticEventCategory(String category) =>
    category == 'run' || category == 'cycle';
