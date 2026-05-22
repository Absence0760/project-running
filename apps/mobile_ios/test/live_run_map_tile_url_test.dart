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
    test('no env vars → MapTiler URL with empty key', () {
      final url = resolveTileUrl(const {});
      expect(url,
          'https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}@2x.png?key=');
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

    test('whitespace-only override is treated as set (caller responsibility)',
        () {
      // The helper only checks `isNotEmpty` — a value like " " is
      // technically non-empty. flutter_map would fail on the
      // malformed URL anyway; we don't try to second-guess the
      // operator's config here.
      final url = resolveTileUrl(const {
        'TILE_URL_TEMPLATE': ' ',
      });
      expect(url, ' ',
          reason: 'override resolution is by-string not by-validity');
    });
  });
}
