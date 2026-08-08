import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../geocoding.dart';
import '../l10n/gen/app_localizations.dart';
import '../privacy.dart';
import '../settings_sync.dart';
import '../widgets/confirm_discard.dart';
import '../widgets/live_run_map.dart'
    show
        basemapTileLayer,
        basemapVoidColour,
        currentBasemapIsDark,
        currentTileUrl;
import '../widgets/map_attribution.dart';
import '../widgets/top_banner.dart';
import '../widgets/place_search_panel.dart';

/// Settings → Privacy zones: tap-to-add geofences clipped from the
/// start and end of any public-surface track. Mirrors the web
/// PrivacyZonePicker. Persisted on `user_settings.prefs.privacy_zones`.
///
/// On open the map centres on the user's location (so it doesn't sit on a
/// far-away default where self-hosted tiles may not cover) unless zones
/// already exist, and offers a place-search field + Locate-me FAB — the
/// same affordances the route builder and discovery map carry.
class PrivacyZonesScreen extends StatefulWidget {
  final SettingsSyncService settingsSync;

  /// Test seam — replays canned geocoding responses (see geocoding.dart).
  final GeocodingFetcher? geocodingFetcher;

  /// Test seam — stubs the platform `Geolocator` so the Locate FAB +
  /// open-centring can be exercised without the platform channel.
  final Future<Position> Function()? locateFn;

  const PrivacyZonesScreen({
    super.key,
    required this.settingsSync,
    this.geocodingFetcher,
    this.locateFn,
  });

  @override
  State<PrivacyZonesScreen> createState() => _PrivacyZonesScreenState();
}

class _PrivacyZonesScreenState extends State<PrivacyZonesScreen> {
  List<PrivacyZone> _zones = [];
  double _draftRadius = 150;
  final _mapController = MapController();
  bool _saving = false;
  // Zones are edited in memory and only persisted on Save; a swipe/back
  // before Save silently dropped drawn zones, so guard the exit.
  bool _dirty = false;

  final _searchCtl = TextEditingController();
  List<PlaceResult> _searchResults = const [];
  // Held apart from an empty result set so the dropdown can say the
  // search FAILED rather than claim the place does not exist.
  bool _searchUnavailable = false;
  bool _searchOpen = false;
  Timer? _searchDebounce;

  LatLng? _userLatLng;
  bool _mapReady = false;
  bool _centeredOnce = false;

