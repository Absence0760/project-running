import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        ActivityLoaderKind,
        AppSemanticColors,
        FullBodyLoader,
        IdentityAvatar,
        StatGrid,
        StatTile;

import '../backend_timeout.dart';
import '../catalogue_browse.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../widgets/error_state.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/track_preview.dart';

/// Localized name for a stored `surface` token. An unrecognised value is
/// returned VERBATIM: the CHECK constraint means a stray token can only appear
/// when this client is older than the database, and a prettified guess is
/// indistinguishable from a real translation. Mirrors web's
/// `routeSurfaceLabel`.
String catalogueSurfaceLabel(AppLocalizations l10n, String surface) =>
    switch (surface) {
      'road' => l10n.routesSurfaceRoad,
      'trail' => l10n.routesSurfaceTrail,
      'mixed' => l10n.routesSurfaceMixed,
      _ => surface,
    };

/// Browse list for the curated famous-segment catalogue (decisions §233).
/// Mobile mirror of web `/segments`: search with accent folding, region and
/// surface filters, four sorts — all shaped by the `catalogue_browse.dart`
/// parity pair over the whole fetched catalogue, so a keystroke costs no
/// round-trip.
///
/// The catalogue is world-readable, so this screen works signed out — unlike
/// the leaderboard on [GlobalSegmentDetailScreen].
class GlobalSegmentsScreen extends StatefulWidget {
  final ApiClient? api;

  const GlobalSegmentsScreen({super.key, this.api});

  @override
  State<GlobalSegmentsScreen> createState() => _GlobalSegmentsScreenState();
}

class _GlobalSegmentsScreenState extends State<GlobalSegmentsScreen> {
  List<GlobalSegmentRow> _segments = const [];
  bool _loading = true;
  bool _error = false;

