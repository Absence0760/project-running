import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../privacy.dart';
import '../settings_sync.dart';
import '../widgets/top_banner.dart';

/// Settings → Privacy zones: tap-to-add geofences clipped from the
/// start and end of any public-surface track. Mirrors the web
/// PrivacyZonePicker. Persisted on `user_settings.prefs.privacy_zones`.
class PrivacyZonesScreen extends StatefulWidget {
  final SettingsSyncService settingsSync;

  const PrivacyZonesScreen({super.key, required this.settingsSync});

  @override
  State<PrivacyZonesScreen> createState() => _PrivacyZonesScreenState();
}

class _PrivacyZonesScreenState extends State<PrivacyZonesScreen> {
  List<PrivacyZone> _zones = [];
  double _draftRadius = 150;
  final _mapController = MapController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  void _loadZones() {
    final raw = widget.settingsSync.service?.effective<List<dynamic>>(
      privacyZonesKey,
      fallback: const <dynamic>[],
    );
    if (raw != null) {
      _zones = raw
          .whereType<Map<String, dynamic>>()
          .map(PrivacyZone.fromJson)
          .toList();
    }
  }

  Future<void> _save() async {
    final s = widget.settingsSync.service;
    if (s == null) return;
    setState(() => _saving = true);
    try {
      await s.updateUniversal({
        privacyZonesKey: _zones.map((z) => z.toJson()).toList(),
      });
      if (!mounted) return;
      showTopBanner(context, 'Privacy zones saved.');
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addZoneAt(LatLng tap) {
    setState(() {
      _zones = [
        ..._zones,
        PrivacyZone(
          lat: tap.latitude,
          lng: tap.longitude,
          radiusM: _draftRadius,
        ),
      ];
    });
  }

  void _removeZone(int index) {
    setState(() => _zones = [..._zones]..removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = _zones.isNotEmpty
        ? LatLng(_zones.first.lat, _zones.first.lng)
        : const LatLng(51.5074, -0.1278); // London-ish fallback

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy zones'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Tap the map to add a zone. Tracks on public surfaces have '
              'their start and end clipped past the zone radius.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text('Radius', style: theme.textTheme.labelLarge),
                Expanded(
                  child: Slider(
                    min: 50,
                    max: 500,
                    divisions: 9,
                    value: _draftRadius,
                    label: '${_draftRadius.round()} m',
                    onChanged: (v) => setState(() => _draftRadius = v),
                  ),
                ),
                Text('${_draftRadius.round()} m'),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initial,
                initialZoom: 14,
                onTap: (_, latlng) => _addZoneAt(latlng),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.runonward.app',
                ),
                CircleLayer(
                  circles: [
                    for (final z in _zones)
                      CircleMarker(
                        point: LatLng(z.lat, z.lng),
                        radius: z.radiusM,
                        useRadiusInMeter: true,
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.25),
                        borderColor: theme.colorScheme.primary,
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < _zones.length; i++)
                      Marker(
                        point: LatLng(_zones[i].lat, _zones[i].lng),
                        width: 32,
                        height: 32,
                        child: GestureDetector(
                          onTap: () => _removeZone(i),
                          child: Icon(
                            Icons.cancel,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_zones.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_zones.length} zone${_zones.length == 1 ? '' : 's'} '
                      '— tap a marker to remove.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _zones = []),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear all'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
