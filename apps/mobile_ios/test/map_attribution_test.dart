// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/basemap_credits.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/map_attribution.dart';

/// Issue #666 round 7, S13. `flutter_map` renders no attribution of its own,
/// so seven map surfaces displayed MapTiler and OpenStreetMap tiles crediting
/// neither — an unfinished look and a basemap-ToS gap. MapTiler Cloud's terms
/// require "© MapTiler" on screen whenever a map is displayed plus
/// "© OpenStreetMap contributors" for the OSM data underneath; OSM's data is
/// ODbL and owes that credit on its own account.
///
/// The credits must follow the RESOLVED basemap — since § 489 that varies by
/// preference, theme and env override, so a hardcoded string would name a
/// provider whose tiles are not on screen.

/// Representative land fills, the same samples `live_run_map_tile_url_test`
/// declares. Not exact — a basemap is many colours — but the right order of
/// magnitude.
const _lightBasemapSample = Color(0xFFF2EFE9);
const _darkBasemapSample = Color(0xFF1A1B20);

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

/// Source-over composite of [top] onto [under], in the sRGB-encoded space
/// Flutter blends in.
Color _over(Color top, Color under) {
  // ignore: deprecated_member_use
  final a = top.a;
  int ch(double t, double u) => (t * a + u * (1 - a)).round();
  return Color.fromARGB(
    255,
    // ignore: deprecated_member_use
    ch(top.r * 255, under.r * 255),
    // ignore: deprecated_member_use
    ch(top.g * 255, under.g * 255),
    // ignore: deprecated_member_use
    ch(top.b * 255, under.b * 255),
  );
}

Future<void> _pump(WidgetTester tester, Widget child, {Locale? locale}) =>
    tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ));

