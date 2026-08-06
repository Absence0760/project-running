import 'package:flutter/material.dart';

/// How much room a [StatusPill] takes.
enum StatusPillSize {
  /// The dense one: a tag beside a title, several to a row.
  compact,

  /// The default: a status a surface is reporting about itself.
  standard,
}

/// A short status label in a stadium container.
///
/// Twenty-four of these had been built by hand, with **nine** different
/// paddings (6/1, 7/2, 8/1, 8/2, 8/3, 10/2, 10/4, 10/5, 10/6) and four
/// spellings of the label size — `labelSmall` (11sp), `labelMedium` (12sp),
/// `bodySmall` (which is *also* 12sp, so two of them looked identical and
/// tracked different tokens) and one bare `fontSize: 12`.
///
/// The fix is that the padding is no longer a choice: it follows the size,
/// which follows the type step. The two pairs are the two most common shipped
/// combinations, so the vast majority of pills do not move at all — the point
/// is that there are two rather than nine.
///
/// [foreground] is the label colour and must clear 4.5:1 against whatever
/// [fill] resolves to **composited over the surface the pill lands on**. When
/// the caller passes a tint of [foreground] itself as the [fill] — the
/// commonest shape here — that composite is the ground, not the card: a tint
/// over an already-tinted parent compounds (18 % over 14 % is 29.5 %, which
/// dropped a web pill to 3.345:1, decisions § 503).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.foreground,
    this.fill,
    this.outline,
    this.icon,
    this.dot = false,
    this.size = StatusPillSize.standard,
  }) : assert(!(dot && icon != null), 'a pill leads with a dot or an icon');

  /// Already localized — `ui_kit` has no catalogue, so a default could only be
  /// English (decisions § 492).
  final String label;

  final Color foreground;

  /// Null leaves the pill unfilled, which is what an [outline] is for.
  final Color? fill;
  final Color? outline;

  final IconData? icon;

  /// A filled disc in [foreground], for a pill whose whole job is live/idle.
  final bool dot;

  final StatusPillSize size;

  double get _fontSize => size == StatusPillSize.compact ? 11 : 12;

  /// The two shipped pairs, keyed by size rather than picked per site.
  EdgeInsets get _padding => size == StatusPillSize.compact
      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
      : const EdgeInsets.symmetric(horizontal: 10, vertical: 4);

  /// A glyph reads a shade larger than its cap height, so it is the label's
  /// size plus two — 13 beside 11sp, 14 beside 12sp, which is what every
  /// hand-built pill had converged on anyway.
  double get _iconSize => _fontSize + 2;

  /// Two thirds of the label, so the disc reads as a bullet rather than a
  /// second glyph: 8 beside 12sp, which is the size the one shipped dot used.
  double get _dotSize => (_fontSize * 2 / 3).roundToDouble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (size == StatusPillSize.compact
            ? theme.textTheme.labelSmall
            : theme.textTheme.labelMedium)
        ?.copyWith(color: foreground, fontWeight: FontWeight.w700);
    return Container(
      padding: _padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: outline == null ? null : Border.all(color: outline!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: _dotSize,
              height: _dotSize,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: foreground),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: _iconSize, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
