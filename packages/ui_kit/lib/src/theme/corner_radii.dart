/// The corner-radius scale, derived from what the app already draws.
///
/// Issue #666 V15 counted eleven values across "199 hand-rolled `BoxDecoration`
/// containers" and prescribed three tokens: 8, 12 and 999. Re-measured, the
/// container count is **173** and the distribution is 12×45, 8×33, 6×22, 16×21,
/// 4×17, 20×14, 14×12, 10×7, 999×7, 2×5, 3×2 — so the finding's own pill figure
/// was 33 when the real one is **7**, and both 6 and 16 outrank it three-to-one.
/// A three-token scale of 8/12/999 would have moved a fifth of the app's
/// corners onto a rung chosen partly on a count that was off by 26.
///
/// The rungs below cut the value set from eleven to seven while moving no
/// corner by more than 2 dp: the strays (2, 3 → 4; 6 → 8; 10, 14 → 12) snap to the nearest rung,
/// ties going to the more common one. `corner_radius_guard_test.dart` pins the
/// SET, on the same reasoning as `AppIconSize` — a `BorderRadius` has no theme
/// step to name, so requiring a constant at 185 call sites would buy naming
/// rather than consistency.
abstract final class AppRadius {
  /// A chip's inner tint, a progress track, a hairline swatch.
  static const double xs = 4;

  /// A dense inline surface — a badge, a small tile.
  static const double sm = 8;

  /// The default: a card, a sheet, a bordered container.
  static const double md = 12;

  /// A larger panel or a modal's top corners.
  static const double lg = 16;

  /// A hero surface — the biggest rounded rectangle in ordinary layout.
  static const double xl = 20;

  /// A sheet's top corners. The run screen's collapsible stats panel is the
  /// only surface at this rung, and it keeps it: snapping it to `xl` would
  /// have restyled the recording screen's most prominent surface to save one
  /// value, and the recording stack is the last place to spend a visual change
  /// on tidiness.
  static const double sheet = 24;

  /// A pill: a status chip, a filter chip, an avatar ring.
  static const double pill = 999;

  /// Every rung, for the guard and for a caller that needs to snap a value.
  static const List<double> scale = [xs, sm, md, lg, xl, sheet, pill];
}
