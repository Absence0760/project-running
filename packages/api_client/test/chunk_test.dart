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
}
