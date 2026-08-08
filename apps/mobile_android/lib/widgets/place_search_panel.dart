import 'package:flutter/material.dart';

import '../geocoding.dart';
import '../l10n/gen/app_localizations.dart';

/// The body of the place-search dropdown shared by the three map screens
/// that carry one (privacy zones, routes heatmap, route builder).
///
/// It exists to keep those three honest about the same distinction the
/// web dropdown makes: a provider that failed is NOT a place that does
/// not exist. All three used to render `if (_searchOpen && results
/// .isNotEmpty)`, so a failed lookup — and an empty one — produced no
/// feedback at all.
class PlaceSearchPanel extends StatelessWidget {
  final List<PlaceResult> results;

  /// True when the last lookup came back [PlaceSearchStatus.unavailable].
  /// Takes precedence over an empty [results]: the runner needs to know
  /// the search failed before anything else.
  final bool unavailable;

  final ValueChanged<PlaceResult> onSelect;
  final VoidCallback onRetry;

  const PlaceSearchPanel({
    super.key,
    required this.results,
    required this.unavailable,
    required this.onSelect,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    if (unavailable) {
      return ListTile(
        key: const Key('place-search-unavailable'),
        dense: true,
        leading: Icon(Icons.cloud_off, color: cs.error),
        title: Text(l10n.placeSearchUnavailable),
        trailing: TextButton(
          onPressed: onRetry,
          child: Text(l10n.placeSearchRetry),
        ),
      );
    }

    if (results.isEmpty) {
      return ListTile(
        key: const Key('place-search-empty'),
        dense: true,
        leading: const Icon(Icons.search_off),
        title: Text(l10n.placeSearchNoResults),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        for (final r in results)
          ListTile(
            dense: true,
            leading: const Icon(Icons.place),
            title: Text(
              r.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelect(r),
          ),
      ],
    );
  }
}
