import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

/// Pins the fix for the over-long `in` filter class.
///
/// PostgREST serialises `.inFilter(col, ids)` into the request URL. A list
/// past the gateway's request-line budget does not error — the query comes
/// back EMPTY, so the read looks like "this runner follows nobody" or "this
/// profile has no name". [kInFilterChunk] is the project's own stated ceiling.
///
/// The rule this guards: every id list handed to `.inFilter(...)` is either a
/// [readChunked] / [chunkList] chunk — the closure parameter is named `chunk`
/// by convention, which is what makes the guard readable off the source — or
/// it is listed below with the ceiling that holds it under [kInFilterChunk].
void main() {
  final src = File('lib/src/api_client.dart').readAsLinesSync();

  /// `trimmed source line` -> how many times it may appear. Counting rather
  /// than merely listing keeps a second, unbounded read from hiding behind a
  /// bounded one that happens to be written identically.
  const allowed = <String, int>{
    // Uploader ids off a page of `run_photos` capped by fetchEventPhotos'
    // own `limit`, asserted below.
    ".inFilter('id', ownerIds);": 1,
    // Author ids off a feed page capped by fetchFollowingFeed /
    // _fetchFollowingLifts' own `limit`, asserted below.
    '.inFilter(UserProfileRow.colId, authorIds);': 2,
    // The five notification-context joins, each off a page of notifications
    // capped by fetchNotificationViews' own `limit`, asserted below. The club
    // leg is NOT here: it unions event clubs with club-link ids, so it is the
    // one join that can reach twice the page size.
    '.inFilter(UserProfileRow.colId, actorIds);': 1,
    '.inFilter(RunRow.colId, runIds);': 2,
    '.inFilter(RunCommentRow.colId, commentIds);': 1,
    '.inFilter(EventRow.colId, eventIds);': 1,
    // The exercises of ONE authored routine, and the weeks of ONE plan. Both
    // are hand-built by a user; a routine with 100 exercises or a plan with
    // 100 weeks is not a thing that exists.
    '.inFilter(GymRoutineSetRow.colRoutineExerciseId,': 1,
    '.inFilter(PlanWorkoutRow.colWeekId, [for (final w in weeks) w.id])': 1,
    // Author ids off a template search with a literal `.limit(100)`.
    ".inFilter('id', authorIds);": 1,
  };

  test('every unchunked .inFilter carries a stated bound', () {
    final found = <String, int>{};
    for (final line in src) {
      final t = line.trim();
      if (t.startsWith('//') || !t.contains('.inFilter(')) continue;
      if (t.contains(', chunk)')) continue;
      found[t] = (found[t] ?? 0) + 1;
    }

    expect(
      found,
      allowed,
      reason: 'an `in` filter longer than kInFilterChunk returns an empty '
          'result instead of an error. Route the id list through readChunked '
          '(name the closure parameter `chunk`), or list the line above with '
          'the ceiling that keeps it under the bound.',
    );
  });

  /// The ceilings the allowlist leans on. Each is a `limit` default declared
  /// in the method that produces the id list, so a bump past kInFilterChunk
  /// fails here rather than silently emptying the join.
  const limitCeilings = <String, String>{
    'Future<List<EventPhotoView>> fetchEventPhotos(': 'int limit = 100,',
    'Future<List<FeedEntry>> fetchFollowingFeed({': 'int limit = 20,',
    'Future<List<LiftFeedEntry>> _fetchFollowingLifts({': 'int limit = 20,',
    'Future<List<NotificationView>> fetchNotificationViews({':
        'int limit = 100,',
  };

  test('the declared limits the allowlist leans on stay under the bound', () {
    final text = src.join('\n');
    for (final entry in limitCeilings.entries) {
      final start = text.indexOf(entry.key);
      expect(start, greaterThanOrEqualTo(0),
          reason: '${entry.key} moved or was renamed');
      final end = text.indexOf('\n  /// ', start);
      final body = text.substring(start, end == -1 ? text.length : end);
      expect(body.contains(entry.value), isTrue,
          reason: '${entry.key} no longer declares ${entry.value} — its id '
              'list is what the allowlist above calls bounded');
      final declared = int.parse(
          RegExp(r'int limit = (\d+)').firstMatch(entry.value)!.group(1)!);
      expect(declared, lessThanOrEqualTo(kInFilterChunk));
    }
  });
}
