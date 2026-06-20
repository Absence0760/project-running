import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/offline_tile_pack.dart';
import 'package:mobile_android/tile_pack.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('offline_pack_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // A small bbox at low zoom keeps the tile count tiny and deterministic.
  const bbox = TileBbox(minLat: 51.50, minLng: -0.13, maxLat: 51.51, maxLng: -0.11);

  Uint8List fakeTile() => Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

  test('happy path writes one file per tile and settles ready', () async {
    var fetched = 0;
    final store = OfflineTilePackStore(
      tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
      fetcher: (url) async {
        fetched++;
        return fakeTile();
      },
    );
    await store.init(overrideDirectory: tmp);
    final expected =
        tilesForBbox(bbox, minZoom: 12, maxZoom: 13).length;

    await store.downloadPack('r1', bbox, minZoom: 12, maxZoom: 13);

    final p = store.progressFor('r1');
    expect(p.status, OfflinePackStatus.ready);
    expect(p.done, expected);
    expect(p.total, expected);
    expect(fetched, expected);
  });

  test('a failing tile is isolated; the pack completes partially', () async {
    var n = 0;
    final store = OfflineTilePackStore(
      tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
      fetcher: (url) async {
        n++;
        return n == 1 ? null : fakeTile(); // first tile fails
      },
    );
    await store.init(overrideDirectory: tmp);

    await store.downloadPack('r2', bbox, minZoom: 12, maxZoom: 12);

    final p = store.progressFor('r2');
    expect(p.status, OfflinePackStatus.partial);
    expect(p.done, lessThan(p.total));
  });

  test('a thrown fetch is caught and counted as a miss', () async {
    final store = OfflineTilePackStore(
      tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
      fetcher: (url) async => throw Exception('boom'),
    );
    await store.init(overrideDirectory: tmp);

    await store.downloadPack('r3', bbox, minZoom: 12, maxZoom: 12);

    final p = store.progressFor('r3');
    expect(p.status, OfflinePackStatus.partial);
    expect(p.done, 0);
  });

  test('a retry only fetches the gaps', () async {
    var n = 0;
    final store = OfflineTilePackStore(
      tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
      fetcher: (url) async {
        n++;
        return n == 1 ? null : fakeTile();
      },
    );
    await store.init(overrideDirectory: tmp);
    await store.downloadPack('r4', bbox, minZoom: 12, maxZoom: 12);
    final firstRoundFetches = n;
    // Re-run with a fetcher that always succeeds — only the missing tile(s).
    var retryFetches = 0;
    final store2 = OfflineTilePackStore(
      tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
      fetcher: (url) async {
        retryFetches++;
        return fakeTile();
      },
    );
    await store2.init(overrideDirectory: tmp);
    await store2.downloadPack('r4', bbox, minZoom: 12, maxZoom: 12);

    expect(store2.progressFor('r4').status, OfflinePackStatus.ready);
    // Retry fetched fewer than the full first round (the on-disk tiles skip).
    expect(retryFetches, lessThan(firstRoundFetches));
  });

  test('deletePack removes the pack directory', () async {
    final store = OfflineTilePackStore(
      tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
      fetcher: (url) async => fakeTile(),
    );
    await store.init(overrideDirectory: tmp);
    await store.downloadPack('r5', bbox, minZoom: 12, maxZoom: 12);
    expect(Directory('${tmp.path}/r5').existsSync(), isTrue);

    await store.deletePack('r5');

    expect(Directory('${tmp.path}/r5').existsSync(), isFalse);
    expect(store.progressFor('r5').status, OfflinePackStatus.absent);
  });

  test('the count cap is enforced (status tooLarge, no download)', () async {
    var fetched = 0;
    final store = OfflineTilePackStore(
      tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
      fetcher: (url) async {
        fetched++;
        return fakeTile();
      },
    );
    await store.init(overrideDirectory: tmp);
    // A world-spanning bbox at z16 vastly exceeds the per-pack cap.
    const huge = TileBbox(minLat: -80, minLng: -179, maxLat: 80, maxLng: 179);

    await store.downloadPack('r6', huge, minZoom: 16, maxZoom: 16);

    expect(store.progressFor('r6').status, OfflinePackStatus.tooLarge);
    expect(fetched, 0);
  });

  test('cachedTile finds a written tile and misses an absent one', () async {
    final store = OfflineTilePackStore(
      tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
      fetcher: (url) async => fakeTile(),
    );
    await store.init(overrideDirectory: tmp);
    final tiles = tilesForBbox(bbox, minZoom: 12, maxZoom: 12);
    await store.downloadPack('r7', bbox, minZoom: 12, maxZoom: 12);

    final first = tiles.first;
    final hit = await store.cachedTile('r7', first.z, first.x, first.y);
    expect(hit, isNotNull);
    final miss = await store.cachedTile('r7', 18, 1, 1);
    expect(miss, isNull);
  });

  test('init reconciles an already-downloaded pack to ready', () async {
    final store = OfflineTilePackStore(
      tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
      fetcher: (url) async => fakeTile(),
    );
    await store.init(overrideDirectory: tmp);
    await store.downloadPack('r8', bbox, minZoom: 12, maxZoom: 12);

    // Fresh store over the same dir — cold start reflects the pack on disk.
    final store2 = OfflineTilePackStore(
      tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
      fetcher: (url) async => fakeTile(),
    );
    await store2.init(overrideDirectory: tmp);
    expect(store2.progressFor('r8').status, OfflinePackStatus.ready);
  });
}
