// The share-card rasterisers used to sleep ~700 ms and then grab the frame,
// so a cold tile fetch baked a part-black map into the exported PNG (issue
// #666 S17). These pin the observation that replaced the sleep — and the
// absence of the sleep itself, because lengthening it would "fix" the symptom
// while leaving the race.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/map_tile_readiness.dart';

/// A [TileImage] is awkward to build standalone, so drive the readiness object
/// through the same `tileBuilder` signature the layer calls.
TileImage _tile(int x, {required bool loaded, bool error = false}) {
  final image = TileImage(
    vsync: const TestVSync(),
    coordinates: TileCoordinates(x, 0, 12),
    imageProvider: const AssetImage('nonexistent'),
    onLoadComplete: (_) {},
    onLoadError: (_, __, ___) {},
    tileDisplay: const TileDisplay.instantaneous(),
    errorImage: null,
    cancelLoading: Completer<void>(),
  );
  if (loaded) image.loadFinishedAt = DateTime.now();
  image.loadError = error;
  return image;
}

void main() {
  group('MapTileReadiness (issue #666 S17)', () {
    test('an unobserved layer is not settled — the wait must not short-circuit',
        () {
      expect(MapTileReadiness().isSettled, isFalse);
    });

    testWidgets('settles only once every observed tile has finished',
        (tester) async {
      final readiness = MapTileReadiness();
      final loaded = _tile(0, loaded: true);
      final pending = _tile(1, loaded: false);

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            readiness.observe(context, const SizedBox(), loaded);
            readiness.observe(context, const SizedBox(), pending);
            return const SizedBox();
          },
        ),
      );

      expect(readiness.isSettled, isFalse,
          reason: 'one tile is still loading');

      pending.loadFinishedAt = DateTime.now();
      expect(readiness.isSettled, isTrue);
    });

    testWidgets('a tile that FAILED counts as settled', (tester) async {
      // flutter_map stamps loadFinishedAt on an error too. Waiting for a 403
      // or an offline tile to succeed would hold the export open until the
      // ceiling and then export exactly the same frame.
      final readiness = MapTileReadiness();
      final failed = _tile(0, loaded: true, error: true);
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            readiness.observe(context, const SizedBox(), failed);
            return const SizedBox();
          },
        ),
      );
      expect(readiness.isSettled, isTrue);
    });

    testWidgets('settled() returns as soon as the tiles are ready',
        (tester) async {
      final readiness = MapTileReadiness();
      final tile = _tile(0, loaded: false);
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            readiness.observe(context, const SizedBox(), tile);
            return const SizedBox();
          },
        ),
      );

      bool? outcome;
      unawaited(readiness.settled().then((ok) => outcome = ok));
      await tester.pump(const Duration(milliseconds: 50));
      expect(outcome, isNull, reason: 'the tile has not loaded yet');

      tile.loadFinishedAt = DateTime.now();
      await tester.pump(const Duration(milliseconds: 50));
      expect(outcome, isTrue);
    });

    testWidgets('settled() gives up at the ceiling and says so',
        (tester) async {
      final readiness = MapTileReadiness();
      final stuck = _tile(0, loaded: false);
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            readiness.observe(context, const SizedBox(), stuck);
            return const SizedBox();
          },
        ),
      );

      bool? outcome;
      unawaited(
        readiness
            .settled(ceiling: const Duration(milliseconds: 80))
            .then((ok) => outcome = ok),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(outcome, isFalse);
    });
  });

  group('the share-card rasterisers observe rather than sleep', () {
    // The discipline rule this pins: a race is not fixed by lengthening the
    // interval that hides it. Both cards used `Future.delayed(700ms)` between
    // building the map and rasterising it.
    for (final path in const [
      'lib/widgets/run_share_card.dart',
      'lib/widgets/route_share_card.dart',
    ]) {
      test('$path waits on MapTileReadiness, with no sleep left behind', () {
        final src = File(path).readAsStringSync();
        expect(src, contains('MapTileReadiness'));
        expect(src, contains('tileBuilder: tileReadiness?.observe'));
        expect(src, contains('.settled()'));
        expect(src.contains('Future.delayed'), isFalse,
            reason: 'a fixed sleep is a guess about network latency');
      });
    }
  });
}
