import 'package:flutter/material.dart';

/// Verified-club badge — a small ✓-in-a-rosette icon shown next to a
/// club's name (or an event title whose parent club is verified)
/// indicating the entity has been manually confirmed as the
/// authentic operator.
///
/// Why this exists: `clubs.name` is NOT unique (only `clubs.slug`
/// is), so a fan can register "Richmond Marathon" before the
/// official organisation does. The badge differentiates the
/// verified-as-official surface from the squatter / fan surface.
///
/// Twin of the Svelte `VerifiedBadge` component; both render the
/// same icon + accessible label so cross-platform users learn one
/// mark.
class VerifiedBadge extends StatelessWidget {
  /// Edge length in dp. Default 16 matches the inline-with-text
  /// rendering on club tiles + event titles. Larger sizes work for
  /// hero headers.
  final double size;

  /// Tooltip + accessibility label. Defaults to the standard copy
  /// "Official verified club" so screen readers + hover tooltips
  /// both surface the meaning.
  final String tooltip;

  const VerifiedBadge({
    super.key,
    this.size = 16,
    this.tooltip = 'Official verified club',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: Icon(
          Icons.verified,
          size: size,
          // Same blue (`#2563eb`) the Svelte twin uses so the badge
          // reads identically across web + mobile.
          color: const Color(0xFF2563EB),
          semanticLabel: tooltip,
        ),
      ),
    );
  }
}