  String _query = '';
  String? _region;
  String? _surface;
  CatalogueSort _sort = CatalogueSort.name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _error = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final segments =
          await api.fetchGlobalSegments().timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _segments = segments;
        _loading = false;
      });
    } catch (_) {
      // Surfaced rather than degraded to an empty list: "the catalogue is
      // empty" and "the fetch failed" are different claims, and only one of
      // them is worth offering a retry for.
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _query = '';
      _region = null;
      _surface = null;
      _sort = CatalogueSort.name;
    });
  }

  void _open(String segmentId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          GlobalSegmentDetailScreen(api: widget.api, segmentId: segmentId),
    ));
  }

  static String _sortLabel(AppLocalizations l10n, CatalogueSort sort) =>
      switch (sort) {
        CatalogueSort.name => l10n.segmentCatalogueSortName,
        CatalogueSort.shortest => l10n.segmentCatalogueSortShortest,
        CatalogueSort.longest => l10n.segmentCatalogueSortLongest,
        CatalogueSort.climb => l10n.segmentCatalogueSortClimb,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.segmentCatalogueTitle)),
      body: _loading
          ? FullBodyLoader(
              kind: ActivityLoaderKind.run,
              label: l10n.segmentsPanelLoading,
            )
          : _error
              ? ErrorState(
                  message: l10n.segmentCatalogueLoadFailed,
                  onRetry: _load,
                )
              : _segments.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.segmentCatalogueEmpty,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _buildCatalogue(context, l10n),
    );
  }

  Widget _buildCatalogue(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final catalogue = [
      for (final s in _segments)
        CatalogueSegment(
          id: s.id,
          name: s.name,
          surface: s.surface,
          region: s.region,
          distanceM: s.distanceM,
          elevationM: s.elevationM,
        ),
    ];
    final regions = catalogueRegions(catalogue);
    final surfaces = catalogueSurfaces(catalogue);
    final shown = sortCatalogue(
      filterCatalogue(
        catalogue,
        query: _query,
        region: _region,
        surface: _surface,
      ),
      _sort,
    );
    final filtered =
        _query.trim().isNotEmpty || _region != null || _surface != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          l10n.segmentCatalogueIntro,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: l10n.segmentCatalogueSearchLabel,
            hintText: l10n.segmentCatalogueSearchHint,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // A one-value dropdown filters nothing — it only offers the
            // selection the list already is.
            if (regions.length > 1)
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _region,
                  isDense: true,
                  hint: Text(l10n.segmentCatalogueAllRegions),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.segmentCatalogueAllRegions),
                    ),
                    for (final r in regions)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (v) => setState(() => _region = v),
                ),
              ),
            if (surfaces.length > 1)
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _surface,
                  isDense: true,
                  hint: Text(l10n.segmentCatalogueAllSurfaces),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.segmentCatalogueAllSurfaces),
                    ),
                    for (final s in surfaces)
                      DropdownMenuItem(
                        value: s,
                        child: Text(catalogueSurfaceLabel(l10n, s)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _surface = v),
                ),
              ),
            DropdownButtonHideUnderline(
              child: DropdownButton<CatalogueSort>(
                value: _sort,
                isDense: true,
                items: [
                  for (final s in CatalogueSort.values)
                    DropdownMenuItem(value: s, child: Text(_sortLabel(l10n, s))),
                ],
                onChanged: (v) =>
                    v == null ? null : setState(() => _sort = v),
              ),
            ),
            if (filtered || _sort != CatalogueSort.name)
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.close, size: 16),
                label: Text(l10n.segmentsPanelResetFilters),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // One live region whose CONTENTS swap rather than one per branch: a
        // status node that is removed when the result set empties announces
        // nothing on the transition that most needs announcing.
        Semantics(
          liveRegion: true,
          child: Text(
            shown.isEmpty
                ? l10n.segmentCatalogueNoMatches
                : l10n.segmentCatalogueCount(shown.length),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 8),
        for (final segment in shown) ...[
          _CatalogueCard(segment: segment, onTap: () => _open(segment.id)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CatalogueCard extends StatelessWidget {
  final CatalogueSegment segment;
  final VoidCallback onTap;

  const _CatalogueCard({required this.segment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final elevation = segment.elevationM;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        title: Text(segment.name, style: theme.textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (segment.region != null && segment.region!.trim().isNotEmpty)
                Text(segment.region!),
              const SizedBox(height: 4),
              Text(
                [
                  formatDistanceForPref((segment.distanceM ?? 0).toDouble()),
                  if (elevation != null && elevation > 0)
                    formatElevationForPref(elevation.toDouble()),
                  catalogueSurfaceLabel(l10n, segment.surface),
                ].join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// One catalogue segment: its curated geometry, key stats, description, and the
/// block-guarded leaderboard with the same gender / age-band tiers the
/// route-segment panel offers. Mobile mirror of web `/segments/[id]`.
class GlobalSegmentDetailScreen extends StatefulWidget {
  final ApiClient? api;
  final String segmentId;

  const GlobalSegmentDetailScreen({
    super.key,
    required this.api,
    required this.segmentId,
  });

  @override
  State<GlobalSegmentDetailScreen> createState() =>
      _GlobalSegmentDetailScreenState();
}

class _GlobalSegmentDetailScreenState extends State<GlobalSegmentDetailScreen> {
  GlobalSegmentRow? _segment;
  bool _loading = true;
  bool _loadFailed = false;

  // A null board is the loading state, so a rejected fetch that left it null
  // would read as "still loading" forever. The failure carries its own flag.
  List<GlobalSegmentLeaderboardEntry>? _board;
  bool _boardFailed = false;
  String? _gender;
  String? _ageBand;

  @override
  void initState() {
    super.initState();
    _loadSegment();
  }

  Future<void> _loadSegment() async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final segment = await api
          .fetchGlobalSegment(widget.segmentId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _segment = segment;
        _loading = false;
      });
      if (segment != null) await _refreshBoard();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  Future<void> _refreshBoard() async {
    final api = widget.api;
    // `global_segment_leaderboard` raises 42501 for an anonymous caller, so a
    // signed-out viewer gets the sign-in state rather than an error with a
    // retry that could never succeed.
    if (api == null || api.userId == null) return;
    setState(() {
      _board = null;
      _boardFailed = false;
    });
    try {
      final board = await api
          .fetchGlobalSegmentLeaderboard(
            widget.segmentId,
            gender: _gender,
            ageBand: _ageBand,
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() => _board = board);
    } catch (_) {
      if (!mounted) return;
      setState(() => _boardFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final segment = _segment;
    return Scaffold(
      appBar: AppBar(
        title: Text(segment?.name ?? l10n.segmentCatalogueTitle),
      ),
      body: _loading
          ? FullBodyLoader(
              kind: ActivityLoaderKind.run,
              label: l10n.segmentsPanelLoading,
            )
          : _loadFailed
              ? ErrorState(
                  message: l10n.segmentCatalogueDetailFailedTitle,
                  onRetry: _loadSegment,
                )
              : segment == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.segmentCatalogueNotFoundTitle,
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.segmentCatalogueNotFoundBody,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildDetail(context, l10n, segment),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    AppLocalizations l10n,
    GlobalSegmentRow segment,
  ) {
    final theme = Theme.of(context);
    // The catalogue geometry is public curated data, NOT any athlete's GPS
    // track, so it renders directly — there is no owner whose privacy
    // zones could apply, and nothing for `fetchClippedTrackForRun` to
    // protect.
    final geometry = ApiClient.globalSegmentGeometry(segment);
    final elevation = segment.elevationM;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (segment.region != null && segment.region!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.place,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    segment.region!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        StatGrid(
          cells: [
            StatTile.medium(
              label: l10n.segmentCatalogueStatDistance,
              value: formatDistanceForPref(segment.distanceM),
            ),
            if (elevation != null && elevation > 0)
              StatTile.medium(
                label: l10n.segmentCatalogueStatElevation,
                value: formatElevationForPref(elevation),
              ),
            StatTile.medium(
              label: l10n.segmentCatalogueStatSurface,
              value: catalogueSurfaceLabel(l10n, segment.surface),
            ),
          ],
        ),
        if (segment.description != null &&
            segment.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(segment.description!, style: theme.textTheme.bodyMedium),
        ],
        if (geometry.length >= 2) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: TrackPreview(points: geometry),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          l10n.segmentCatalogueLeaderboard,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        _buildBoard(context, l10n),
      ],
    );
  }

  Widget _buildBoard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final api = widget.api;
    if (api == null || api.userId == null) {
      return SizedBox(
        height: 220,
        child: SignInRequiredState(api: api, onSignedIn: _refreshBoard),
      );
    }
    final filtered = _gender != null || _ageBand != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _gender,
                isDense: true,
                hint: Text(l10n.segmentsPanelAllGenders),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l10n.segmentsPanelAllGenders),
                  ),
                  DropdownMenuItem(
                    value: 'male',
                    child: Text(l10n.segmentsPanelGenderMen),
                  ),
                  DropdownMenuItem(
                    value: 'female',
                    child: Text(l10n.segmentsPanelGenderWomen),
                  ),
                ],
                onChanged: (v) {
                  setState(() => _gender = v);
                  _refreshBoard();
                },
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _ageBand,
                isDense: true,
                hint: Text(l10n.segmentsPanelAllAges),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l10n.segmentsPanelAllAges),
                  ),
                  for (final b in kSegmentAgeBands)
                    DropdownMenuItem(value: b, child: Text(b)),
                ],
                onChanged: (v) {
                  setState(() => _ageBand = v);
                  _refreshBoard();
                },
              ),
            ),
            if (filtered)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _gender = null;
                    _ageBand = null;
                  });
                  _refreshBoard();
                },
                icon: const Icon(Icons.close, size: 16),
                label: Text(l10n.segmentsPanelResetFilters),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_boardFailed)
          ErrorState(
            message: l10n.segmentsPanelLeaderboardError,
            onRetry: _refreshBoard,
          )
        else if (_board == null)
          Text(
            l10n.segmentsPanelLeaderboardLoading,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else if (_board!.isEmpty)
          Text(
            filtered
                ? l10n.segmentsPanelLeaderboardEmptyFiltered
                : l10n.segmentsPanelLeaderboardEmpty,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          ..._boardRows(context, l10n, api.userId),
      ],
    );
  }

  List<Widget> _boardRows(
    BuildContext context,
    AppLocalizations l10n,
    String? viewerId,
  ) {
    final board = _board!;
    final label = crownLabel(_gender, _ageBand);
    final leader = board.first;
    final viewerHoldsCrown = leader.rank == 1 &&
        viewerId != null &&
        leader.effort.userId == viewerId;
    return [
      if (viewerHoldsCrown)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(Icons.emoji_events,
                  size: 18, color: AppSemanticColors.of(context).crown),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.segmentsPanelCrownBanner(label),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      for (final entry in board)
        _BoardRow(entry: entry, viewerId: viewerId, crownLabel: label),
    ];
  }
}

class _BoardRow extends StatelessWidget {
  final GlobalSegmentLeaderboardEntry entry;
  final String? viewerId;
  final String crownLabel;

  const _BoardRow({
    required this.entry,
    required this.viewerId,
    required this.crownLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isViewer = viewerId != null && entry.effort.userId == viewerId;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isViewer
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: entry.rank == 1
                ? Tooltip(
                    message: crownLabel,
                    child: Icon(
                      Icons.emoji_events,
                      size: 20,
                      color: AppSemanticColors.of(context).crown,
                    ),
                  )
                : Text(
                    '#${entry.rank}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          IdentityAvatar(
            seed: entry.athlete.id,
            name: entry.athlete.displayName,
            size: 24,
            imageUrl: entry.athlete.avatarUrl,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.athlete.displayName ?? l10n.segmentsPanelRunnerFallback,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: isViewer ? FontWeight.w700 : null),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // The viewer tint is barely distinguishable from a neighbouring row,
          // so the label and the weight are the cue — as on the route-segment
          // leaderboard.
          if (isViewer) ...[
            const SizedBox(width: 6),
            Text(
              l10n.navYou,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            formatEffortTime(entry.effort.timeSeconds),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
