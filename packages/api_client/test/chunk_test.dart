import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

void main() {
  group('chunkList', () {
    test('splits into the requested size with a short final chunk', () {
      final ids = List.generate(250, (i) => 'id-$i');
      final chunks = chunkList(ids, kInFilterChunk);
      expect(chunks.length, 3);
      expect(chunks[0].length, 100);
      expect(chunks[1].length, 100);
      expect(chunks[2].length, 50);
      // No id lost or duplicated across the chunk boundaries.
      expect(chunks.expand((c) => c).toList(), ids);
    });

    test('default size is kInFilterChunk (100)', () {
      final ids = List.generate(201, (i) => i);
      final chunks = chunkList(ids);
      expect(chunks.length, 3);
      expect(chunks[2].length, 1);
    });

    test('empty input yields no chunks; a short list yields one chunk', () {
      expect(chunkList<String>([]), isEmpty);
      expect(chunkList(['a', 'b']), [
        ['a', 'b'],
      ]);
    });

    test('a list exactly one chunk long yields a single full chunk', () {
      final ids = List.generate(100, (i) => i);
      final chunks = chunkList(ids, 100);
      expect(chunks.length, 1);
      expect(chunks.single.length, 100);
    });

    test('throws on a non-positive size', () {
      expect(() => chunkList([1, 2], 0), throwsArgumentError);
      expect(() => chunkList([1, 2], -1), throwsArgumentError);
    });
  });

  group('readChunked', () {
    test('queries once per chunk and concatenates in chunk order', () async {
      final ids = List.generate(250, (i) => 'id-$i');
      final seen = <List<String>>[];
      final out = await readChunked(ids, (chunk) async {
        seen.add(chunk);
        return chunk.map((id) => 'row:$id').toList();
      });
      expect(seen.map((c) => c.length).toList(), [100, 100, 50]);
      expect(out, ids.map((id) => 'row:$id').toList());
    });

    test('an empty id list runs no query at all', () async {
      var calls = 0;
      final out = await readChunked<String>([], (chunk) async {
        calls++;
        return const [];
      });
      expect(calls, 0);
      expect(out, isEmpty);
    });
  });

  group('topByRecency', () {
    ({String id, DateTime at}) row(String id, String iso) =>
        (id: id, at: DateTime.parse(iso));

    test('dedupes by id, sorts recency desc then id desc, trims to limit', () {
      final merged = topByRecency(
        [
          row('b', '2026-01-02T00:00:00Z'),
          row('a', '2026-01-03T00:00:00Z'),
          row('b', '2026-01-02T00:00:00Z'),
          row('c', '2026-01-01T00:00:00Z'),
        ],
        limit: 2,
        idOf: (r) => r.id,
        recencyOf: (r) => r.at,
      );
      expect(merged.map((r) => r.id).toList(), ['a', 'b']);
    });

    test('ties on recency break by id descending', () {
      final merged = topByRecency(
        [
          row('a', '2026-01-01T00:00:00Z'),
          row('c', '2026-01-01T00:00:00Z'),
          row('b', '2026-01-01T00:00:00Z'),
        ],
        limit: 3,
        idOf: (r) => r.id,
        recencyOf: (r) => r.at,
      );
      expect(merged.map((r) => r.id).toList(), ['c', 'b', 'a']);
    });

    test('a non-positive limit yields nothing', () {
      expect(
        topByRecency([row('a', '2026-01-01T00:00:00Z')],
            limit: 0, idOf: (r) => r.id, recencyOf: (r) => r.at),
        isEmpty,
      );
    });
  });
}
