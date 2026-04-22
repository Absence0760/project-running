import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../preferences.dart';
import '../run_stats.dart';
import '../tile_cache.dart';

/// Opens a modal sheet showing a portrait "share card" for [run] — a branded
/// preview of the route map plus headline stats — and lets the user share
/// either the rendered PNG or the raw GPX via the system share sheet.
Future<void> showRunShareSheet(
  BuildContext context, {
  required Run run,
  required Preferences preferences,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ShareRunSheet(
      run: run,
      preferences: preferences,
      title: title,
    ),
  );
}

class _ShareRunSheet extends StatefulWidget {
  final Run run;
  final Preferences preferences;
  final String title;

  const _ShareRunSheet({
    required this.run,
    required this.preferences,
    required this.title,
  });

  @override
  State<_ShareRunSheet> createState() => _ShareRunSheetState();
}

class _ShareRunSheetState extends State<_ShareRunSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _capturing = false;

  String get _caption {
    final unit = widget.preferences.unit;
    final dist = UnitFormat.distance(widget.run.distanceMetres, unit);
    return '${widget.title} — $dist in ${_formatDuration(widget.run.duration)}';
  }

  Future<void> _shareImage() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      // Give map tiles a beat to load in before grabbing the frame. Cached
      // tiles (the common case — user just viewed the detail screen) resolve
      // in the first endOfFrame; the extra delay covers a cold fetch.
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 700));
      await WidgetsBinding.instance.endOfFrame;

      final boundary = _cardKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/run-${widget.run.id}.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: _caption,
      );
    } catch (e) {
      debugPrint('Failed to capture run share card: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create share image')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _shareFile(String format) async {
    final tmp = await getTemporaryDirectory();
    final run = widget.run;
    final title = widget.title;
    File file;
    switch (format) {
      case 'tcx':
        file = File('${tmp.path}/run-${run.id}.tcx');
        await file.writeAsString(_runToTcx(run, title));
      case 'fit':
        file = File('${tmp.path}/run-${run.id}.fit');
        await file.writeAsBytes(_runToFitBytes(run));
      default:
        file = File('${tmp.path}/run-${run.id}.gpx');
        await file.writeAsString(_runToGpx(run, title));
    }
    await Share.shareXFiles([XFile(file.path)], text: _caption);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + mq.viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Share run', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: RunShareCard(
                      run: widget.run,
                      preferences: widget.preferences,
                      title: widget.title,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PopupMenuButton<String>(
                      onSelected: _capturing ? null : _shareFile,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'gpx', child: Text('GPX')),
                        PopupMenuItem(value: 'tcx', child: Text('TCX')),
                        PopupMenuItem(value: 'fit', child: Text('FIT')),
                      ],
                      child: OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.route_outlined),
                        label: const Text('Export'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _capturing ? null : _shareImage,
                      icon: _capturing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.image_outlined),
                      label: const Text('Image'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Portrait run share card — route map on top, headline stats on the bottom
/// over a dark background. Wrap in a [RepaintBoundary] and grab it via
/// [RenderRepaintBoundary.toImage] to produce a shareable PNG. Intended to
/// be rendered at a 4:5 aspect ratio.
class RunShareCard extends StatelessWidget {
  final Run run;
  final Preferences preferences;
  final String title;

  const RunShareCard({
    super.key,
    required this.run,
    required this.preferences,
    required this.title,
  });

  String get _tileUrl {
    final key = dotenv.env['MAPTILER_KEY'] ?? '';
    return 'https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}@2x.png?key=$key';
  }

  @override
  Widget build(BuildContext context) {
    final unit = preferences.unit;
    final activity =
        ActivityType.fromName(run.metadata?['activity_type'] as String?);
    final moving = _movingTime();
    final pace = _movingPaceSecPerKm(moving);
    final track = run.track.map((w) => LatLng(w.lat, w.lng)).toList();

    return Container(
      color: const Color(0xFF0B0A1F),
      child: Column(
        children: [
          Expanded(flex: 3, child: _buildMap(track)),
          Expanded(
            flex: 2,
            child: _buildStats(activity, unit, moving, pace),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(List<LatLng> track) {
    if (track.length < 2) {
      return const Center(
        child: Icon(Icons.directions_run,
            size: 96, color: Color(0xFF4F46E5)),
      );
    }

    // Compute spans so we can fall back to centre+zoom when every point is
    // identical (e.g. a treadmill run that still logged one stationary fix).
    double minLat = track.first.latitude, maxLat = track.first.latitude;
    double minLng = track.first.longitude, maxLng = track.first.longitude;
    for (final p in track) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final hasSpan =
        (maxLat - minLat) > 1e-6 || (maxLng - minLng) > 1e-6;

    final options = hasSpan
        ? MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(track),
              padding: const EdgeInsets.all(40),
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          )
        : MapOptions(
            initialCenter: track.first,
            initialZoom: 16,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          );

    return FlutterMap(
      options: options,
      children: [
        TileLayer(
          urlTemplate: _tileUrl,
          userAgentPackageName: 'com.example.mobile_android',
          maxZoom: 19,
          tileProvider: CachedTileProvider(
            store: TileCache.store,
            maxStale: const Duration(days: 30),
            dio: TileCache.dio,
          ),
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: track,
              strokeWidth: 14,
              color: const Color(0xFF818CF8).withValues(alpha: 0.18),
            ),
          ],
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: track,
              strokeWidth: 6,
              gradientColors: const [
                Color(0xFF4F46E5),
                Color(0xFF818CF8),
                Color(0xFFC7D2FE),
              ],
              borderStrokeWidth: 2,
              borderColor: const Color(0xFF1E1B4B),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: track.first,
              width: 18,
              height: 18,
              child: _endpointDot(const Color(0xFF34D399)),
            ),
            Marker(
              point: track.last,
              width: 18,
              height: 18,
              child: _endpointDot(const Color(0xFFF87171)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _endpointDot(Color color) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }

  Widget _buildStats(
    ActivityType activity,
    DistanceUnit unit,
    Duration movingTime,
    double? pace,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${activity.label} · ${_formatDate(run.startedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _stat(
                label: 'Distance',
                value: UnitFormat.distanceValue(run.distanceMetres, unit),
                unitLabel: UnitFormat.distanceLabel(unit),
              ),
              _stat(
                label: 'Time',
                value: _formatDuration(movingTime),
              ),
              _stat(
                label: activity.usesSpeed ? 'Speed' : 'Pace',
                value: activity.usesSpeed
                    ? UnitFormat.speed(pace, unit)
                    : UnitFormat.pace(pace, unit),
                unitLabel: activity.usesSpeed
                    ? UnitFormat.speedLabel(unit)
                    : UnitFormat.paceLabel(unit),
              ),
            ],
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'RUN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  height: 1.0,
                ),
              ),
              Text(
                '© MapTiler · OpenStreetMap',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 8,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required String label,
    required String value,
    String? unitLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 9,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            if (unitLabel != null) ...[
              const SizedBox(width: 3),
              Text(
                unitLabel,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Duration _movingTime() {
    if (run.track.length < 2) return run.duration;
    final computed = movingTimeOf(run.track);
    if (computed.inSeconds == 0) return run.duration;
    return computed;
  }

  double? _movingPaceSecPerKm(Duration movingTime) {
    if (run.distanceMetres < 10) return null;
    final seconds = movingTime.inSeconds;
    if (seconds < 1) return null;
    return seconds / (run.distanceMetres / 1000);
  }
}

String _runToGpx(Run r, String title) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln(
      '<gpx version="1.1" creator="Run" xmlns="http://www.topografix.com/GPX/1/1">');
  buf.writeln('  <metadata>');
  buf.writeln('    <name>${esc(title)}</name>');
  buf.writeln('    <time>${r.startedAt.toUtc().toIso8601String()}</time>');
  buf.writeln('  </metadata>');
  buf.writeln('  <trk>');
  buf.writeln('    <name>${esc(title)}</name>');
  buf.writeln('    <trkseg>');
  for (final w in r.track) {
    buf.write('      <trkpt lat="${w.lat}" lon="${w.lng}">');
    if (w.elevationMetres != null) {
      buf.write('<ele>${w.elevationMetres}</ele>');
    }
    if (w.timestamp != null) {
      buf.write('<time>${w.timestamp!.toUtc().toIso8601String()}</time>');
    }
    buf.writeln('</trkpt>');
  }
  buf.writeln('    </trkseg>');
  buf.writeln('  </trk>');
  buf.writeln('</gpx>');
  return buf.toString();
}

String _runToTcx(Run r, String title) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln(
      '<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">');
  buf.writeln('  <Activities>');
  buf.writeln('    <Activity Sport="Running">');
  buf.writeln(
      '      <Id>${r.startedAt.toUtc().toIso8601String()}</Id>');
  buf.writeln('      <Notes>${esc(title)}</Notes>');
  buf.writeln('      <Lap StartTime="${r.startedAt.toUtc().toIso8601String()}">');
  buf.writeln(
      '        <TotalTimeSeconds>${r.duration.inSeconds}</TotalTimeSeconds>');
  buf.writeln(
      '        <DistanceMeters>${r.distanceMetres.toStringAsFixed(1)}</DistanceMeters>');
  buf.writeln('        <Track>');
  for (final w in r.track) {
    buf.writeln('          <Trackpoint>');
    if (w.timestamp != null) {
      buf.writeln(
          '            <Time>${w.timestamp!.toUtc().toIso8601String()}</Time>');
    }
    buf.writeln('            <Position>');
    buf.writeln('              <LatitudeDegrees>${w.lat}</LatitudeDegrees>');
    buf.writeln('              <LongitudeDegrees>${w.lng}</LongitudeDegrees>');
    buf.writeln('            </Position>');
    if (w.elevationMetres != null) {
      buf.writeln(
          '            <AltitudeMeters>${w.elevationMetres}</AltitudeMeters>');
    }
    buf.writeln('          </Trackpoint>');
  }
  buf.writeln('        </Track>');
  buf.writeln('      </Lap>');
  buf.writeln('    </Activity>');
  buf.writeln('  </Activities>');
  buf.writeln('</TrainingCenterDatabase>');
  return buf.toString();
}

List<int> _runToFitBytes(Run r) {
  // FIT epoch: 1989-12-31 00:00:00 UTC
  final fitEpoch = DateTime.utc(1989, 12, 31);
  int fitTimestamp(DateTime dt) => dt.difference(fitEpoch).inSeconds;
  int semicircles(double degrees) => (degrees * (1 << 31) / 180).round();

  final out = <int>[];

  void writeU8(int v) => out.add(v & 0xFF);
  void writeU16LE(int v) {
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
  }
  void writeU32LE(int v) {
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
    out.add((v >> 16) & 0xFF);
    out.add((v >> 24) & 0xFF);
  }
  void writeSint32LE(int v) => writeU32LE(v < 0 ? v + 0x100000000 : v);

  // Definition message helper. Returns the local message type used.
  void writeDefinition({
    required int localType,
    required int globalMesgNum,
    required List<List<int>> fields,
  }) {
    writeU8(0x40 | (localType & 0x0F)); // definition header
    writeU8(0); // reserved
    writeU8(0); // little-endian
    writeU16LE(globalMesgNum);
    writeU8(fields.length);
    for (final f in fields) {
      writeU8(f[0]); // field num
      writeU8(f[1]); // size
      writeU8(f[2]); // base type
    }
  }

  // Data message helper.
  void writeDataHeader(int localType) {
    writeU8(localType & 0x0F);
  }

  // -- File header (14 bytes, written at the end with correct data size) --
  for (var i = 0; i < 14; i++) out.add(0); // placeholder

  // -- File ID message (mesg 0) --
  writeDefinition(localType: 0, globalMesgNum: 0, fields: [
    [0, 1, 0],   // type: enum (4=activity)
    [1, 2, 132], // manufacturer: uint16
    [3, 4, 134], // serial: uint32z
    [4, 4, 134], // time_created: uint32
  ]);
  writeDataHeader(0);
  writeU8(4); // type = activity
  writeU16LE(1); // manufacturer = 1 (Garmin, generic)
  writeU32LE(12345); // serial
  writeU32LE(fitTimestamp(r.startedAt));

  // -- Record messages (mesg 20) --
  writeDefinition(localType: 1, globalMesgNum: 20, fields: [
    [253, 4, 134], // timestamp: uint32
    [0, 4, 133],   // position_lat: sint32
    [1, 4, 133],   // position_lng: sint32
    [2, 2, 132],   // altitude: uint16 (scale 5, offset 500)
  ]);
  for (final w in r.track) {
    writeDataHeader(1);
    writeU32LE(fitTimestamp(w.timestamp ?? r.startedAt));
    writeSint32LE(semicircles(w.lat));
    writeSint32LE(semicircles(w.lng));
    final alt = w.elevationMetres ?? 0;
    writeU16LE(((alt + 500) * 5).round().clamp(0, 0xFFFF));
  }

  // -- Patch file header --
  final dataSize = out.length - 14;
  out[0] = 14; // header size
  out[1] = 20; // protocol version (2.0)
  out[2] = 0x08; // profile version low
  out[3] = 0x08; // profile version high
  out[4] = dataSize & 0xFF;
  out[5] = (dataSize >> 8) & 0xFF;
  out[6] = (dataSize >> 16) & 0xFF;
  out[7] = (dataSize >> 24) & 0xFF;
  // ".FIT" signature
  out[8] = 0x2E; // '.'
  out[9] = 0x46; // 'F'
  out[10] = 0x49; // 'I'
  out[11] = 0x54; // 'T'
  // Header CRC (2 bytes) — set to 0 (optional per spec)
  out[12] = 0;
  out[13] = 0;

  // -- Data CRC --
  var crc = 0;
  for (var i = 14; i < out.length; i++) {
    crc = _fitCrc(crc, out[i]);
  }
  out.add(crc & 0xFF);
  out.add((crc >> 8) & 0xFF);

  return out;
}

int _fitCrc(int crc, int byte) {
  const table = [
    0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
    0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
  ];
  var tmp = table[crc & 0xF] ^ table[byte & 0xF];
  crc = (crc >> 4) & 0x0FFF;
  crc = crc ^ tmp ^ table[(byte >> 4) & 0xF];
  return crc;
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _formatDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}
