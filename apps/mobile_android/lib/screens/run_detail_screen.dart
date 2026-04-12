import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../route_simplify.dart';
import '../run_stats.dart';
import '../widgets/live_run_map.dart';
import '../widgets/run_share_card.dart';

/// Detail view for a completed run, showing the route map, splits, and stats.
class RunDetailScreen extends StatefulWidget {
  final Run run;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final ApiClient? apiClient;

  const RunDetailScreen({
    super.key,
    required this.run,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    this.apiClient,
  });

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  late Run run = widget.run;
  bool _loadingTrack = false;
  Route? _linkedRoute;

  @override
  void initState() {
    super.initState();
    _loadLinkedRoute();
    _maybeFetchTrack();
  }

  /// If the run is attached to a saved route (manual-entry runs usually
  /// are), resolve it from the local route store so we can show its planned
  /// path on the map when the run itself has no GPS track.
  void _loadLinkedRoute() {
    final id = run.routeId;
    if (id == null) return;
    try {
      _linkedRoute =
          widget.routeStore.routes.where((r) => r.id == id).firstOrNull;
    } catch (_) {
      _linkedRoute = null;
    }
  }

  /// If this run came from the cloud (track empty but track_url present),
  /// download the GPS waypoints from Storage and update the local store so
  /// next time we don't need to refetch.
  Future<void> _maybeFetchTrack() async {
    if (run.track.isNotEmpty) return;
    final trackUrl = run.metadata?['track_url'] as String?;
    if (trackUrl == null) return;
    final api = widget.apiClient;
    if (api == null) return;

    setState(() => _loadingTrack = true);
    try {
      final track = await api.fetchTrack(run);
      if (track.isEmpty) return;
      final updated = Run(
        id: run.id,
        startedAt: run.startedAt,
        duration: run.duration,
        distanceMetres: run.distanceMetres,
        track: track,
        routeId: run.routeId,
        source: run.source,
        externalId: run.externalId,
        metadata: run.metadata,
        createdAt: run.createdAt,
      );
      // Persist the fetched track to the local store so subsequent opens are
      // instant. saveFromRemote merges and marks synced.
      await widget.runStore.saveFromRemote(updated);
      if (mounted) setState(() => run = updated);
    } catch (e) {
      debugPrint('Failed to fetch track for ${run.id}: $e');
    } finally {
      if (mounted) setState(() => _loadingTrack = false);
    }
  }

  String get _title => (run.metadata?['title'] as String?) ?? _formatDate(run.startedAt);
  String get _notes => (run.metadata?['notes'] as String?) ?? '';

  static const _metresPerMile = 1609.344;

