import 'package:flutter_test/flutter_test.dart';

import '../lib/social_service.dart';

/// `fmtRelative` is the canonical localized relative-time formatter (feed
/// posts, run comments). Pins that it renders in the requested locale and
/// picks the right bucket. Uses the `now` seam so the buckets are
/// deterministic; stays within the relative buckets (never the absolute-
/// date fallback) so no intl date init is needed.
void main() {
  final now = DateTime.utc(2026, 6, 1, 12, 0, 0);
  DateTime ago(Duration d) => now.subtract(d);

  group('fmtRelative — English buckets', () {
    test('under a minute', () {
      expect(fmtRelative(ago(const Duration(seconds: 30)), 'en', now: now), 'Just now');
    });
    test('minutes', () {
      expect(fmtRelative(ago(const Duration(minutes: 5)), 'en', now: now), '5m ago');
    });
    test('hours', () {
      expect(fmtRelative(ago(const Duration(hours: 2)), 'en', now: now), '2h ago');
    });
    test('yesterday', () {
      expect(fmtRelative(ago(const Duration(hours: 25)), 'en', now: now), 'Yesterday');
    });
    test('days', () {
      expect(fmtRelative(ago(const Duration(days: 3)), 'en', now: now), '3d ago');
    });
    test('weeks (plural)', () {
      expect(fmtRelative(ago(const Duration(days: 14)), 'en', now: now), '2 weeks ago');
    });
    test('weeks (singular)', () {
      expect(fmtRelative(ago(const Duration(days: 8)), 'en', now: now), '1 week ago');
    });
  });

  group('fmtRelative — localized', () {
    test('German minutes + weeks', () {
      expect(fmtRelative(ago(const Duration(minutes: 5)), 'de', now: now), 'vor 5 Min.');
      expect(fmtRelative(ago(const Duration(days: 14)), 'de', now: now), 'vor 2 Wochen');
    });
    test('Japanese minutes + just-now', () {
      expect(fmtRelative(ago(const Duration(seconds: 10)), 'ja', now: now), 'たった今');
      expect(fmtRelative(ago(const Duration(minutes: 5)), 'ja', now: now), '5分前');
    });
  });
}
