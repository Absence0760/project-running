// Issue #666, the mobile half of §529. The lift and meal glyphs in the history
// timeline were theme-independent `const Color`s doing two jobs at once — the
// disc's tint AND the mark on that tint — which is the tightest ground a mark
// can be measured against, and both failed WCAG 1.4.11's 3:1 in dark
// (#4E7C5E 2.875:1, #9A6B2F 2.962:1 on their own 16 % disc over duskDeep).
//
// This measures the ACTUAL rendered pair — the CircleAvatar's composited
// background and the Icon's colour — so it tracks the widget rather than a
// copy of its constants.

import 'dart:math' as math;

import 'package:api_client/api_client.dart' show ActivityRow;
import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/activity_timeline_list.dart';

double _luminance(Color c) {
  double chan(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// `Color.withValues(alpha:)` does not composite — it just carries the alpha —
/// so the ground a glyph actually lands on is the tint resolved over the card.
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

ActivityRow _row(String kind, String id) => ActivityRow(
      id: id,
      kind: kind,
      startedAt: DateTime.utc(2026, 8, 5, 9),
      summary: switch (kind) {
        'lift' => {'title': 'Squats', 'set_count': 3, 'volume_kg': 100},
        'meal' => {'item_name': 'Oats', 'calories': 300},
        _ => {'distance_m': 5000, 'duration_s': 1500},
      },
    );

void main() {
  for (final entry in {'light': AppTheme.light, 'dark': AppTheme.dark}.entries) {
    testWidgets('${entry.key}: every timeline kind glyph clears 3:1 on its own disc',
        (tester) async {
      final theme = entry.value;
      final kinds = ['run', 'lift', 'meal'];
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ActivityTimelineList(
            activities: [
              for (var i = 0; i < kinds.length; i++) _row(kinds[i], 'id$i'),
            ],
            unit: DistanceUnit.km,
            onTapRun: (_) {},
            onTapLift: (_) {},
            onRefresh: () async {},
          ),
        ),
      ));
      await tester.pump();

      final avatars =
          tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).toList();
      // Assert the population, not only the property.
      expect(avatars, hasLength(kinds.length));

      final card = theme.cardTheme.color!;
      for (var i = 0; i < avatars.length; i++) {
        final tint = _over(avatars[i].backgroundColor!, card);
        final icon = avatars[i].child! as Icon;
        final ratio = _contrast(icon.color!, tint);
        expect(ratio, greaterThanOrEqualTo(3.0),
            reason: '${entry.key} ${kinds[i]} glyph on its own disc is '
                '${ratio.toStringAsFixed(3)}:1');
      }
    });
  }
}
