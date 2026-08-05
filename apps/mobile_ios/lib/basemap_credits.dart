import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Read dotenv defensively — bare `dotenv.env` throws
/// `NotInitializedError` when the harness hasn't called `dotenv.load()`,
/// which then propagates up and prevents the screen from rendering at all
/// (real bug found by the May 2026 audit when the privacy-zones + heatmap
/// screens started reading dotenv in their TileLayer URL). Tiles are an L2
/// layer: failing to resolve one must never take a screen down with it.
Map<String, String> tileEnv() {
  try {
    return dotenv.env;
  } catch (e) {
    debugPrint('dotenv unavailable for tile resolution: $e');
    return const {};
  }
}

/// One party the resolved basemap owes a visible credit to.
///
/// [name] is a proper noun and is never translated; the sentence around it
/// is, which is why the surrounding copy lives in the ARBs and only the
/// name travels in this record.
class MapCredit {
  final String name;
  final String url;

  /// True when the credit is for OpenStreetMap's *data* rather than a
  /// renderer, in which case ODbL wants "contributors" alongside the name.
  final bool osmData;

  const MapCredit({
    required this.name,
    required this.url,
    this.osmData = false,
  });
}

const _maptiler = MapCredit(
  name: 'MapTiler',
  url: 'https://www.maptiler.com/copyright/',
);
const _openStreetMap = MapCredit(
  name: 'OpenStreetMap',
  url: 'https://www.openstreetmap.org/copyright',
  osmData: true,
);
const _protomaps = MapCredit(
  name: 'Protomaps',
  url: 'https://protomaps.com/',
);

/// Credits owed by the basemap `resolveTileUrl` resolves to under the same
/// env. The branches match that resolver's precedence exactly, because a
/// credit naming a provider whose tiles are not on screen is as wrong as
/// no credit at all.
///
///  * `TILE_URL_TEMPLATE` override — the documented target is a local
///    Protomaps `tileserver-gl` (`docs/ops/protomaps_local_setup.md`),
///    whose PMTiles are built from OpenStreetMap, so both are named.
///  * `MAPTILER_KEY` — MapTiler Cloud's terms require "© MapTiler" on
///    screen whenever a map is displayed, plus "© OpenStreetMap
///    contributors" because every MapTiler style we resolve to (including
///    satellite, whose labels are OSM-derived) carries OSM data.
///  * Neither — the OSM raster fallback, which owes the ODbL credit and
///    nothing else.
List<MapCredit> basemapCreditsFor(Map<String, String> env) {
  if ((env['TILE_URL_TEMPLATE'] ?? '').trim().isNotEmpty) {
    return const [_protomaps, _openStreetMap];
  }
  if ((env['MAPTILER_KEY'] ?? '').trim().isEmpty) {
    return const [_openStreetMap];
  }
  return const [_maptiler, _openStreetMap];
}

/// Production-callsite convenience: the credits for the basemap this build
/// actually resolves to.
List<MapCredit> currentBasemapCredits() => basemapCreditsFor(tileEnv());
