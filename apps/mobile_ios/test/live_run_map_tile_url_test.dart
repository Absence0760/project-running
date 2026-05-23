import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/live_run_map.dart';

/// Unit tests for [resolveTileUrl] — the pure raster-tile
/// URL builder used by both the live-recording map and every
/// run-detail map. Pins:
///
///  * The legacy MapTiler default (production path).
///  * The `TILE_URL_TEMPLATE` override that drives the local
///    Protomaps tileserver-gl dev setup. See
///    `docs/protomaps_local_setup.md` + `decisions.md § 68`.
///
/// The widget itself can't run on the host JVM (it needs `flutter
/// run` + a window), so the testable seam is this resolver.
void main() {
  group('resolveTileUrl', () {
    test('no env vars → OSM fallback', () {
      // May 2026 audit: previously this returned a MapTiler URL
      // with an empty `?key=`, which 403s every tile request. The
      // OSM tiles let the map render SOMETHING on an unconfigured
      // dev machine; MissingMapTilesHint surfaces the diagnostic
      // alongside.
      final url = resolveTileUrl(const {});
      expect(url, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    });

    test('whitespace-only MAPTILER_KEY → OSM fallback', () {
      // Same fail-safe applies when the key is a stray whitespace
      // — equivalent to "unconfigured".
      final url = resolveTileUrl(const {
        'MAPTILER_KEY': '   ',
      });
      expect(url, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    });

    test('MAPTILER_KEY set → MapTiler URL with key', () {
      final url = resolveTileUrl(const {
        'MAPTILER_KEY': 'abc123',
      });
      expect(url,
          'https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}@2x.png?key=abc123');
    });

    test('TILE_URL_TEMPLATE override wins outright', () {
      // The local Protomaps tileserver-gl dev path. The override
      // bypasses MapTiler entirely — local server has no API key.
      final url = resolveTileUrl(const {
        'TILE_URL_TEMPLATE':
            'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
      });
      expect(url,
          'http://localhost:8080/styles/basic/{z}/{x}/{y}.png');
    });

    test('override wins even when MAPTILER_KEY is also set', () {
      // Dev path keeps the key in .env.local for production builds
      // — the override flips the URL only when present.
      final url = resolveTileUrl(const {
        'MAPTILER_KEY': 'production-key',
        'TILE_URL_TEMPLATE':
            'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
      });
      expect(url,
          'http://localhost:8080/styles/basic/{z}/{x}/{y}.png');
      expect(url.contains('maptiler.com'), isFalse,
          reason: 'override path must NOT include the MapTiler URL');
      expect(url.contains('production-key'), isFalse,
          reason: 'override path must NOT include the MapTiler key');
    });

    test('empty-string override is treated as absent', () {
      final url = resolveTileUrl(const {
        'TILE_URL_TEMPLATE': '',
        'MAPTILER_KEY': 'x',
      });
      expect(url.contains('maptiler.com'), isTrue,
          reason: 'empty override → MapTiler');
    });

    test('Android emulator alias 10.0.2.2 round-trips intact', () {
      // The emulator's loopback alias for the host — what
      // bin/protomaps-dev.sh tells the user to use when targeting
      // the emulator.
      final url = resolveTileUrl(const {
        'TILE_URL_TEMPLATE':
            'http://10.0.2.2:8080/styles/basic/{z}/{x}/{y}.png',
      });
      expect(url,
          'http://10.0.2.2:8080/styles/basic/{z}/{x}/{y}.png');
    });

    test('override preserves the {z}/{x}/{y} placeholder shape', () {
      // The tile template must keep flutter_map's curly-brace
      // placeholders intact — flutter_map substitutes them per
      // tile. A malformed override that hardcoded numbers would
      // produce the same tile for every grid cell.
      final url = resolveTileUrl(const {
        'TILE_URL_TEMPLATE':
            'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
      });
      expect(url.contains('{z}'), isTrue);
      expect(url.contains('{x}'), isTrue);
      expect(url.contains('{y}'), isTrue);
    });

    test('whitespace-only override falls back to MapTiler (no silent breakage)',
        () {
      // A stray space after `TILE_URL_TEMPLATE=` in .env.local is
      // a really common copy/paste mistake. Treating it as a valid
      // override would silently disable MapTiler + send tile
      // requests to ` ` (literal space) which flutter_map fails
      // on opaquely. The May 2026 audit pass moved the resolver
      // to `trim().isNotEmpty` — matches the Wear OS `isNotBlank`
      // semantics.
      for (final whitespace in const [' ', '   ', '\t', '\n', ' \t \n ']) {
        final url = resolveTileUrl({
          'TILE_URL_TEMPLATE': whitespace,
          'MAPTILER_KEY': 'real-key',
        });
        expect(url.contains('maptiler.com'), isTrue,
            reason: 'whitespace override (${whitespace.codeUnits}) must '
                'fall through to MapTiler');
        expect(url.contains('real-key'), isTrue);
      }
    });

    test('override with surrounding whitespace is trimmed', () {
      // A trailing newline from an editor that auto-appends one is
      // ALSO common. Trim + use the real value rather than reject.
      final url = resolveTileUrl(const {
        'TILE_URL_TEMPLATE':
            '  http://localhost:8080/styles/basic/{z}/{x}/{y}.png\n',
      });
      expect(url,
          'http://localhost:8080/styles/basic/{z}/{x}/{y}.png');
    });

    test('override containing query params round-trips intact', () {
      // A custom local server might require an auth token query
      // param. The resolver doesn't strip, encode, or otherwise
      // touch the URL beyond trimming.
      final url = resolveTileUrl(const {
        'TILE_URL_TEMPLATE':
            'http://localhost:8080/t/{z}/{x}/{y}.png?token=abc&debug=1',
      });
      expect(url,
          'http://localhost:8080/t/{z}/{x}/{y}.png?token=abc&debug=1');
    });

    test('https override round-trips intact (production-shape override)',
        () {
      // Forward-compat: a future cloud-hosted Protomaps URL.
      final url = resolveTileUrl(const {
        'TILE_URL_TEMPLATE':
            'https://tiles.example.com/styles/basic/{z}/{x}/{y}.png',
      });
      expect(url,
          'https://tiles.example.com/styles/basic/{z}/{x}/{y}.png');
    });
  });
}
