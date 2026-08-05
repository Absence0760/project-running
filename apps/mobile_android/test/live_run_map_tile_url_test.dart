import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/live_run_map.dart';

/// Unit tests for [resolveTileUrl] / [resolveBasemapIsDark] — the pure
/// raster-tile resolvers behind every mobile map surface. Pins:
///
///  * The MapTiler style named by the user's `map_style` preference
///    (issue #666 round 2: Settings offered Streets / Satellite /
///    Outdoors / Dark and persisted the choice, but nothing read it back
///    and all seven maps were hard-locked to `streets-v2-dark`).
///  * `streets` following the app theme, matching web's
///    `buildMapStyleUrl`.
///  * The `TILE_URL_TEMPLATE` override that drives the local Protomaps
///    tileserver-gl dev setup. See `docs/ops/protomaps_local_setup.md` +
///    `decisions.md § 68`.
///  * Overlay colours deriving from the RESOLVED basemap, not the app
///    theme — with no MapTiler key the fallback is a light OSM set, which
///    a dark-basemap casing and white marker rings disappear into.
///
/// The widget itself can't run on the host JVM (it needs `flutter run` +
/// a window), so the testable seam is these resolvers.

/// Representative land fills, sampled for the contrast floors below.
/// Not exact — basemaps are multi-coloured — but the right order of
/// magnitude for "does this overlay separate from the map at all".
const _lightBasemapSample = Color(0xFFF2EFE9);
const _darkBasemapSample = Color(0xFF1A1B20);

/// WCAG 1.4.11's non-text bar, applied to overlay-vs-basemap.
const _overlayFloor = 3.0;

