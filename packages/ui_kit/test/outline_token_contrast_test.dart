import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// The measured half of the `outline`-is-not-a-text-colour rule (issue #666,
/// the S7 follow-up §487/§505 left open). `colorScheme.outline` is the 3:1
/// BOUNDARY token; `onSurfaceVariant` is the muted TEXT token.
///
/// Both are computed against every surface the app actually paints on, because
/// measuring on one convenient background is the trap §503 recorded — and it
/// changes the answer here. `outline` fails AA on *every* light surface
/// (4.058:1 down to 3.481:1) but reads 5.117:1 on the dark card, so the rule
/// is not "outline always fails as text": it is that `outline` cannot be
/// relied on as text, while `onSurfaceVariant` can. The tests below assert
/// exactly that, per brightness.
///
/// The source-side companion is
/// `apps/mobile_android/test/outline_text_token_guard_test.dart` (both twins),
/// which keeps text off `outline` in the first place.
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

/// Surfaces muted TYPE lands on, enumerated from the call sites: the card and
/// the page, the three container steps a chip or a table header uses, and
/// `tertiaryContainer` — the fill a completed plan-calendar cell takes, whose
/// day numeral and kind label are muted type.
Map<String, Color> _textSurfaces(ThemeData t) {
  final s = t.colorScheme;
  return {
    'card': t.cardTheme.color!,
    'scaffold': t.scaffoldBackgroundColor,
    'surfaceContainerHighest': s.surfaceContainerHighest,
    'surfaceContainerHigh': s.surfaceContainerHigh,
    'surfaceContainer': s.surfaceContainer,
    'tertiaryContainer': s.tertiaryContainer,
  };
}

/// Surfaces an `outline` MARK lands on. Deliberately not `tertiaryContainer`:
/// no surviving mark sits on it and `outline` reads 2.952:1 there in dark, so
/// a mark added over that fill owes a re-measurement, not an assumption.
Map<String, Color> _markSurfaces(ThemeData t) {
  final s = t.colorScheme;
  return {
    'card': t.cardTheme.color!,
    'scaffold': t.scaffoldBackgroundColor,
    'surfaceContainerHighest': s.surfaceContainerHighest,
    'surfaceContainerHigh': s.surfaceContainerHigh,
    'surfaceContainer': s.surfaceContainer,
  };
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    group('$name muted-text token', () {
      test('onSurfaceVariant clears 4.5:1 as text on every real surface', () {
        _textSurfaces(theme).forEach((where, bg) {
          expect(_contrast(theme.colorScheme.onSurfaceVariant, bg),
              greaterThanOrEqualTo(4.5),
              reason: 'onSurfaceVariant on $where');
        });
      });

      test('outline cannot be relied on as text — it fails AA on at least one '
          'real surface', () {
        final failures = <String, double>{};
        _textSurfaces(theme).forEach((where, bg) {
          final ratio = _contrast(theme.colorScheme.outline, bg);
          if (ratio < 4.5) failures[where] = ratio;
        });
        expect(failures, isNotEmpty,
            reason: 'outline now clears AA everywhere in $name — if the '
                'palette moved, this rule needs rewriting rather than '
                'relaxing, and the source guard should be revisited with it');
      });

      test('outline still clears 1.4.11\'s 3:1 wherever a mark uses it', () {
        _markSurfaces(theme).forEach((where, bg) {
          expect(_contrast(theme.colorScheme.outline, bg),
              greaterThanOrEqualTo(3.0),
              reason: 'outline on $where — the boundary use is what the token '
                  'is for, so it owes 3:1 there');
        });
      });

      test('onSurfaceVariant is the higher-contrast step of the two', () {
        final s = theme.colorScheme;
        final card = theme.cardTheme.color!;
        expect(_contrast(s.onSurfaceVariant, card),
            greaterThan(_contrast(s.outline, card)));
      });
    });
  }
}
