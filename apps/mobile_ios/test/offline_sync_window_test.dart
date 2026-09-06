import 'package:flutter_test/flutter_test.dart';

import '../lib/offline_sync_store.dart';

/// decisions § 1242. `outsideFetchWindow` decides which synced rows a windowed
/// refresh is allowed to prune, and it used to exist three times — twice byte
/// for byte and once open-coded with the `end` bound dropped. Nothing compared
/// them, so the half-open convention could drift on one store alone. These are
/// the direct cases the three `replaceFromServer` suites only ever reached
/// through a whole refresh.
void main() {
  final start = DateTime.utc(2026, 3, 10);
  final end = DateTime.utc(2026, 3, 17);

  group('outsideFetchWindow', () {
    test('an unplaceable timestamp is in-window, so a full replace can prune it',
        () {
      expect(outsideFetchWindow(null, null, null), isFalse);
      expect(outsideFetchWindow(null, start, end), isFalse);
    });

    test('no bounds is a full replace: everything is in-window', () {
      expect(outsideFetchWindow(DateTime.utc(1999), null, null), isFalse);
      expect(outsideFetchWindow(DateTime.utc(2099), null, null), isFalse);
    });

    test('start is INCLUSIVE and end is EXCLUSIVE', () {
      expect(outsideFetchWindow(start, start, end), isFalse);
      expect(outsideFetchWindow(end, start, end), isTrue);
      expect(
          outsideFetchWindow(
              end.subtract(const Duration(microseconds: 1)), start, end),
          isFalse);
      expect(
          outsideFetchWindow(
              start.subtract(const Duration(microseconds: 1)), start, end),
          isTrue);
    });

    test('an open-ended window bounds only the side it was given', () {
      expect(outsideFetchWindow(DateTime.utc(2026, 3, 1), start, null), isTrue);
      expect(outsideFetchWindow(DateTime.utc(2099), start, null), isFalse);
      expect(outsideFetchWindow(DateTime.utc(1999), null, end), isFalse);
      expect(outsideFetchWindow(DateTime.utc(2099), null, end), isTrue);
    });

    test('compares absolute instants, not wall-clock fields', () {
      // The stores hand it a UTC row timestamp against a window bound built
      // from a local DateTime, so a field-wise comparison would misplace every
      // row by the reader's offset.
      final local = DateTime.utc(2026, 3, 12, 6).toLocal();
      expect(outsideFetchWindow(DateTime.utc(2026, 3, 12, 6), local, end),
          isFalse);
      expect(
          outsideFetchWindow(
              DateTime.utc(2026, 3, 12, 6)
                  .subtract(const Duration(microseconds: 1)),
              local,
              end),
          isTrue);
    });
  });
}
