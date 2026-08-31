import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('atomic_io_test_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<String> tmpFiles() => dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.tmp'))
      .toList();

  test('writeStringAtomic round-trips the contents', () async {
    final file = File('${dir.path}/a.txt');
    await writeStringAtomic(file, 'hello world');
    expect(file.readAsStringSync(), 'hello world');
  });

  test('writeJsonAtomic encodes and round-trips via jsonDecode', () async {
    final file = File('${dir.path}/a.json');
    await writeJsonAtomic(file, {'k': 1, 'list': [1, 2, 3]});
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['k'], 1);
    expect(decoded['list'], [1, 2, 3]);
  });

  test('overwrites an existing file with the new contents', () async {
    final file = File('${dir.path}/a.json');
    await writeJsonAtomic(file, {'v': 'old'});
    await writeJsonAtomic(file, {'v': 'new'});
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['v'], 'new');
  });

  test('leaves no .tmp sibling after a successful write', () async {
    final file = File('${dir.path}/a.json');
    await writeJsonAtomic(file, {'v': 1});
    expect(tmpFiles(), isEmpty);
  });

  test('concurrent writes to the same target all complete without throwing',
      () async {
    final file = File('${dir.path}/a.json');
    // A shared temp path would make the second rename throw on a missing
    // source; the per-write unique suffix lets all of these resolve.
    await Future.wait([
      for (var i = 0; i < 8; i++) writeJsonAtomic(file, {'i': i}),
    ]);
    expect(tmpFiles(), isEmpty);
    // The surviving file is valid JSON written by one of the racers.
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['i'], inInclusiveRange(0, 7));
  });

  group('sweepStoreScratchFiles', () {
    test('deletes a stale temp sibling and spares a fresh one', () {
      // The orphan a crashed write leaves behind is invisible to every store
      // listing (they all filter on `.json`), so it is never pruned and holds
      // a full row — a GPS track, a route's waypoints — past sign-out.
      final stale = File('${dir.path}/a.json.0.tmp')..writeAsStringSync('{}');
      stale.setLastModifiedSync(
          DateTime.now().subtract(kAtomicOrphanMinAge * 2));
      final fresh = File('${dir.path}/b.json.1.tmp')..writeAsStringSync('{}');
      final keeper = File('${dir.path}/c.json')..writeAsStringSync('{}');

      sweepStoreScratchFiles(dir);

      expect(stale.existsSync(), isFalse);
      // The age gate is what keeps the sweep off a concurrent writer's
      // in-flight temp file — the background-sync isolate holds its own store
      // over the same directory.
      expect(fresh.existsSync(), isTrue);
      expect(keeper.existsSync(), isTrue);
    });

    test('drops a leftover .lock outright, with no age gate', () {
      // Residue of the per-sidecar FileLock the run and route stores held
      // until § 829 measured that a POSIX record lock, owned by the process,
      // excluded nothing in it. Nothing writes one any more, so an install
      // upgrading past that change must not keep them forever.
      final lock = File('${dir.path}/synced_ids.json.lock')
        ..writeAsStringSync('');
      final keeper = File('${dir.path}/synced_ids.json')
        ..writeAsStringSync('{}');

      sweepStoreScratchFiles(dir);

      expect(lock.existsSync(), isFalse);
      expect(keeper.existsSync(), isTrue);
    });

    test('a missing directory is reported, not thrown', () {
      final gone = Directory('${dir.path}/nope');
      final errors = <String>[];
      sweepStoreScratchFiles(gone, onError: errors.add);
      expect(errors, hasLength(1));
    });
  });
}
