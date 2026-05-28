import 'package:flutter_test/flutter_test.dart';

import '../lib/training_service.dart';

void main() {
  // CI regression pin: TrainingService.fetchViewerGender is called
  // from `_PlanNewScreenState.initState`. When Supabase isn't
  // initialised (every widget test that doesn't boot the local
  // stack), the `_c` getter throws a StateError. A previous version
  // of `fetchViewerGender` only wrapped the network read in
  // try/catch, leaving the `_uid` -> `_c` access exposed — the
  // initState thus crashed the entire test. The fix moved the
  // try/catch to cover both, restoring the L4-best-effort contract.
  //
  // This test is the smallest possible reproducer: a default-
  // constructed TrainingService (no override, no Supabase.initialize)
  // returns null from fetchViewerGender instead of throwing.

  test(
    'fetchViewerGender returns null (no throw) when Supabase is uninitialised',
    () async {
      final svc = TrainingService();
      final g = await svc.fetchViewerGender();
      expect(g, isNull);
    },
  );
}
