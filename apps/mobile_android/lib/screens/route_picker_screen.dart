import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';

/// Full-screen route picker — the modern replacement for the old
/// `showModalBottomSheet` route list. The user reported two
/// concrete asks against the modal:
///
///   1. **It's still using the old modal pattern** — every other
///      create / pick flow on mobile is now a `MaterialPageRoute`
///      with an AppBar + back button (per the modal-vs-page user
///      feedback from earlier rounds). The route picker was the
///      one outlier.
///   2. **Starred routes should show first** — the user-starred
///      "watch-favourite" set is the practical short-list for
///      picking a route to run today; surfacing those at the top
///      saves a scroll past dozens of imported routes.
///
/// Plus a third affordance that pairs naturally with point 1:
///
///   3. **Search** — a TextField at the top of the page filters
///      the list by case-insensitive name substring. Library of
///      50+ routes becomes navigable with a single short typed
///      query.
///
/// Open via [pickRoute]; returns the chosen route, or `null` for
/// either "No route" or Cancel.
class RoutePickerScreen extends StatefulWidget {
  final List<cm.Route> routes;
  final DistanceUnit unit;

  const RoutePickerScreen({
    super.key,
    required this.routes,
    required this.unit,
  });

  @override
  State<RoutePickerScreen> createState() => _RoutePickerScreenState();
}

class _RoutePickerScreenState extends State<RoutePickerScreen> {
  late final TextEditingController _searchCtl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  /// Filter (by name substring) + sort (starred first, then
  /// case-insensitive name). Pure — no SetState side-effects.
  List<cm.Route> _filteredAndSorted() {
    final term = _search.trim().toLowerCase();
    final filtered = term.isEmpty
        ? List<cm.Route>.from(widget.routes)
        : widget.routes
            .where((r) => r.name.toLowerCase().contains(term))
            .toList();
    filtered.sort((a, b) {
      // Starred routes first.
      if (a.isStarred != b.isStarred) {
        return a.isStarred ? -1 : 1;
      }
      // Then by name, case-insensitive.
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final routes = _filteredAndSorted();
    final hasStarred = routes.any((r) => r.isStarred);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.routePickerTitle),
        // "No route" lives as a leading-style trailing action so
        // users running without a preselected route can dismiss
        // back to the run screen without scrolling.
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<cm.Route?>(context, null),
            child: Text(l10n.routePickerNoRoute),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtl,
                autofocus: false,
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: l10n.routePickerClearSearchTooltip,
                          onPressed: () {
                            _searchCtl.clear();
                            setState(() => _search = '');
                          },
                        ),
                  hintText: l10n.routePickerSearchHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            if (routes.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _search.trim().isEmpty
                          ? l10n.routePickerEmptyNoRoutes
                          : l10n.routePickerEmptyNoMatch(_search),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: routes.length +
                      (hasStarred && _search.trim().isEmpty ? 2 : 0),
                  itemBuilder: (context, index) {
                    // When at least one starred route is in the
                    // filtered set AND the user isn't searching,
                    // surface a small section header above the
                    // starred block, then a divider between
                    // starred and the rest.
                    if (hasStarred && _search.trim().isEmpty) {
                      if (index == 0) {
                        return _SectionHeader(
                          icon: Icons.star,
                          label: l10n.routePickerStarredHeader,
                          color: const Color(0xFFFBBF24),
                        );
                      }
                      // Find the index of the first non-starred
                      // route to insert the second section header.
                      final firstUnstarred =
                          routes.indexWhere((r) => !r.isStarred);
                      if (firstUnstarred > 0 && index == firstUnstarred + 1) {
                        return _SectionHeader(
                          icon: Icons.route,
                          label: l10n.routePickerAllRoutesHeader,
                          color: theme.colorScheme.onSurfaceVariant,
                        );
                      }
                      // Translate the rendered index → routes
                      // index, accounting for the inserted
                      // header rows.
                      final routeIdx = (firstUnstarred > 0 &&
                              index > firstUnstarred + 1)
                          ? index - 2
                          : index - 1;
                      if (routeIdx < 0 || routeIdx >= routes.length) {
                        return const SizedBox.shrink();
                      }
                      return _RouteTile(
                        route: routes[routeIdx],
                        unit: widget.unit,
                      );
                    }
                    return _RouteTile(
                      route: routes[index],
                      unit: widget.unit,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  final cm.Route route;
  final DistanceUnit unit;
  const _RouteTile({required this.route, required this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(
          route.isStarred ? Icons.star : Icons.route,
          color: route.isStarred
              ? const Color(0xFFFBBF24)
              : theme.colorScheme.secondary,
        ),
      ),
      title: Text(
        route.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        UnitFormat.distance(route.distanceMetres, unit),
      ),
      onTap: () => Navigator.pop<cm.Route?>(context, route),
    );
  }
}

/// Opens the picker as a full-screen page. Returns the chosen
/// route, `null` for "No route" or Cancel, or `null` if the user
/// backs out without selecting.
Future<cm.Route?> pickRoute(
  BuildContext context, {
  required List<cm.Route> routes,
  required DistanceUnit unit,
}) {
  return Navigator.of(context).push<cm.Route?>(
    MaterialPageRoute(
      builder: (_) => RoutePickerScreen(routes: routes, unit: unit),
      fullscreenDialog: true,
    ),
  );
}