  Future<void> _editDetails() async {
    final unit = widget.preferences.unit;
    final titleCtl = TextEditingController(text: _title);
    final notesCtl = TextEditingController(text: _notes);

    // Distance + duration are editable only when there's no GPS track to
    // contradict the typed values. Recorded runs derive these from the
    // waypoints and editing them here would desync the map, splits, and
    // the fastest-5k PB from the headline numbers.
    final canEditStats = run.track.isEmpty;
    final distanceCtl = TextEditingController(
      text: canEditStats ? _distanceToInput(run.distanceMetres, unit) : '',
    );
    final hoursCtl = TextEditingController(
      text: canEditStats ? run.duration.inHours.toString() : '',
    );
    final minutesCtl = TextEditingController(
      text: canEditStats ? (run.duration.inMinutes % 60).toString() : '',
    );
    final secondsCtl = TextEditingController(
      text: canEditStats ? (run.duration.inSeconds % 60).toString() : '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit run'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleCtl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtl,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 4,
              ),
              if (canEditStats) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: distanceCtl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Distance',
                    suffixText: UnitFormat.distanceLabel(unit),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Duration'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: _durationSubField(hoursCtl, 'h')),
                    const SizedBox(width: 8),
                    Expanded(child: _durationSubField(minutesCtl, 'm')),
                    const SizedBox(width: 8),
                    Expanded(child: _durationSubField(secondsCtl, 's')),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    double newDistance = run.distanceMetres;
    Duration newDuration = run.duration;
    if (canEditStats) {
      final parsedDistance = _parseDistanceMetres(distanceCtl.text, unit);
      final parsedDuration = _parseDuration(
        hoursCtl.text,
        minutesCtl.text,
        secondsCtl.text,
      );
      if (parsedDistance == null || parsedDuration == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a valid distance and duration'),
          ),
        );
        return;
      }
      newDistance = parsedDistance;
      newDuration = parsedDuration;
    }

    final metadata = Map<String, dynamic>.from(run.metadata ?? {});
    metadata['title'] = titleCtl.text.trim();
    metadata['notes'] = notesCtl.text.trim();

    final updated = Run(
      id: run.id,
      startedAt: run.startedAt,
      duration: newDuration,
      distanceMetres: newDistance,
      track: run.track,
      routeId: run.routeId,
      source: run.source,
      externalId: run.externalId,
      metadata: metadata,
      createdAt: run.createdAt,
    );
    await widget.runStore.update(updated);
    setState(() => run = updated);
  }

  Widget _durationSubField(TextEditingController ctl, String suffix) {
    return TextField(
      controller: ctl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        isDense: true,
        suffixText: suffix,
      ),
    );
  }

  static String _distanceToInput(double metres, DistanceUnit unit) {
    if (unit == DistanceUnit.mi) {
      return (metres / _metresPerMile).toStringAsFixed(2);
    }
    return (metres / 1000).toStringAsFixed(2);
  }

  static double? _parseDistanceMetres(String raw, DistanceUnit unit) {
    final v = double.tryParse(raw.trim());
    if (v == null || v <= 0) return null;
    return unit == DistanceUnit.mi ? v * _metresPerMile : v * 1000;
  }

  static Duration? _parseDuration(String h, String m, String s) {
    final hi = int.tryParse(h.trim().isEmpty ? '0' : h.trim());
    final mi = int.tryParse(m.trim().isEmpty ? '0' : m.trim());
    final si = int.tryParse(s.trim().isEmpty ? '0' : s.trim());
    if (hi == null || mi == null || si == null) return null;
    if (hi < 0 || mi < 0 || si < 0) return null;
    final total = Duration(hours: hi, minutes: mi, seconds: si);
    if (total.inSeconds <= 0) return null;
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit run',
            onPressed: _editDetails,
          ),
          IconButton(
            icon: const Icon(Icons.add_road_outlined),
            tooltip: 'Save as route',
            onPressed: _saveAsRoute,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share run',
            onPressed: _shareRun,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete run',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
        children: [
          // Map: show the recorded track if we have one; otherwise fall back
          // to the linked route's planned path. Manual-entry runs with no
          // route attached skip the map entirely.
          if (run.track.isNotEmpty || _linkedRoute != null)
            SizedBox(
              height: 280,
              child: Stack(
                children: [
                  LiveRunMap(
                    track: run.track,
                    plannedRoute:
                        run.track.isEmpty ? _linkedRoute?.waypoints : null,
                    followRunner: false,
                  ),
                  if (_loadingTrack)
                    const Positioned(
                      top: 12,
                      right: 12,
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Loading GPS data...',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Activity type + notes
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Icon(_activityType.icon, size: 18, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text(
                  _activityType.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          if (_notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(_notes, style: theme.textTheme.bodyMedium),
            ),

          // Primary stats — each cell is Expanded so a long value like
          // "1:15:30" can't push the row past the screen edge. For runs
          // with no GPS track (manual entries, summary imports) the
          // "Moving" column is dropped — it's identical to "Time" and
          // four cells are too tight on a phone.
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: _StatBig(
                    label: 'Distance',
                    value: UnitFormat.distanceValue(run.distanceMetres, unit),
                    unit: UnitFormat.distanceLabel(unit),
                  ),
                ),
                Expanded(
                  child: _StatBig(
                    label: 'Time',
                    value: _formatDuration(run.duration),
                  ),
                ),
                if (_showMovingTime)
                  Expanded(
                    child: _StatBig(
                      label: 'Moving',
                      value: _formatDuration(_movingTime),
                    ),
                  ),
                Expanded(
                  child: _StatBig(
                    label: _activityType.usesSpeed ? 'Avg Speed' : 'Pace',
                    value: _activityType.usesSpeed
                        ? UnitFormat.speed(_movingPaceSecPerKm, unit)
                        : UnitFormat.pace(_movingPaceSecPerKm, unit),
                    unit: _activityType.usesSpeed
                        ? UnitFormat.speedLabel(unit)
                        : UnitFormat.paceLabel(unit),
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // Elevation chart
          if (_hasElevation) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Elevation', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 120,
                child: _ElevationChart(track: run.track, theme: theme),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
          ],

          // Laps
          if (_laps.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Laps', style: theme.textTheme.titleMedium),
            ),
            ..._buildLaps(theme, unit),
            const Divider(),
          ],

          // Splits — only when there's a track to compute them from.
          if (run.track.length >= 2) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Splits', style: theme.textTheme.titleMedium),
            ),
            ..._buildSplits(theme, unit),
          ],

          const SizedBox(height: 32),
        ],
        ),
      ),
    );
  }

  ActivityType get _activityType =>
      ActivityType.fromName(run.metadata?['activity_type'] as String?);

  bool get _hasElevation =>
      run.track.any((w) => w.elevationMetres != null);

  List<Map<String, dynamic>> get _laps {
    final laps = run.metadata?['laps'];
    if (laps is List) return List<Map<String, dynamic>>.from(laps);
    return const [];
  }

  List<Widget> _buildLaps(ThemeData theme, DistanceUnit unit) {
    return _laps.map((lap) {
      final number = lap['number'] as int;
      final dist = (lap['cumulative_distance_m'] as num).toDouble();
      final dur = Duration(seconds: (lap['cumulative_duration_s'] as num).toInt());
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.tertiaryContainer,
          child: Icon(Icons.flag, size: 18, color: theme.colorScheme.tertiary),
        ),
        title: Text('Lap $number'),
        subtitle: Text(UnitFormat.distance(dist, unit)),
        trailing: Text(_formatDuration(dur), style: theme.textTheme.titleMedium),
      );
    }).toList();
  }

  /// Moving time — elapsed with stops excluded, derived from the GPS track.
  /// Falls back to the full duration when the track is missing or too
  /// sparse to compute a meaningful value (e.g. imported runs without GPS).
  Duration get _movingTime {
    if (run.track.length < 2) return run.duration;
    final computed = movingTimeOf(run.track);
    if (computed.inSeconds == 0) return run.duration;
    return computed;
  }

  /// Whether to render the "Moving" stat cell. Hidden when the value is
  /// going to equal the total duration anyway — either because there's no
  /// GPS track to compute it from, or because the runner never stopped.
  /// Avoids a fourth stat cramping the row on a phone.
  bool get _showMovingTime {
    if (run.track.length < 2) return false;
    return _movingTime.inSeconds != run.duration.inSeconds;
  }

  double? get _movingPaceSecPerKm {
    if (run.distanceMetres < 10) return null;
    final seconds = _movingTime.inSeconds;
    if (seconds < 1) return null;
    return seconds / (run.distanceMetres / 1000);
  }

  List<Widget> _buildSplits(ThemeData theme, DistanceUnit unit) {
    if (run.track.length < 2) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('No GPS data for splits'),
        ),
      ];
    }

    const metresPerMile = 1609.344;
    final tickLength = unit == DistanceUnit.mi ? metresPerMile : 1000.0;
    final unitLabel = UnitFormat.distanceLabel(unit);

    final splits = <_Split>[];
    double cumulative = 0;
    int nextTick = 1;
    DateTime tickStart = run.track.first.timestamp ?? run.startedAt;

    for (int i = 1; i < run.track.length; i++) {
      final a = run.track[i - 1];
      final b = run.track[i];
      cumulative += _haversine(a.lat, a.lng, b.lat, b.lng);

      while (cumulative >= nextTick * tickLength) {
        final tickEnd = b.timestamp ?? run.startedAt;
        final splitTime = tickEnd.difference(tickStart);
        splits.add(_Split(nextTick, splitTime));
        tickStart = tickEnd;
        nextTick++;
      }
    }

    if (splits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Run too short for a full $unitLabel split'),
        ),
      ];
    }

    return splits.map((s) {
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text('${s.tick}'),
        ),
        title: Text('$unitLabel ${s.tick}'),
        trailing: Text(
          _formatDuration(s.duration),
          style: theme.textTheme.titleMedium,
        ),
      );
    }).toList();
  }

  /// Save this run's GPS track as a reusable route. Prompts for a name
  /// (default: the run's title) and simplifies the track via
  /// Ramer–Douglas–Peucker so the saved route isn't noisy.
  Future<void> _saveAsRoute() async {
    if (run.track.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This run has no GPS track to save as a route"),
        ),
      );
      return;
    }

    final nameCtl = TextEditingController(text: _title);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as route'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Save this GPS trace as a route you can follow again.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Route name',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final name = nameCtl.text.trim().isEmpty ? _title : nameCtl.text.trim();
    final simplified = simplifyTrack(run.track, epsilonMetres: 10);
    final gain = computeElevationGain(run.track);

    final route = Route(
      id: const Uuid().v4(),
      name: name,
      waypoints: simplified,
      distanceMetres: run.distanceMetres,
      elevationGainMetres: gain,
      createdAt: DateTime.now(),
    );
    await widget.routeStore.save(route);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved "$name" — ${simplified.length} waypoints '
          '(${run.track.length - simplified.length} smoothed out)',
        ),
      ),
    );
  }

  /// Open the share sheet — lets the user share an image of the run card or
  /// the raw GPX trace.
  Future<void> _shareRun() async {
    await showRunShareSheet(
      context,
      run: run,
      preferences: widget.preferences,
      title: _title,
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete run?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.runStore.delete(run.id);
      if (context.mounted) Navigator.pop(context);
    }
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}

