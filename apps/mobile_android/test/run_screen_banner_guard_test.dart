import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Run-screen alert-banner colour guard (issue #666 V2). The four mid-run
/// alert banners — off-route, permission-revoked, GPS-lost, weak-GPS — used
/// hand-picked Tailwind hexes with Colors.white, two of which failed WCAG AA
/// (3.18-3.76:1 for their 14sp/w600 text). They must draw from the
/// AppSemanticColors theme extension instead: the danger pair for the three
/// failure banners, the warning pair for weak GPS. Source-level (like
/// tap_target_guard_test.dart) because the run screen's LiveRunMap hangs
/// pumpAndSettle; the extension's own contrast is computed in
/// packages/ui_kit/test/app_semantic_colors_test.dart.

String _stripped() => File('lib/screens/run_screen.dart')
    .readAsStringSync()
    .replaceAll(RegExp(r'\s+'), '');

/// The stripped-source window around [anchor], reaching back far enough to
/// cover the banner's Card colour and forward over its text style.
String _bannerSpan(String content, String anchor,
    {int before = 500, int after = 300}) {
  final i = content.indexOf(anchor);
  expect(i, greaterThanOrEqualTo(0), reason: 'anchor "$anchor" not found');
  final start = (i - before).clamp(0, content.length);
  final end = (i + after).clamp(0, content.length);
  return content.substring(start, end);
}

void main() {
  test('the audited banner hexes are gone from run_screen.dart', () {
    final content = _stripped();
    for (final hex in ['0xFFEF4444', '0xFFDC2626', '0xFFD97706']) {
      expect(content.contains(hex), isFalse,
          reason: 'run_screen.dart reintroduced $hex — the alert banners '
              'must use AppSemanticColors (issue #666 V2)');
    }
  });

  group('each banner draws its pair from AppSemanticColors', () {
    const banners = {
      'off-route': ('l10n.runOffRoute(', 'danger'),
      'permission-revoked': ('l10n.runPermissionRevoked', 'danger'),
      'gps-lost': ('l10n.runGpsLost', 'danger'),
      'weak-gps': ('l10n.runWeakGps', 'warning'),
    };
    for (final b in banners.entries) {
      test(b.key, () {
        final span = _bannerSpan(_stripped(), b.value.$1);
        final token = b.value.$2;
        expect(span.contains('semantic.$token'), isTrue,
            reason: '${b.key} banner no longer fills with semantic.$token');
        final onToken =
            'semantic.on${token[0].toUpperCase()}${token.substring(1)}';
        expect(span.contains(onToken), isTrue,
            reason: '${b.key} banner foreground no longer uses $onToken');
        expect(span.contains('Colors.white'), isFalse,
            reason: '${b.key} banner reverted to Colors.white, which fails '
                'WCAG AA on these fills (issue #666 V2)');
        expect(span.contains('Color(0x'), isFalse,
            reason: '${b.key} banner reverted to a hardcoded colour literal '
                '(issue #666 V2)');
      });
    }
  });
}
