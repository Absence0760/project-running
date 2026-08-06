// Source-scan register for issue #666's other remainder: an alpha on a
// NON-boundary theme token.
//
// §510 made the ban on thinning `outline` / `outlineVariant` / `dividerColor`
// absolute — a token whose whole guarantee is a 3:1 floor has no headroom to
// spend — and left this class open with an unmeasured count. `primary`,
// `onSurface`, `primaryContainer`, `surface` and the rest DO have headroom, so
// a blanket ban would be wrong. What was actually missing was the measurement:
// none of these had ever been computed against the surface it paints on.
//
// So this is a REGISTER, not a ban. Every surviving thinning is count-pinned per
// file on §480's model, and each entry states the role and the measured number,
// so a NEW thinning fails until somebody measures it and a migrated file forces
// its entry's removal. The numbers themselves are computed, never written here:
// `packages/ui_kit/test/thinned_token_contrast_test.dart` derives each from the
// real `AppTheme` tokens, and pins every repair in both directions.
//
// The rule the register encodes, by role:
//   * FOREGROUND (text) — 4.5:1 composited on its real background.
//   * ICON / BORDER / meaningful mark — 3:1 composited. A boundary that is the
//     ONLY thing separating a container from its page is a mark, however
//     decorative it looks.
//   * a purely decorative WASH — nothing owed, but recorded, because a fill's
//     alpha changes what its own children composite against.
//   * a fill whose PRESENCE is a state signal is not a wash: 1.4.1 needs a
//     non-colour cue beside it. Every entry below that carries state names its
//     cue, because at these alphas (1.00-1.26:1) the tint cannot be the cue.
//
// When this test fails: compute the composited ratio on the surface the site
// actually paints on — not on the convenient plain background, which is §503's
// recorded trap and changed the answer for six of these — then either fix it or
// add an entry saying what you measured.

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _roots = ['lib', '../../packages/ui_kit/lib'];

/// The three tokens §510 bans outright. Their thinning is caught by
/// `outline_text_token_guard_test.dart`, which owns that rule; naming them here
/// keeps this register from quietly becoming a second, weaker home for it.
const _boundaryTokens = {'outline', 'outlineVariant'};

/// file -> exact expected count of thinned non-boundary tokens.
const _register = <String, int>{
  // Two 48x48 icon bubbles on a card (1.306/1.334 and 1.231/1.402). Washes:
  // the glyph inside each is the full-strength token and the row is labelled.
  'lib/screens/import_screen.dart': 2,
  // ICON, `onSurfaceVariant@0.7` on the page — 3.861/5.899, clears 3:1. The
  // 48 px empty-state glyph, with its title and body text beside it.
  'lib/screens/people_screen.dart': 1,
  // The plan-detail "today" row fill (1.003/1.140). Not the cue: the row's
  // leading slot carries a dot labelled `planDetailToday` and its weekday
  // abbreviation goes w700.
  'lib/screens/plan_detail_screen.dart': 1,
  // The two create-plan card fills (1.065/1.256). Washes now that each card's
  // border is full `primary` and carries the boundary at 10.337/7.260.
  'lib/screens/plan_new_screen.dart': 2,
  // A privacy-zone disc drawn on basemap TILES, so no ratio is computable at
  // all. The same call sets `borderColor` to full `primary` at 2 px, and a
  // full-strength cancel glyph sits at the centre — the boundary is carried by
  // things that do not depend on the imagery.
  'lib/screens/privacy_zones_screen.dart': 1,
  // The two unread-notification row tints (1.109/1.087). Not the cue: the
  // grouped row carries an unread-count badge and the single row a dot.
  'lib/screens/profile_screen.dart': 2,
  // Two map overlay panels. Their `onSurface` type clears 4.5:1 against both
  // tile extremes (>= 14.272/12.715), which bounds every tile between them.
  'lib/screens/route_builder_screen.dart': 2,
  // `onSurface@0.08` — the elevation chart's "no pace derivable here" fill, at
  // 1.173/1.196 an absence rather than a fourth band: deliberately fainter
  // than the palette's own 1.5:1 band floor and deliberately not in the
  // legend. Nothing is owed by a mark that is meant to read as the page.
  'lib/screens/run_detail_screen.dart': 1,
  // Two map overlay panels plus three washes (1.109/1.087, 1.143/1.162,
  // 1.184/1.207); the type and glyph on each is full strength.
  'lib/screens/run_screen.dart': 5,
  // The live stats panel, blurred over the map. Type >= 11.292/9.165 at both
  // tile extremes.
  'lib/widgets/collapsible_panel.dart': 1,
  // The multi-select selected-row fill (1.065/1.223), moved here with the row
  // itself when #666 C8 consolidated the two forks of it. Not the cue: the
  // leading slot forks `check_circle` / `radio_button_unchecked` and the row
  // carries `Semantics(selected:)`.
  'lib/widgets/run_list_tile.dart': 1,
  // `surface@0.95` over the PAGE, not a map — the only one of the family that
  // is not an overlay, and in dark it is a lighter fill on a darker page
  // (1.163:1), so its `dividerColor` border is what separates it.
  'lib/widgets/gym_execution_band.dart': 1,
  // Map overlay pill; its `success` label reads 4.839/6.397 at the worst tile.
  'lib/widgets/live_share_indicator.dart': 1,
  // The dev-only hint's fill (1.064/1.179). A wash now that its border is full
  // `error` at 3.271/4.179 and carries the boundary.
  'lib/widgets/missing_map_tiles_hint.dart': 1,
  // TEXT, `onInverseSurface@0.75` on the opaque inverse-surface card —
  // 7.295/5.135. 0.75 rather than 0.70 was already a computed choice.
  'lib/widgets/safety_nudge_banner.dart': 1,
  // The viewer's own leaderboard row (1.078/1.013 re-derived). Not the cue: the
  // row carries a `navYou` label beside the name and the name goes w700.
  'lib/widgets/segments_panel.dart': 1,
  // The overlay banner. Its callers include four map screens, so the tile
  // extremes are the honest background: type >= 14.272/12.715.
  'lib/widgets/top_banner.dart': 1,
  // Map overlay band over the live map, same shape as `gym_execution_band` but
  // a different substrate — which is why they are measured separately.
  'lib/widgets/workout_execution_band.dart': 1,
};