class _Split {
  final int tick;
  final Duration duration;
  const _Split(this.tick, this.duration);
}

class _StatBig extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _StatBig({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Simple elevation profile rendered with a CustomPainter.
class _ElevationChart extends StatelessWidget {
  final List<Waypoint> track;
  final ThemeData theme;
  const _ElevationChart({required this.track, required this.theme});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ElevationPainter(
        track: track,
        lineColor: theme.colorScheme.primary,
        fillColor: theme.colorScheme.primary.withOpacity(0.15),
        gridColor: theme.dividerColor,
      ),
      size: Size.infinite,
    );
  }
}

class _ElevationPainter extends CustomPainter {
  final List<Waypoint> track;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  _ElevationPainter({
    required this.track,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final elevations = track
        .where((w) => w.elevationMetres != null)
        .map((w) => w.elevationMetres!)
        .toList();
    if (elevations.length < 2) return;

    final minEle = elevations.reduce(math.min);
    final maxEle = elevations.reduce(math.max);
    final range = (maxEle - minEle).abs() < 1 ? 1.0 : maxEle - minEle;

    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < elevations.length; i++) {
      final x = i / (elevations.length - 1) * size.width;
      final y = size.height - ((elevations[i] - minEle) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()..color = fillColor;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    // Min/max labels
    final textStyle = TextStyle(color: gridColor, fontSize: 10);
    final maxText = TextPainter(
      text: TextSpan(text: '${maxEle.round()}m', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    maxText.paint(canvas, const Offset(4, 0));

    final minText = TextPainter(
      text: TextSpan(text: '${minEle.round()}m', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    minText.paint(canvas, Offset(4, size.height - minText.height));
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter old) =>
      old.track != track || old.lineColor != lineColor;
}
