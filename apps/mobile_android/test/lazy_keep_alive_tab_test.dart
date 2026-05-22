import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-grep arch guards for the `_LazyKeepAliveTab` rebuildKey
/// fix in `home_screen.dart`.
///
/// The user reported "tapping Start Run from a route detail jumps to
/// the Run tab but doesn't select the route." Root cause: the
/// lazy-keep-alive cache held the FIRST build of RunScreen alive
/// forever — when `_startRunWithRoute` updated `_preselectedRoute`,
/// the rebuild rebuilt the page LIST but reused the same cached
/// RunScreen instance with the old (null) `initialRoute`.
///
/// The fix:
///   1. `_LazyKeepAliveTab` accepts a `rebuildKey: Object?` prop.
///   2. `didUpdateWidget` clears `_child` when rebuildKey changes.
///   3. The Run tab passes `_preselectedRoute?.id` as rebuildKey so
///      a new route selection invalidates the cache.
///
/// Source-grep instead of widget-test because the home_screen
/// integration would require mocking 8+ services (audio cues,
/// social, training, BLE, etc.). The arch-guard pins the wiring at
/// the exact lines where a regression would re-introduce the bug.
void main() {
  group('_LazyKeepAliveTab — rebuildKey wiring', () {
    late String src;
    setUpAll(() {
      src = File('lib/screens/home_screen.dart').readAsStringSync();
    });

    test('_LazyKeepAliveTab exposes a rebuildKey prop', () {
      expect(
        src.contains('final Object? rebuildKey'),
        isTrue,
        reason:
            '_LazyKeepAliveTab must declare a rebuildKey prop — without '
            'it, the cached child never re-invokes its builder after '
            'an upstream state change (e.g. _preselectedRoute updates).',
      );
      expect(
        src.contains('this.rebuildKey'),
        isTrue,
        reason: 'rebuildKey must be wired through the constructor.',
      );
    });

    test('didUpdateWidget clears the cache when rebuildKey changes', () {
      expect(
        src.contains('old.rebuildKey != widget.rebuildKey'),
        isTrue,
        reason: 'The cache invalidation is gated on rebuildKey diff '
            '— without this, tab swipes would needlessly drop the '
            'cached child (defeating keep-alive).',
      );
      expect(
        src.contains('_child = null'),
        isTrue,
        reason: 'Must actually null out the cache on key change so the '
            'next build re-invokes widget.builder().',
      );
    });

    test(
        'the Run tab passes _preselectedRoute?.id as rebuildKey — '
        'cache invalidates when the route selection changes',
        () {
      expect(
        src.contains('rebuildKey: _preselectedRoute?.id'),
        isTrue,
        reason: 'Without this, "Start Run from route detail" jumps to '
            'the Run tab but RunScreen still has the OLD '
            'initialRoute. The user-reported "route not selected" '
            'bug.',
      );
    });

    test(
        'tabs WITHOUT a rebuildKey keep their original build-once '
        'keep-alive-forever semantics (no needless rebuilds)',
        () {
      // Negative pin: most _LazyKeepAliveTab callsites should NOT
      // pass a rebuildKey. Only the Run tab needs to react to
      // external state changes; Dashboard / Runs / Social /
      // Settings stay cached for their full lifetime as before.
      // Quick count: rebuildKey: appears exactly ONCE (the Run tab).
      final occurrences = 'rebuildKey:'.allMatches(src).length;
      expect(
        occurrences,
        1,
        reason: 'Only the Run tab should opt in to rebuildKey '
            'invalidation — adding it to every tab would defeat the '
            'lazy-keep-alive optimisation.',
      );
    });

    test('_startRunWithRoute sets _preselectedRoute + jumps to tab 1', () {
      // Pin the flow that the rebuildKey fix supports.
      expect(src.contains('_preselectedRoute = route'), isTrue);
      expect(src.contains('_pageController.jumpToPage(1)'), isTrue,
          reason: 'Run tab is index 1 in the home nav.');
    });
  });
}
