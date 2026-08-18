import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the route-backfill push swallow.
///
/// `_backfillHealthConnectTracks` writes the released Health Connect maps to
/// disk and then pushes them to the server. The push was wrapped in a catch
/// that only `debugPrint`ed, so a failed upload still reported "Added maps to
/// N runs" — the maps are on the device, the server does not have them, and
/// `SyncService` is the thing that will retry. That is the claim the import
/// path already makes with `importStatusCloudPushDeferred`, so the backfill
/// says it with the same flag and the same string rather than a second
/// vocabulary of its own.
///
/// A source guard because the path is unreachable on the host: both
/// `requestHealthRoutePermission` and `HealthConnectImporter.fetchRoutes`
/// refuse off Android, and the push branch additionally needs a signed-in
/// `ApiClient`, which has no fake.
void main() {
  final src = File('lib/screens/import_screen.dart').readAsStringSync();

  String slice(String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '$signature moved');
    final end = src.indexOf('\n  /// ', start);
    return src.substring(start, end == -1 ? src.length : end);
  }

  test('a failed backfill push is reported, not swallowed', () {
    final body = slice('_backfillHealthConnectTracks() async {');
    expect(body.contains("debugPrint('Route backfill cloud push failed"), isTrue,
        reason: 'the log line is still wanted, it just cannot be the whole '
            'response to a failed upload');
    expect(body.contains('pushDeferred = true;'), isTrue,
        reason: 'the catch must record the deferral, not only log it');
    expect(body.contains('return (filled: filled.length, pushDeferred:'), isTrue,
        reason: 'the deferral has to leave the method to be surfaceable');
  });

  test('the caller feeds the deferral into the shared import flag', () {
    final body = slice('Future<void> _allowRouteImport() async {');
    expect(body.contains('_cloudPushDeferred = backfill.pushDeferred;'), isTrue,
        reason: 'the route-backfill outcome must reach the same state field '
            'the import path sets');
  });

  test('the deferral renders through the existing import status line', () {
    expect(src.contains('if (!_busy && _cloudPushDeferred) ...['), isTrue);
    expect(src.contains('l10n.importStatusCloudPushDeferred'), isTrue);
    // One flag, one string, one place it renders: a second key here would be
    // a second vocabulary for the same fact.
    expect('l10n.importStatusCloudPushDeferred'.allMatches(src).length, 1);
    expect(
      RegExp(r'importStatusCloudPush\w*').allMatches(src).map((m) => m[0]).toSet(),
      {'importStatusCloudPushDeferred'},
    );
  });
}
