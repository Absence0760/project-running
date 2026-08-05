import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// The measured half of "an alpha on a NON-boundary token is allowed, once you
/// have computed what it lands on" (issue #666, the class §510 left open with
/// an unmeasured count).
///
/// §510 made the ban on thinning `outline` / `outlineVariant` / `dividerColor`
/// absolute, because a token whose whole guarantee is a 3:1 floor has no
/// headroom to spend. `primary`, `onSurface`, `primaryContainer` and the rest
/// DO have headroom, so a blanket ban would be wrong — but "has headroom" is
/// not the same as "clears the floor", and none of these had ever been
/// computed. Every figure below is derived from the real `AppTheme` tokens on
/// the surface each site actually paints on, which is §503's recorded trap: the
/// six sites that stack a tint on an already-tinted parent all read differently
/// on the convenient plain background.
///
/// Each fix is pinned in BOTH directions — the replacement clears its floor AND
/// the value it replaced did not — so a future revert is a failure rather than
/// a silent regression. The source-side companion is
/// `apps/mobile_android/test/thinned_token_register_test.dart` (both twins),
/// which keeps the surviving thinnings countable.
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

/// [token] at [alpha] composited over [bg]. `Color.alphaBlend` is the same
/// 8-bit sRGB src-over the framework uses when it paints the thinned colour,
/// so this is the pixel the user sees rather than an approximation of it.
Color _thin(Color token, double alpha, Color bg) =>
    Color.alphaBlend(token.withValues(alpha: alpha), bg);

