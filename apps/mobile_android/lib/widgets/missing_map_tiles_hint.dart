import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Inline diagnostic shown on map-bearing screens when
/// `dotenv.env['MAPTILER_KEY']` is missing or empty. The user
/// reported "I'm still not seeing the map" multiple times across
/// rounds — root cause is almost always that the dev build's
/// `.env.local` doesn't actually carry the key. Rendering a small
/// banner instead of a silently-blank map makes the failure mode
/// diagnosable from the device without scrolling logs.
///
/// Returns `SizedBox.shrink()` when the key IS set — production
/// builds with a configured key see nothing.
///
/// Why a widget vs a console-print: the user is reporting visible
/// UX. The diagnostic has to BE visible.
class MissingMapTilesHint extends StatelessWidget {
  /// If non-null, overrides the env probe — exposed for tests
  /// only so widget tests can pump both branches without booting
  /// dotenv.
  @visibleForTesting
  final bool? envKeyPresentOverride;

  const MissingMapTilesHint({
    super.key,
    this.envKeyPresentOverride,
  });

  bool get _keyPresent {
    if (envKeyPresentOverride != null) return envKeyPresentOverride!;
    try {
      return (dotenv.env['MAPTILER_KEY'] ?? '').isNotEmpty;
    } catch (_) {
      // dotenv may not be initialised in some test paths — treat
      // as "no key" so the diagnostic surfaces rather than crashing.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_keyPresent) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.map_outlined,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Map tiles disabled',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Set MAPTILER_KEY in apps/mobile_android/.env.local '
                  'and rebuild the app. The route polyline still '
                  'renders correctly; only the basemap tiles are '
                  'missing.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
