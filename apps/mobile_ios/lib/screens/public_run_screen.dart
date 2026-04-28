import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../run_stats.dart';
import '../widgets/error_state.dart';
import '../widgets/live_run_map.dart';
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
      final row = await widget.api.fetchRunById(widget.runId);
      if (row == null) {
        if (!mounted) return;
        setState(() {
          _row = null;
          _loading = false;
        });
        return;
      }
      final results = await Future.wait<dynamic>([
        row.trackUrl == null || row.trackUrl!.isEmpty
            ? Future.value(const <Waypoint>[])
            : widget.api.fetchTrackByPath(row.trackUrl!),
        widget.api.fetchPublicProfile(row.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _row = row;
        _track = results[0] as List<Waypoint>;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Run')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorState(
                  message: 'Could not load this run.',
                  onRetry: _load,
                )
              : _row == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'This run is private or no longer available.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : _buildBody(theme, _row!),
    );
  }

  Widget _buildBody(ThemeData theme, RunRow row) {
    final distanceKm = row.distanceM / 1000;
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
                  _author!.displayName ?? 'Runner',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  _fmtDateTime(row.startedAt),
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
                label: 'Distance',
                value: distanceKm.toStringAsFixed(2),
                unit: 'km',
              ),
              _StatBlock(
                label: 'Time',
                value: _fmtDuration(Duration(seconds: row.durationS)),
              ),
              _StatBlock(
                label: 'Pace',
                value: pace > 0 ? UnitFormat.pace(pace, DistanceUnit.km) : '—',
                unit: pace > 0 ? '/km' : null,
              ),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text('Segments', style: theme.textTheme.titleMedium),
        ),
        RunSegmentEfforts(
          api: widget.api,
          runId: row.id,
          runOwnerId: row.userId,
          routeId: row.routeId,
          track: _track,
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

  static String _fmtDateTime(DateTime d) {
    final local = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
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