const _aaText = 4.5;
const _aaMark = 3.0;

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    final s = theme.colorScheme;
    final scaffold = theme.scaffoldBackgroundColor;
    final card = theme.cardTheme.color!;
    final sCHighest = s.surfaceContainerHighest;

    group('$name surviving foreground thinnings', () {
      test('the nudge banner secondary action clears AA as text', () {
        // `onInverseSurface` at 0.75 on the opaque `inverseSurface` card. 0.75
        // rather than 0.7 is a previously-computed choice; this is the number.
        expect(
          _contrast(_thin(s.onInverseSurface, 0.75, s.inverseSurface),
              s.inverseSurface),
          greaterThanOrEqualTo(_aaText),
        );
      });

      test('the empty-state glyph clears the non-text floor', () {
        expect(
          _contrast(_thin(s.onSurfaceVariant, 0.7, scaffold), scaffold),
          greaterThanOrEqualTo(_aaMark),
        );
      });
    });

    group('$name repaired sites', () {
      test('the coach-card subtitle: 0.8 failed AA, full does not', () {
        final bg = s.primaryContainer;
        expect(_contrast(s.onPrimaryContainer, bg),
            greaterThanOrEqualTo(_aaText));
        if (name == 'light') {
          // 4.470:1 — under AA by a margin no eye would catch, which is why it
          // shipped. Dark read 5.276:1, so only one brightness ever failed.
          expect(_contrast(_thin(s.onPrimaryContainer, 0.8, bg), bg),
              lessThan(_aaText));
        }
      });

      test('the map-tiles hint border is its only boundary', () {
        final fill = _thin(s.errorContainer, 0.4, scaffold);
        expect(_contrast(s.error, fill), greaterThanOrEqualTo(_aaMark));
        expect(_contrast(_thin(s.error, 0.3, fill), fill), lessThan(_aaMark));
      });

      test('the first-run prompt border is its only boundary', () {
        final fill = _thin(s.primary, 0.06, scaffold);
        expect(_contrast(s.primary, fill), greaterThanOrEqualTo(_aaMark));
        expect(_contrast(_thin(s.primary, 0.18, fill), fill),
            lessThan(_aaMark));
      });

      test('the last-run placeholder glyph is its only content', () {
        final fill = _thin(s.primary, 0.08, sCHighest);
        expect(_contrast(s.primary, fill), greaterThanOrEqualTo(_aaMark));
        if (name == 'dark') {
          // 3.148 light / 2.847 dark — the light theme passed and the dark did
          // not, the opposite way round from §510's `outline` finding, which is
          // why the per-brightness gate is on the failing side each time.
          expect(_contrast(_thin(s.primary, 0.6, fill), fill),
              lessThan(_aaMark));
        }
      });

      test('the two create-plan card borders', () {
        final fill = _thin(s.primaryContainer, 0.4, scaffold);
        expect(_contrast(s.primary, fill), greaterThanOrEqualTo(_aaMark));
        expect(_contrast(_thin(s.primary, 0.4, fill), fill), lessThan(_aaMark));
      });

      test('the calorie goal line could not simply be un-thinned', () {
        expect(_contrast(s.outline, card), greaterThanOrEqualTo(_aaMark));
        if (name == 'light') {
          // 2.006:1 thinned — and the finding that decided the token, rather
          // than merely the alpha: light `secondary` was coralDeep, 2.767:1 on
          // parchment at FULL strength, so un-thinning would have left the mark
          // failing. A thinning is not always a thinning problem. Dark read
          // 4.402:1 thinned, so only light ever failed. The colour is named
          // directly because light `secondary` has since moved to coralMark:
          // that repaired the token, it did not make the old figure untrue, and
          // the line keeps `outline` because a boundary is what it draws.
          expect(_contrast(_thin(AppTheme.coralDeep, 0.7, card), card),
              lessThan(_aaMark));
          expect(_contrast(AppTheme.coralDeep, card), lessThan(_aaMark));
        }
      });

      test('both calorie-trend bar hues clear the floor on their card', () {
        expect(_contrast(s.primary, sCHighest), greaterThanOrEqualTo(_aaMark));
        expect(_contrast(s.outline, sCHighest), greaterThanOrEqualTo(_aaMark));
        expect(_contrast(_thin(s.primary, 0.45, sCHighest), sCHighest),
            lessThan(_aaMark));
        // Pairwise they are NOT 3:1 apart, which §495 established is
        // unreachable for a series once each also owes 3:1 to its surface —
        // hence the weekday label's weight carrying the today distinction.
        expect(_contrast(s.primary, s.outline), lessThan(_aaMark));
      });

      test('the elevation-chart crosshair over the faintest band', () {
        // §503's trap: measured on the bare page it read 2.9x; the band it
        // actually crosses is fainter still, so the honest background is the
        // composite, not the scaffold.
        final faintest = _thin(s.onSurface, 0.08, scaffold);
        expect(_contrast(s.outline, faintest), greaterThanOrEqualTo(_aaMark));
        if (name == 'light') {
          expect(_contrast(_thin(s.onSurface, 0.4, faintest), faintest),
              lessThan(_aaMark));
        }
      });
    });

    // The nine translucent panels over the live map have no deterministic
    // background at all, so the floor is checked against the extremes a tile
    // can be. Passing at both bounds passes for every tile between them.
    group('$name map-overlay panels bound their own worst case', () {
      const alphas = [0.85, 0.90, 0.92, 0.94, 0.95];
      for (final a in alphas) {
        test('onSurface on surface@$a clears AA over white and black tiles',
            () {
          for (final tile in const [Color(0xFFFFFFFF), Color(0xFF000000)]) {
            final panel = _thin(s.surface, a, tile);
            expect(_contrast(s.onSurface, panel), greaterThanOrEqualTo(_aaText),
                reason: 'surface@$a over $tile');
          }
        });
      }

      test('the live-share label clears AA over both tile extremes', () {
        final success = theme.extension<AppSemanticColors>()!.success;
        for (final tile in const [Color(0xFFFFFFFF), Color(0xFF000000)]) {
          final panel = _thin(s.surface, 0.92, tile);
          expect(_contrast(success, panel), greaterThanOrEqualTo(_aaText),
              reason: 'success on surface@0.92 over $tile');
        }
      });
    });
  }
}
