import 'dart:async';

import 'store_write_watch.dart';

/// Suite-wide instrumentation for the store write chain, applied to every test
/// under this directory by `flutter_test`'s own configuration hook.
///
/// Both defects it watches for are DYNAMIC properties no source scan can see.
/// A widget test's `tester.tap` runs on the fake clock, so a store write it
/// starts completes on the real event loop the fake clock never turns: if
/// nothing waits for that write, it is still in flight when `tearDown` deletes
/// the temp directory out from under it, and the torn rename is either silent
/// or an unattributable failure in whichever test runs next. Three successive
/// censuses tried to count that population by grepping for helper names —
/// `pumpUntil`, `pumpEventQueue`, a temp directory beside a tap — and all
/// three counted something else (decisions § 1097).
///
/// The second is `storeWritesSettled`'s own diagnosis, which is delivered by
/// completing a future and so reaches its awaiter through the awaiting zone's
/// continuation — never run for a fake-zone await with no pump behind it, so
/// the test hangs to the runner's timeout printing a bare `TimeoutException`
/// that names neither the store nor the call site (decisions § 1093, row 5).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  installStoreWriteWatch();
  await testMain();
}