/// A theme token thinned by an alpha. `scheme` catches the sites that hold the
/// `ColorScheme` in a local instead of reading it through `theme`, which is how
/// `safety_nudge_banner` escaped §510's own count.
final _thinned = RegExp(
  r'(?:colorScheme|scheme)\s*\.\s*(\w+)\s*\.\s*with(?:Values|Opacity)\s*\(',
);

const _fixtures = <(String, bool)>[
  // must register
  ('color: theme.colorScheme.primary.withValues(alpha: 0.06)', true),
  ('color: theme.colorScheme.primaryContainer.withOpacity(0.4)', true),
  ('color: scheme.onInverseSurface.withValues(alpha: 0.75)', true),
  ('color: theme.colorScheme.surface\n    .withValues(alpha: 0.95),', true),
  ('color: t.colorScheme.onSurface . withOpacity ( 0.4 )', true),
  // must not: the bare token, a non-scheme colour, and the three §510 owns.
  ('color: theme.colorScheme.primary', false),
  ('color: Colors.black.withValues(alpha: 0.55)', false),
  ('color: AppTheme.parchment.withOpacity(0.55)', false),
  ('color: theme.colorScheme.outline.withValues(alpha: 0.6)', false),
  ('color: theme.colorScheme.outlineVariant.withOpacity(0.5)', false),
];

/// Whether [match] is a thinning this register owns, rather than one §510 bans.
bool owned(RegExpMatch match) => !_boundaryTokens.contains(match.group(1));

void main() {
  test('the matcher decides every fixture the way the rule says', () {
    final wrong = <String>[];
    for (final (source, shouldRegister) in _fixtures) {
      final got = _thinned.allMatches(source).any(owned);
      if (got != shouldRegister) {
        wrong.add('expected register=$shouldRegister, got $got for: $source');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('a thinning in a comment or a string is not a use', () {
    const cases = [
      '// color: theme.colorScheme.primary.withValues(alpha: 0.06),\n',
      '/// 31 sites thin colorScheme.primary.withOpacity(0.6) unmeasured\n',
      "const k = 'colorScheme.primary.withOpacity(0.4)';\n",
    ];
    for (final source in cases) {
      expect(_thinned.hasMatch(blankNonCode(source)), isFalse,
          reason: 'still matched after blanking: $source');
    }
  });

  test('every scanned root exists', () {
    for (final root in _roots) {
      expect(rootExists(root), isTrue,
          reason: '$root is scanned but missing — if the package moved, move '
              'this entry with it so the scan stays whole.');
    }
  });

  test('every thinned non-boundary token is registered with its measurement',
      () {
    final violations = <String>[];
    final seen = <String, int>{};
    for (final root in _roots) {
      for (final file in dartFiles(root)) {
        final src = blankNonCode(file.readAsStringSync());
        for (final m in _thinned.allMatches(src)) {
          if (!owned(m)) continue;
          seen[file.path] = (seen[file.path] ?? 0) + 1;
        }
      }
    }
    for (final entry in seen.entries) {
      final allowed = _register[entry.key];
      if (allowed == null) {
        violations.add('${entry.key}: ${entry.value} thinned theme token(s), '
            'none registered. Compute the composited ratio on the surface the '
            'site paints on — 4.5:1 if it is type, 3:1 if it is an icon, a '
            'border or any mark that carries meaning — then fix it or record '
            'the number here.');
      } else if (entry.value != allowed) {
        violations.add('${entry.key}: ${entry.value} thinned theme token(s), '
            'register expects $allowed. A new alpha in an already-registered '
            'file is a new measurement, not a covered one.');
      }
    }
    for (final entry in _register.entries) {
      if (!seen.containsKey(entry.key)) {
        violations.add('${entry.key}: register expects ${entry.value} '
            'thinning(s) but found none — migrated? Remove the entry.');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