double _luminance(Color c) {
  double chan(double v) {
    v /= 255.0;
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  // ignore: deprecated_member_use
  return 0.2126 * chan(c.red.toDouble()) +
      // ignore: deprecated_member_use
      0.7152 * chan(c.green.toDouble()) +
      // ignore: deprecated_member_use
      0.0722 * chan(c.blue.toDouble());
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

String _url(
  Map<String, String> env, {
  String mapStyle = 'streets',
  Brightness brightness = Brightness.dark,
}) =>
    resolveTileUrl(env, mapStyle: mapStyle, brightness: brightness);

bool _isDark(
  Map<String, String> env, {
  String mapStyle = 'streets',
  Brightness brightness = Brightness.dark,
}) =>
    resolveBasemapIsDark(env, mapStyle: mapStyle, brightness: brightness);

void main() {
  group('resolveTileUrl', () {
    test('no env vars → OSM fallback', () {
      // May 2026 audit: previously this returned a MapTiler URL
      // with an empty `?key=`, which 403s every tile request. The
      // OSM tiles let the map render SOMETHING on an unconfigured
      // dev machine; MissingMapTilesHint surfaces the diagnostic
      // alongside.
      expect(_url(const {}), 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    });

    test('whitespace-only MAPTILER_KEY → OSM fallback', () {
      // Same fail-safe applies when the key is a stray whitespace
      // — equivalent to "unconfigured".
      expect(_url(const {'MAPTILER_KEY': '   '}),
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    });

    test('streets follows the app theme', () {
      expect(
        _url(const {'MAPTILER_KEY': 'abc123'}, brightness: Brightness.dark),
        'https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}@2x.png?key=abc123',
      );
      expect(
        _url(const {'MAPTILER_KEY': 'abc123'}, brightness: Brightness.light),
        'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}@2x.png?key=abc123',
      );
    });

    test('each preference resolves to its own MapTiler slug', () {
      const env = {'MAPTILER_KEY': 'k'};
      expect(_url(env, mapStyle: 'satellite'), contains('/maps/satellite/'));
      expect(_url(env, mapStyle: 'outdoors'), contains('/maps/outdoor-v2/'));
      expect(_url(env, mapStyle: 'dark'), contains('/maps/streets-v2-dark/'));
    });

    test('a fixed style ignores the app theme', () {
      // Only `streets` is theme-derived — picking Satellite in the light
      // theme must not silently hand back a street map.
      for (final style in const ['satellite', 'outdoors', 'dark']) {
        expect(
          _url(const {'MAPTILER_KEY': 'k'},
              mapStyle: style, brightness: Brightness.light),
          _url(const {'MAPTILER_KEY': 'k'},
              mapStyle: style, brightness: Brightness.dark),
          reason: '$style must resolve identically in both themes',
        );
      }
    });

    test('an unknown style falls back to streets, never to a blank map', () {
      expect(
        _url(const {'MAPTILER_KEY': 'k'},
            mapStyle: 'terrain-from-a-newer-client'),
        contains('/maps/streets-v2-dark/'),
      );
    });

    test('TILE_URL_TEMPLATE override wins outright', () {
      // The local Protomaps tileserver-gl dev path. The override
      // bypasses MapTiler entirely — local server has no API key.
      expect(
        _url(const {
          'TILE_URL_TEMPLATE':
              'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
        }),
        'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
      );
    });

    test('the override outranks the style preference too', () {
      for (final style in const ['streets', 'satellite', 'outdoors', 'dark']) {
        expect(
          _url(const {
            'MAPTILER_KEY': 'production-key',
            'TILE_URL_TEMPLATE':
                'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
          }, mapStyle: style),
          'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
          reason: 'local dev runs one self-hosted style for every '
              'preference — matches web buildMapStyleUrl',
        );
      }
    });

    test('override wins even when MAPTILER_KEY is also set', () {
      // Dev path keeps the key in .env.local for production builds
      // — the override flips the URL only when present.
      final url = _url(const {
        'MAPTILER_KEY': 'production-key',
        'TILE_URL_TEMPLATE':
            'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
      });
      expect(url, 'http://localhost:8080/styles/basic/{z}/{x}/{y}.png');
      expect(url.contains('maptiler.com'), isFalse,
          reason: 'override path must NOT include the MapTiler URL');
      expect(url.contains('production-key'), isFalse,
          reason: 'override path must NOT include the MapTiler key');
    });

    test('empty-string override is treated as absent', () {
      expect(_url(const {'TILE_URL_TEMPLATE': '', 'MAPTILER_KEY': 'x'}),
          contains('maptiler.com'));
    });

    test('Android emulator alias 10.0.2.2 round-trips intact', () {
      // The emulator's loopback alias for the host — what
      // bin/protomaps-dev.sh tells the user to use when targeting
      // the emulator.
      expect(
        _url(const {
          'TILE_URL_TEMPLATE':
              'http://10.0.2.2:8080/styles/basic/{z}/{x}/{y}.png',
        }),
        'http://10.0.2.2:8080/styles/basic/{z}/{x}/{y}.png',
      );
    });

    test('override preserves the {z}/{x}/{y} placeholder shape', () {
      // The tile template must keep flutter_map's curly-brace
      // placeholders intact — flutter_map substitutes them per
      // tile. A malformed override that hardcoded numbers would
      // produce the same tile for every grid cell.
      final url = _url(const {
        'TILE_URL_TEMPLATE':
            'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
      });
      expect(url.contains('{z}'), isTrue);
      expect(url.contains('{x}'), isTrue);
      expect(url.contains('{y}'), isTrue);
    });

    test('every resolved MapTiler URL keeps the placeholder shape', () {
      for (final style in const ['streets', 'satellite', 'outdoors', 'dark']) {
        final url = _url(const {'MAPTILER_KEY': 'k'}, mapStyle: style);
        expect(url, contains('{z}/{x}/{y}'), reason: style);
      }
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
        final url = _url({
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
      expect(
        _url(const {
          'TILE_URL_TEMPLATE':
              '  http://localhost:8080/styles/basic/{z}/{x}/{y}.png\n',
        }),
        'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
      );
    });

    test('override containing query params round-trips intact', () {
      // A custom local server might require an auth token query
      // param. The resolver doesn't strip, encode, or otherwise
      // touch the URL beyond trimming.
      expect(
        _url(const {
          'TILE_URL_TEMPLATE':
              'http://localhost:8080/t/{z}/{x}/{y}.png?token=abc&debug=1',
        }),
        'http://localhost:8080/t/{z}/{x}/{y}.png?token=abc&debug=1',
      );
    });

    test('https override round-trips intact (production-shape override)', () {
      // Forward-compat: a future cloud-hosted Protomaps URL.
      expect(
        _url(const {
          'TILE_URL_TEMPLATE':
              'https://tiles.example.com/styles/basic/{z}/{x}/{y}.png',
        }),
        'https://tiles.example.com/styles/basic/{z}/{x}/{y}.png',
      );
    });
  });

  group('resolveBasemapIsDark', () {
    test('the OSM fallback is light in either app theme', () {
      // The fallout the audit named: with no key the map is a LIGHT
      // OSM set, and overlays specified for dark vanish into it.
      expect(_isDark(const {}, brightness: Brightness.dark), isFalse);
      expect(_isDark(const {}, brightness: Brightness.light), isFalse);
    });

    test('streets follows the app theme', () {
      const env = {'MAPTILER_KEY': 'k'};
      expect(_isDark(env, brightness: Brightness.dark), isTrue);
      expect(_isDark(env, brightness: Brightness.light), isFalse);
    });

    test('the dark preference is dark even in the light theme', () {
      expect(
        _isDark(const {'MAPTILER_KEY': 'k'},
            mapStyle: 'dark', brightness: Brightness.light),
        isTrue,
      );
    });

    test('outdoors is light, satellite counts as dark', () {
      const env = {'MAPTILER_KEY': 'k'};
      expect(_isDark(env, mapStyle: 'outdoors', brightness: Brightness.dark),
          isFalse);
      expect(_isDark(env, mapStyle: 'satellite', brightness: Brightness.light),
          isTrue);
    });

    test('an override is light unless its URL names a dark style', () {
      expect(
        _isDark(const {
          'TILE_URL_TEMPLATE':
              'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
        }),
        isFalse,
        reason: 'bin/protomaps-dev.sh serves the light `basic` style',
      );
      expect(
        _isDark(const {
          'TILE_URL_TEMPLATE':
              'http://localhost:8080/styles/DARK/{z}/{x}/{y}.png',
        }),
        isTrue,
      );
    });
  });

  group('overlay colours follow the resolved basemap', () {
    test('the casing separates from the basemap in both directions', () {
      expect(
        _contrast(mapOverlayOutline(darkBasemap: true), _darkBasemapSample),
        greaterThanOrEqualTo(_overlayFloor),
      );
      expect(
        _contrast(mapOverlayOutline(darkBasemap: false), _lightBasemapSample),
        greaterThanOrEqualTo(_overlayFloor),
      );
    });

    test('the two casings are not the same colour', () {
      // The bug this closes: one fixed dark casing used on every
      // basemap, which computes to 1.08:1 against the dark one.
      expect(mapOverlayOutline(darkBasemap: true),
          isNot(mapOverlayOutline(darkBasemap: false)));
    });

    test('every track gradient stop clears the floor against its basemap', () {
      for (final stop in trackGradientColours(darkBasemap: true)) {
        expect(_contrast(stop, _darkBasemapSample),
            greaterThanOrEqualTo(_overlayFloor));
      }
      for (final stop in trackGradientColours(darkBasemap: false)) {
        expect(_contrast(stop, _lightBasemapSample),
            greaterThanOrEqualTo(_overlayFloor));
      }
    });

    test('the newest gradient stop is the most prominent on both basemaps', () {
      // The comet reads oldest → newest; the newest stretch must be the
      // one furthest from the map, whichever way the ramp runs.
      final dark = trackGradientColours(darkBasemap: true);
      expect(_contrast(dark.last, _darkBasemapSample),
          greaterThan(_contrast(dark.first, _darkBasemapSample)));
      final light = trackGradientColours(darkBasemap: false);
      expect(_contrast(light.last, _lightBasemapSample),
          greaterThan(_contrast(light.first, _lightBasemapSample)));
    });
  });
}