  String get _maptilerKey {
    // Defensive read — `dotenv.env` throws NotInitializedError if the
    // screen is reached before the env loads (and in widget tests). The
    // empty key just routes searchPlaces through the Nominatim fallback.
    try {
      return dotenv.env['MAPTILER_KEY'] ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadZones();
    unawaited(_backgroundLocate());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
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
    final l10n = AppLocalizations.of(context);
    final s = widget.settingsSync.service;
    if (s == null) return;
    setState(() => _saving = true);
    try {
      await s.updateUniversal({
        privacyZonesKey: _zones.map((z) => z.toJson()).toList(),
      });
      if (!mounted) return;
      _dirty = false;
      showTopBanner(context, l10n.privacyZonesSaved);
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.privacyZonesSaveFailed(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addZoneAt(LatLng tap) {
    setState(() {
      _dirty = true;
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

  // A privacy zone hides tracks near a sensitive place (home/work) on public
  // shares, so removing one — or clearing all — confirms first.
  Future<void> _confirmRemoveZone(int index) async {
    final l10n = AppLocalizations.of(context);
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.privacyZonesRemoveTitle),
            content: Text(l10n.privacyZonesRemoveBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.prefsCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: Text(l10n.privacyZonesRemoveSemantics),
              ),
            ],
          ),
        ) ??
        false;
    if (ok && mounted) {
      setState(() {
        _dirty = true;
        _zones = [..._zones]..removeAt(index);
      });
    }
  }

  Future<void> _confirmClearAll() async {
    final l10n = AppLocalizations.of(context);
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.privacyZonesClearAllTitle),
            content: Text(l10n.privacyZonesClearAllBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.prefsCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: Text(l10n.privacyZonesClearAll),
              ),
            ],
          ),
        ) ??
        false;
    if (ok && mounted) {
      setState(() {
        _dirty = true;
        _zones = [];
      });
    }
  }

  // ── Location ─────────────────────────────────────────────────────────

  /// One-shot startup fix. Centres the map on the user only on first open
  /// and only when there are no zones to keep in view.
  Future<void> _backgroundLocate() async {
    if (widget.locateFn != null) {
      try {
        _applyFix(await widget.locateFn!());
      } catch (e) {
        debugPrint('privacy_zones: test locateFn fix failed: $e');
      }
      return;
    }
    if (kIsWeb) return;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _applyFix(last);
      final pos = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 5),
      );
      _applyFix(pos);
    } catch (_) {
      // Silent — the FAB is the user-initiated retry.
    }
  }

  void _applyFix(Position pos) {
    if (!mounted) return;
    final ll = LatLng(pos.latitude, pos.longitude);
    setState(() => _userLatLng = ll);
    if (_mapReady && !_centeredOnce && _zones.isEmpty) {
      _centeredOnce = true;
      _mapController.move(ll, 14);
    }
  }

  Future<void> _locate() async {
    try {
      final pos = widget.locateFn != null
          ? await widget.locateFn!()
          : await _platformLocate();
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      _centeredOnce = true;
      setState(() => _userLatLng = ll);
      _mapController.move(ll, 15);
    } catch (e) {
      if (!mounted) return;
      showTopBanner(
        context,
        AppLocalizations.of(context).privacyZonesLocationUnavailable(e),
      );
    }
  }

  Future<Position> _platformLocate() async {
    if (kIsWeb) throw UnsupportedError('Locate unavailable on web');
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      final asked = await Geolocator.requestPermission();
      if (asked == LocationPermission.denied ||
          asked == LocationPermission.deniedForever) {
        throw StateError('Location permission denied');
      }
    } else if (perm == LocationPermission.deniedForever) {
      throw StateError('Location permission denied forever');
    }
    return Geolocator.getCurrentPosition();
  }

  // ── Place search ─────────────────────────────────────────────────────

  Future<void> _onSearchChanged(String query) async {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = const [];
        _searchUnavailable = false;
        _searchOpen = false;
      });
      return;
    }
    _searchDebounce =
        Timer(const Duration(milliseconds: 300), () => _runPlaceSearch(query));
  }

  Future<void> _runPlaceSearch(String query) async {
    final outcome = await searchPlaces(
      query,
      apiKey: _maptilerKey,
      fetcher: widget.geocodingFetcher,
    );
    if (!mounted) return;
    setState(() {
      _searchResults = outcome.results;
      _searchUnavailable = outcome.isUnavailable;
      // Open on an empty result set too: a provider that matched nothing
      // must say so rather than leave the runner staring at a map that
      // did not react.
      _searchOpen = true;
    });
  }

  void _onSearchResultTap(PlaceResult r) {
    _centeredOnce = true;
    _mapController.move(LatLng(r.lat, r.lng), 14);
    FocusManager.instance.primaryFocus?.unfocus();
    _searchCtl.clear();
    setState(() {
      _searchResults = const [];
      _searchUnavailable = false;
      _searchOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final initial = _zones.isNotEmpty
        ? LatLng(_zones.first.lat, _zones.first.lng)
        : (_userLatLng ??
              const LatLng(51.5074, -0.1278)); // London-ish fallback

    return DiscardGuard(
      isDirty: () => _dirty,
      confirmBody: l10n.privacyZonesDiscardBody,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.privacyZonesTitle),
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
              TextButton(onPressed: _save, child: Text(l10n.privacyZonesSave)),
          ],
        ),
        floatingActionButton: FloatingActionButton.small(
          heroTag: 'privacy_zones_locate_fab',
          tooltip: l10n.privacyZonesLocateMe,
          onPressed: _locate,
          child: const Icon(Icons.my_location),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l10n.privacyZonesHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _searchCtl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: l10n.privacyZonesSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    l10n.privacyZonesRadius,
                    style: theme.textTheme.labelLarge,
                  ),
                  Expanded(
                    child: Slider(
                      min: 50,
                      max: 500,
                      divisions: 9,
                      value: _draftRadius,
                      label: l10n.privacyZonesRadiusMeters(
                        _draftRadius.round(),
                      ),
                      onChanged: (v) => setState(() => _draftRadius = v),
                    ),
                  ),
                  Text(l10n.privacyZonesRadiusMeters(_draftRadius.round())),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      backgroundColor:
                          basemapVoidColour(darkBasemap: darkBasemap),
                      initialCenter: initial,
                      initialZoom: 14,
                      onMapReady: () {
                        _mapReady = true;
                        if (_userLatLng != null &&
                            !_centeredOnce &&
                            _zones.isEmpty) {
                          _centeredOnce = true;
                          _mapController.move(_userLatLng!, 14);
                        }
                      },
                      onPositionChanged: (pos, hasGesture) {
                        if (hasGesture) _centeredOnce = true;
                      },
                      onTap: (_, latlng) => _addZoneAt(latlng),
                    ),
                    children: [
                      // Honours TILE_URL_TEMPLATE → MAPTILER_KEY → OSM in
                      // that order, matching every other map surface in
                      // the app. Hardcoded OSM pre-May-2026 made the
                      // privacy-zones picker the only map that worked on
                      // a Protomaps-only dev setup, which masked the
                      // resolveTileUrl regression.
                      basemapTileLayer(urlTemplate: currentTileUrl(context)),
                      CircleLayer(
                        circles: [
                          for (final z in _zones)
                            CircleMarker(
                              point: LatLng(z.lat, z.lng),
                              radius: z.radiusM,
                              useRadiusInMeter: true,
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.25,
                              ),
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
                              width: 48,
                              height: 48,
                              child: Semantics(
                                button: true,
                                label: AppLocalizations.of(
                                  context,
                                ).privacyZonesRemoveSemantics,
                                child: GestureDetector(
                                  onTap: () => _confirmRemoveZone(i),
                                  child: Center(
                                    child: Icon(
                                      Icons.cancel_outlined,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      MapAttribution(darkBasemap: darkBasemap),
                    ],
                  ),
                  if (_searchOpen)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Material(
                        elevation: 4,
                        child: PlaceSearchPanel(
                          results: _searchResults,
                          unavailable: _searchUnavailable,
                          onSelect: _onSearchResultTap,
                          onRetry: () => _runPlaceSearch(_searchCtl.text),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_zones.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: theme.colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.privacyZonesCount(_zones.length),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _confirmClearAll,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(l10n.privacyZonesClearAll),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
