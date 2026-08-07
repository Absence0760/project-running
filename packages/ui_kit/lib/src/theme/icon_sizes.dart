/// The icon-size scale, derived from what the app already draws rather than
/// invented alongside it.
///
/// Issue #666 V14 recorded "18 (×113), 16 (×55), 20 (×24), 14 (×23), 13 (×14),
/// plus one-offs at 11, 12, 22, 26, 28" and prescribed a three-rung scale of
/// inline 16 / leading 20 / illustration 48. Re-measured, the counts are 18×113,
/// 16×54, 14×21, 20×20, 13×13, 48×15 — and the one-off set is larger than the
/// finding listed: 6, 24, 32, 36, 40 and 60 ship too. Adopting the prescribed
/// scale would have moved the app's single most common size (18, more than
/// twice the next) onto a rung it does not use, restyling 113 call sites to
/// close a consistency finding.
///
/// So the rungs below are the clusters the app converged on by itself, and the
/// work was migrating the 22 one-off sites onto the nearest one. `icon_size_
/// guard_test.dart` pins the SET rather than the call sites: a size outside the
/// scale fails, a literal that equals a rung does not. That is deliberately
/// weaker than the `fontSize:` ban — type has a `textTheme` to name a step
/// with, and an `Icon` has no equivalent, so requiring every site to import a
/// constant buys naming rather than consistency.
abstract final class AppIconSize {
  /// Inside a dense chip or a stat row's label.
  static const double dense = 14;

  /// Beside body text — a metric row, an inline affordance.
  static const double inline = 16;

  /// The app's default: a list-row leading glyph, a toolbar action.
  static const double standard = 18;

  /// A leading glyph that anchors a taller row.
  static const double leading = 20;

  /// Material's own default, for anything that inherits it deliberately.
  static const double material = 24;

  /// The glyph in an empty / error state.
  static const double illustration = 48;

  /// A hero illustration on an onboarding or empty surface.
  static const double hero = 64;

  /// Every rung, for the guard and for a caller that needs to snap a value.
  static const List<double> scale = [
    dense,
    inline,
    standard,
    leading,
    material,
    illustration,
    hero,
  ];
}