void main() {
  group('basemapCreditsFor follows the resolved basemap', () {
    test('MapTiler branch credits MapTiler and OpenStreetMap', () {
      final credits = basemapCreditsFor(const {'MAPTILER_KEY': 'abc'});
      expect(credits.map((c) => c.name), ['MapTiler', 'OpenStreetMap']);
      expect(credits.first.url, 'https://www.maptiler.com/copyright/');
      expect(credits.last.url, 'https://www.openstreetmap.org/copyright');
      expect(credits.last.osmData, isTrue);
    });

    test('the keyless OSM raster fallback credits OpenStreetMap alone', () {
      // Crediting MapTiler here would name a provider whose tiles are not
      // on screen, which is as wrong as crediting nobody.
      final credits = basemapCreditsFor(const {});
      expect(credits.map((c) => c.name), ['OpenStreetMap']);
      expect(credits.single.osmData, isTrue);
    });

    test('a blank key is treated as absent, matching resolveTileUrl', () {
      expect(
        basemapCreditsFor(const {'MAPTILER_KEY': '   '}).map((c) => c.name),
        ['OpenStreetMap'],
      );
    });

    test('the TILE_URL_TEMPLATE override credits Protomaps and OSM', () {
      // `bin/protomaps-dev.sh` serves PMTiles built from OpenStreetMap, so
      // the ODbL credit is owed on the dev path too.
      final credits = basemapCreditsFor(const {
        'TILE_URL_TEMPLATE': 'http://localhost:8080/styles/basic/{z}/{x}/{y}.png',
        'MAPTILER_KEY': 'abc',
      });
      expect(credits.map((c) => c.name), ['Protomaps', 'OpenStreetMap']);
    });

    test('every credit carries an https link — attribution must be linked',
        () {
      for (final env in const [
        <String, String>{},
        {'MAPTILER_KEY': 'abc'},
        {'TILE_URL_TEMPLATE': 'http://localhost:8080/x/{z}/{x}/{y}.png'},
      ]) {
        for (final c in basemapCreditsFor(env)) {
          expect(c.url, startsWith('https://'), reason: 'credit ${c.name}');
        }
      }
    });

    test('tileEnv degrades to empty rather than throwing on cold dotenv', () {
      // dotenv is not loaded in this harness; a NotInitializedError escaping
      // here would take the whole map screen down (May 2026 audit).
      expect(tileEnv(), isEmpty);
    });
  });

  group('MapAttribution renders the credit', () {
    testWidgets('names both parties on the MapTiler basemap', (tester) async {
      await _pump(
        tester,
        MapAttribution(
          darkBasemap: true,
          creditsOverride: basemapCreditsFor(const {'MAPTILER_KEY': 'abc'}),
        ),
      );
      expect(find.text('© MapTiler'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    });

    testWidgets('names OpenStreetMap alone on the fallback', (tester) async {
      await _pump(
        tester,
        MapAttribution(
          darkBasemap: false,
          creditsOverride: basemapCreditsFor(const {}),
        ),
      );
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.text('© MapTiler'), findsNothing);
    });

    testWidgets('the surrounding sentence is localized, the names are not',
        (tester) async {
      await _pump(
        tester,
        MapAttribution(
          darkBasemap: true,
          creditsOverride: basemapCreditsFor(const {'MAPTILER_KEY': 'abc'}),
        ),
        locale: const Locale('fr'),
      );
      expect(find.text('© les contributeurs OpenStreetMap'), findsOneWidget);
      expect(find.text('© MapTiler'), findsOneWidget);
    });

    testWidgets('anchors to the bottom start, clear of the locate FAB',
        (tester) async {
      // Every map's locate / re-centre control is a FAB, which Material
      // anchors to the end. A credit a floating button covers is not a
      // credit, so the strip takes the opposite corner — directionally, so
      // the two stay opposite if an RTL locale is ever added.
      await _pump(
        tester,
        MapAttribution(
          darkBasemap: true,
          creditsOverride: basemapCreditsFor(const {'MAPTILER_KEY': 'abc'}),
        ),
      );
      final align = tester.widget<Align>(
        find.descendant(
          of: find.byType(MapAttribution),
          matching: find.byType(Align),
        ),
      );
      expect(align.alignment, AlignmentDirectional.bottomStart);
    });

    testWidgets('each credit is an activatable link with an a11y label',
        (tester) async {
      await _pump(
        tester,
        MapAttribution(
          darkBasemap: true,
          creditsOverride: basemapCreditsFor(const {'MAPTILER_KEY': 'abc'}),
        ),
      );
      expect(find.byType(GestureDetector), findsNWidgets(2));
      expect(find.bySemanticsLabel('Map data attribution'), findsOneWidget);
    });
  });

  group('the credit stays legible over whatever the basemap paints', () {
    test('text clears 4.5:1 against its own scrim on both basemaps', () {
      for (final dark in const [true, false]) {
        final ink = attributionInk(darkBasemap: dark);
        final sample = dark ? _darkBasemapSample : _lightBasemapSample;
        final slab = _over(attributionScrim(darkBasemap: dark), sample);
        expect(_contrast(ink, slab), greaterThanOrEqualTo(4.5),
            reason: 'darkBasemap=$dark over its representative fill');
      }
    });

    test('and over the worst patch the opposite-luminance basemap can show',
        () {
      // A snow field under the dark scrim, a tarmac shadow under the light
      // one — the scrim, not the basemap, is what has to carry the text.
      expect(
        _contrast(
          attributionInk(darkBasemap: true),
          _over(attributionScrim(darkBasemap: true), const Color(0xFFFFFFFF)),
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(
          attributionInk(darkBasemap: false),
          _over(attributionScrim(darkBasemap: false), const Color(0xFF000000)),
        ),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('every map surface carries the credit and the failure treatment', () {
    // The seven `FlutterMap`s in lib/. Attribution is a licence obligation,
    // not a per-screen nicety, so this list is the whole set by construction
    // — a new map that forgets it fails here.
    const mapFiles = [
      'lib/widgets/live_run_map.dart',
      'lib/widgets/route_share_card.dart',
      'lib/widgets/run_share_card.dart',
      'lib/screens/route_builder_screen.dart',
      'lib/screens/privacy_zones_screen.dart',
      'lib/screens/routes_heatmap_screen.dart',
      'lib/screens/run_heatmap_screen.dart',
    ];

    test('the file list is exactly the files that mount a FlutterMap', () {
      final found = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        if (src.contains('FlutterMap(')) found.add(entity.path);
      }
      expect(found..sort(), equals([...mapFiles]..sort()));
    });

    test('each mounts a MapAttribution', () {
      for (final path in mapFiles) {
        expect(File(path).readAsStringSync(), contains('MapAttribution('),
            reason: '$path renders a basemap without crediting it.');
      }
    });

    test('each builds its raster layer through basemapTileLayer', () {
      for (final path in mapFiles) {
        final src = File(path).readAsStringSync();
        expect(src, contains('basemapTileLayer('), reason: path);
        // `basemapTileLayer` itself is the app's one `TileLayer(` — anywhere
        // else is a map that skipped the shared error-tile eviction.
        final expected = path == 'lib/widgets/live_run_map.dart' ? 1 : 0;
        expect(RegExp(r'\bTileLayer\(').allMatches(src).length, expected,
            reason: path);
      }
    });

    test('each paints a basemap-keyed void behind the tiles', () {
      // flutter_map's own default is #E0E0E0, a 13:1 rectangle against the
      // dark basemap — a failed tile read as a hole punched in the map.
      for (final path in mapFiles) {
        expect(File(path).readAsStringSync(), contains('basemapVoidColour('),
            reason: path);
      }
    });
  });
}
