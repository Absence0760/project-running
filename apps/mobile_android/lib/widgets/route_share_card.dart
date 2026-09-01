import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../map_tile_readiness.dart';
import '../preferences.dart';
import '../share_sheet.dart';
import 'capture_png.dart';
import 'live_run_map.dart'
    show basemapTileLayer, basemapVoidColour, tileUrlFor;
import 'map_attribution.dart';
import '../widgets/top_banner.dart';

/// Whether the share card for [route] draws a basemap at all, and therefore
/// whether a capture has any tiles to wait for. A route that short renders
/// the route glyph instead.
bool routeShareCardHasMap(cm.Route route) => route.waypoints.length >= 2;

/// Open a portrait "share card" modal for [route] — a branded preview
/// of the route map plus headline stats — and let the user share the
/// rendered PNG via the system share sheet.
///
/// Mirrors `run_share_card.dart` intentionally; image capture is
/// `RepaintBoundary.toImage` → `share_plus`. This is the route
/// equivalent the roadmap "Community route library → Share to social"
/// item asks for; the existing Share-as-GPX / Share-as-KML popup
/// menu items stay where they are for runners who want the raw track.
Future<void> showRouteShareSheet(
  BuildContext context, {
  required cm.Route route,
  required Preferences preferences,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (ctx) => _ShareRouteSheet(
      route: route,
      preferences: preferences,
    ),
  );
}

class _ShareRouteSheet extends StatefulWidget {
  final cm.Route route;
  final Preferences preferences;

  const _ShareRouteSheet({
    required this.route,
    required this.preferences,
  });

  @override
  State<_ShareRouteSheet> createState() => _ShareRouteSheetState();
}

class _ShareRouteSheetState extends State<_ShareRouteSheet> {
  final GlobalKey _cardKey = GlobalKey();
  final MapTileReadiness _tiles = MapTileReadiness();
  bool _capturing = false;

  String get _caption {
    final unit = widget.preferences.unit;
    final dist = UnitFormat.distance(widget.route.distanceMetres, unit);
    return '${widget.route.name} — $dist';
  }

  Future<void> _shareImage() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      // Wait for the tiles the card is actually showing, not for a guessed
      // interval: a fixed sleep rasterised a part-black map whenever a cold
      // fetch outran it, and made every cached share wait for nothing.
      if (routeShareCardHasMap(widget.route)) {
        await _tiles.settled();
      }
      await WidgetsBinding.instance.endOfFrame;

      final bytes = await capturePngBytes(_cardKey);

      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/route-${widget.route.id}.png');
      await file.writeAsBytes(bytes);

      await shareFilesFrom(
        context,
        files: [XFile(file.path, mimeType: 'image/png')],
        text: _caption,
      );
    } catch (e) {
      debugPrint('Failed to capture route share card: $e');
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).shareCardImageError);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
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
              Text(l10n.shareCardRouteTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: _ShareCardContent(
                      route: widget.route,
                      preferences: widget.preferences,
                      tileReadiness: _tiles,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _capturing ? null : _shareImage,
                  icon: _capturing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share_outlined),
                  label: Text(_capturing
                      ? l10n.shareCardRouteCapturing
                      : l10n.shareCardRouteShareImage),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareCardContent extends StatelessWidget {
  final cm.Route route;
  final Preferences preferences;

  /// Set by the sheet that rasterises this card, so it can wait for the
  /// basemap instead of sleeping.
  final MapTileReadiness? tileReadiness;

  const _ShareCardContent({
    required this.route,
    required this.preferences,
    this.tileReadiness,
  });

  /// Honours `TILE_URL_TEMPLATE` for local Protomaps dev → falls
  /// back to MapTiler. Same single-knob override the rest of the
  /// mobile map surfaces use (see `live_run_map.dart`).
  /// Pinned to the dark basemap rather than following the device theme
  /// or the user's map-style preference: the card rasterises a fixed
  /// dark PNG whose white type and overlays are drawn for a dark map.
  String get _tileUrl => tileUrlFor('dark', Brightness.dark);

  @override
  Widget build(BuildContext context) {
    final waypoints =
        route.waypoints.map((w) => LatLng(w.lat, w.lng)).toList();

    return Container(
      color: const Color(0xFF0B0A1F),
      child: Column(
        children: [
          Expanded(flex: 3, child: _buildMap(waypoints)),
          Expanded(flex: 2, child: _buildStats(context)),
        ],
      ),
    );
  }

  Widget _buildMap(List<LatLng> waypoints) {
    if (waypoints.length < 2) {
      return const Center(
        child: Icon(Icons.route, size: 96, color: Color(0xFF4F46E5)),
      );
    }

    return FlutterMap(
      options: MapOptions(
        backgroundColor: basemapVoidColour(darkBasemap: true),
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(waypoints),
          padding: const EdgeInsets.all(40),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        basemapTileLayer(
          urlTemplate: _tileUrl,
          tileBuilder: tileReadiness?.observe,
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: waypoints,
              strokeWidth: 14,
              color: const Color(0xFF818CF8).withValues(alpha: 0.18),
            ),
          ],
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: waypoints,
              strokeWidth: 6,
              color: const Color(0xFF818CF8),
              borderStrokeWidth: 2,
              borderColor: const Color(0xFF1E1B4B),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: waypoints.first,
              width: 18,
              height: 18,
              child: const _Pin(color: Color(0xFF22C55E)),
            ),
            Marker(
              point: waypoints.last,
              width: 18,
              height: 18,
              child: const _Pin(color: Color(0xFFF43F5E)),
            ),
          ],
        ),
        const MapAttribution(darkBasemap: true),
      ],
    );
  }

  Widget _buildStats(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = preferences.unit;
    final dist = UnitFormat.distance(route.distanceMetres, unit);
    final ele = route.elevationGainMetres > 0
        ? '${route.elevationGainMetres.round()} m'
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              if (route.surface != null) ...[
                const SizedBox(height: 6),
                Text(
                  route.surface!.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFC7D2FE),
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat(label: l10n.shareCardRouteStatDistance, value: dist),
              if (ele != null)
                _Stat(label: l10n.shareCardRouteStatClimb, value: ele),
            ],
          ),
          const Text(
            'Run · Threkir',
            style: TextStyle(
              color: Color(0xFF818CF8),
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF818CF8),
            fontSize: 10,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  final Color color;
  const _Pin({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }
}
