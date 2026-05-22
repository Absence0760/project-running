import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-grep arch guards for the verified-club badge wiring.
///
/// `_ClubTile` and the club-detail `AppBar` are private widgets
/// inside screen files that depend on a real `SocialService` — too
/// expensive to drive end-to-end from a unit test. This file pins
/// the wiring at source level instead, matching the same arch-guard
/// pattern in `architecture_guards_test.dart` /
/// `route_builder_screen_test.dart`:
///
///   - The badge file exists.
///   - Each consuming screen imports it.
///   - Each consuming screen branches on `isVerified` before
///     rendering the badge (no unconditional render — would mark
///     EVERY club as official).
///
/// Why arch-guards instead of widget pumps: the existing
/// `clubs_screen_test.dart` chrome tests don't seed a populated
/// list — they verify AppBar / segmented button / FAB only. Adding
/// a real `SocialService` mock would be a larger refactor than the
/// badge wiring deserves. Source-grep is the right tool.
void main() {
  group('VerifiedBadge — wiring (source-grep arch guards)', () {
    test('lib/widgets/verified_badge.dart exists and exports VerifiedBadge',
        () {
      final f = File('lib/widgets/verified_badge.dart');
      expect(
        f.existsSync(),
        isTrue,
        reason: 'The badge widget file must exist — every other arch '
            'guard below depends on it.',
      );
      final src = f.readAsStringSync();
      expect(
        src.contains('class VerifiedBadge'),
        isTrue,
        reason: 'VerifiedBadge class must be the public symbol.',
      );
      expect(
        src.contains('Icons.verified'),
        isTrue,
        reason: 'Uses the canonical Material verified icon — pinned '
            'so a refactor to `check_circle` (which means '
            '"completed", not "official") fails this test loud.',
      );
      // Same blue as the Svelte twin.
      expect(
        src.contains('0xFF2563EB'),
        isTrue,
        reason: 'Badge colour must match the Svelte twin '
            '(#2563eb) so cross-platform users see the same mark.',
      );
    });

    test('clubs_screen imports + renders VerifiedBadge guarded on isVerified',
        () {
      final src = File('lib/screens/clubs_screen.dart').readAsStringSync();
      expect(
        src.contains("import '../widgets/verified_badge.dart'"),
        isTrue,
        reason: 'Clubs list screen must import the badge widget.',
      );
      expect(
        src.contains('c.isVerified'),
        isTrue,
        reason: 'The render must branch on `c.isVerified` — without '
            'this guard, an unconditional render would mark every '
            'club as official.',
      );
      expect(
        src.contains('VerifiedBadge()'),
        isTrue,
        reason: 'The badge widget must be instantiated in the tile '
            'render path.',
      );
    });

    test(
        'club_detail_screen imports + renders VerifiedBadge guarded '
        'on c.row.isVerified in the AppBar title row',
        () {
      final src =
          File('lib/screens/club_detail_screen.dart').readAsStringSync();
      expect(
        src.contains("import '../widgets/verified_badge.dart'"),
        isTrue,
      );
      expect(
        src.contains('c.row.isVerified'),
        isTrue,
        reason: 'Club detail AppBar must check `c.row.isVerified` '
            'before rendering the badge.',
      );
      // Inline with the title — not in the actions row, not in
      // the body. Pin the exact placement.
      expect(
        src.contains('VerifiedBadge(size: 18)'),
        isTrue,
        reason: 'AppBar badge must use the 18-dp size for inline-'
            'with-title sizing.',
      );
    });
  });

  group('SocialService.isVerified column wiring', () {
    test(
        '_clubSelectCols includes `is_verified` so PostgREST returns '
        'the column on every clubs query',
        () {
      // Without the column in the select list, every fetched
      // ClubRow gets `isVerified=false` (the JSON default for a
      // missing key — see club_row_test.dart). That would mean
      // the badge never renders even on verified clubs.
      final src = File('lib/social_service.dart').readAsStringSync();
      expect(
        src.contains('is_verified'),
        isTrue,
        reason: '_clubSelectCols must include `is_verified` so the '
            'column flows through every clubs query.',
      );
    });
  });
}
