import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import '../widgets/error_state.dart';
import '../widgets/live_run_map.dart';
import '../widgets/run_gear_chips.dart';
import '../widgets/run_photos.dart';
import '../widgets/run_segment_efforts.dart';
import '../widgets/run_social_section.dart';

/// Read-only public view of a single run. Mirrors the web
/// `/share/run/[id]` route — anyone with the link can view a public
/// run; private runs return null via RLS and we render a "not
/// available" empty state.
class PublicRunScreen extends StatefulWidget {
  final ApiClient api;
  final String runId;

  const PublicRunScreen({
    super.key,
    required this.api,
    required this.runId,
  });

  @override
  State<PublicRunScreen> createState() => _PublicRunScreenState();
}

class _PublicRunScreenState extends State<PublicRunScreen> {
  bool _loading = true;
  Object? _loadError;
  RunRow? _row;
  List<Waypoint> _track = const [];
  PublicProfile? _author;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final row = await widget.api.fetchPublicRunById(widget.runId);
      if (row == null) {
        if (!mounted) return;
        setState(() {
          _row = null;
          _loading = false;
        });
        return;
      }
      // Privacy-zone clipping for non-owner viewers (decisions §33).
      // Owners take the direct-Storage path (the per-user-folder
      // policy from 20260410_001 still gates them). Non-owner viewers
      // — including anon, where `api.userId == null` — go through the
      // `clip-public-track` Edge Function so the unclipped blob never
      // crosses the wire (migration 20260619_001 dropped the
      // public-runs Storage policy that previously made direct
      // download possible). The EF fails closed (returns []) on
      // outage; non-owners see an empty map rather than the
      // unclipped track.
      //
      // audit/storage (2026-05-25): track_url was dropped from the
      // public_runs view in migration 20260924_001. The owner path
      // derives the Storage shape the same way the
      // clip-public-track EF does — both pin to
      // `{user_id}/{run_id}.json.gz`, the format the CHECK on
      // runs.track_url enforces (20260621_001). Runs without a
      // track (manual entry) fail the Storage download and the
      // try/catch already in fetchTrackByPath / fetchClippedTrackForRun
      // returns an empty list.
      final viewerId = widget.api.userId;
      final isOwner = viewerId != null && viewerId == row.userId;
      // Wrap with onError so a missing Storage object (manual-entry
      // run, retired blob) lands as an empty track instead of
      // propagating into _loadError, which would mask the rest of
      // the page.
      final Future<List<Waypoint>> trackFuture = (isOwner
              ? widget.api.fetchTrackByPath('${row.userId}/${row.id}.json.gz')
              : widget.api.fetchClippedTrackForRun(row.id))
          .catchError((_) => const <Waypoint>[]);
      final results = await Future.wait<dynamic>([
        trackFuture,
        widget.api.fetchPublicProfile(row.userId),
      ]);
      final track = results[0] as List<Waypoint>;
      if (!mounted) return;
      setState(() {
        _row = row;
        _track = track;
        final profileRow = results[1] as UserProfileRow?;
        _author = profileRow == null
            ? null
            : PublicProfile(
                id: profileRow.id,
                displayName: profileRow.displayName,
                avatarUrl: profileRow.avatarUrl,
              );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.publicRunTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorState(
                  message: l10n.publicRunLoadError,
                  onRetry: _load,
                )
              : _row == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.publicRunUnavailable,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : _buildBody(theme, l10n, _row!),
    );
  }

  Widget _buildBody(ThemeData theme, AppLocalizations l10n, RunRow row) {
    final unit = activeDistanceUnit;
    final pace = (row.distanceM > 0 && row.durationS > 0)
        ? row.durationS / (row.distanceM / 1000)
        : 0.0;
    return ListView(
      children: [
        SizedBox(
          height: 300,
          child: LiveRunMap(
            track: _track,
            plannedRoute: const [],
            followRunner: false,
          ),
        ),
        if (_author != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text(
                  _author!.displayName ?? l10n.publicRunAuthorFallback,
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  formatDateTime(row.startedAt.toLocal(),
                      localeToTag(Localizations.localeOf(context))),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatBlock(
                label: l10n.publicRunStatDistance,
                value: UnitFormat.distanceValue(row.distanceM, unit),
                unit: UnitFormat.distanceLabel(unit),
              ),
              _StatBlock(
                label: l10n.publicRunStatTime,
                value: _fmtDuration(Duration(seconds: row.durationS)),
              ),
              _StatBlock(
                label: l10n.publicRunStatPace,
                value: pace > 0 ? UnitFormat.pace(pace, unit) : '—',
                unit: pace > 0 ? UnitFormat.paceLabel(unit) : null,
              ),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(l10n.publicRunSectionSegments,
              style: theme.textTheme.titleMedium),
        ),
        RunSegmentEfforts(
          api: widget.api,
          runId: row.id,
          runOwnerId: row.userId,
          routeId: row.routeId,
          track: _track,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RunGearChips(
            api: widget.api,
            runId: row.id,
            runOwnerId: row.userId,
          ),
        ),
        if (widget.api.userId != null)
          RunSocialSection(
            api: widget.api,
            runId: row.id,
            runOwnerId: row.userId,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RunPhotos(
            api: widget.api,
            runId: row.id,
            runOwnerId: row.userId,
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _StatBlock({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}
