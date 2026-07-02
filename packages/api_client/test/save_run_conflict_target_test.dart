import 'dart:io';

import 'package:test/test.dart';

/// Regression guard for the imported-run sync bug: `saveRun` /
/// `saveRunsBatch` upsert with `onConflict: 'external_id'`, but the
/// unique index that backs the dedupe is the composite
/// `(user_id, external_id)` (migration
/// 20260528000003_runs_external_id_per_user_unique.sql). Postgres rejects
/// an ON CONFLICT target that doesn't match a unique index (42P10), so a
/// bare `external_id` target makes every sync of a run carrying an
/// external_id (Strava ZIP / CSV / Health Connect import) fail
/// deterministically and get swallowed. The conflict target must name
/// both index columns, in order.
void main() {
  test('run upserts target the composite (user_id, external_id) index', () {
    final src = File('lib/src/api_client.dart').readAsStringSync();

    // The composite target must be present (both saveRun + saveRunsBatch
    // build it the same way).
    expect(
      src.contains("'\${RunRow.colUserId},\${RunRow.colExternalId}'"),
      isTrue,
      reason:
          'run upserts must set onConflict to the composite (user_id, external_id) '
          'so it matches the runs_user_external_id unique index',
    );

    // The bare single-column target that triggered 42P10 must be gone.
    expect(
      src.contains('onConflict: RunRow.colExternalId'),
      isFalse,
      reason:
          'a bare external_id ON CONFLICT target does not match any unique index '
          '(42P10) — it must be the composite (user_id, external_id)',
    );
  });
}
