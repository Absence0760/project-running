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
  // ─────────────── the contract the module exists for ───────────────

  test('a reader racing a stream of writes never sees a partial file',
      () async {
    // The whole point of the .tmp-then-rename dance. `File.writeAsString`
    // truncates the destination to zero bytes and then streams into it, so a
    // reader (or a cold start after a process death) can observe a prefix of
    // the new contents, or nothing at all, and `jsonDecode` rejects it — the
    // row silently disappears. `rename` swaps one inode for another, so the
    // path always resolves to a whole file.
    final file = File('${dir.path}/big.json');
    // Big enough that a non-atomic write would be observable mid-stream:
    // ~1.5 MB is many filesystem blocks, not one.
    List<Map<String, Object>> payload(int gen) => [
          for (var i = 0; i < 12000; i++) {'gen': gen, 'i': i, 'pad': 'x' * 100}
        ];
    await writeJsonAtomic(file, payload(0));

    var reads = 0;
    var stop = false;
    final reader = Future<void>(() async {
      while (!stop) {
        // A read is expected to yield a COMPLETE document every time. Any
        // decode failure, or a short list, is a torn read.
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        expect(decoded, hasLength(12000));
        reads++;
        await Future<void>.delayed(Duration.zero);
      }
    });

    for (var gen = 1; gen <= 12; gen++) {
      await writeJsonAtomic(file, payload(gen));
    }
    stop = true;
    await reader;
    // Without this the loop could have run zero times and proved nothing.
    expect(reads, greaterThan(0));
    expect(tmpFiles(), isEmpty);
  });

  test('a write that cannot be renamed cleans up after itself and rethrows',
      () async {
    // The failure branch. A temp sibling left behind by a failed write is the
    // same orphan a crash leaves: invisible to every store listing, holding a
    // full row on disk. A directory standing where the target file should be
    // makes `rename` fail without needing a filesystem fault.
    final blocked = Directory('${dir.path}/blocked.json')..createSync();
    await expectLater(
      writeStringAtomic(File(blocked.path), 'hello'),
      throwsA(isA<FileSystemException>()),
    );
    expect(tmpFiles(), isEmpty);
  });

  test('the temp file a real write creates is one the sweep would collect',
      () async {
    // The sweep matches on a `.tmp` suffix and the writer chooses the suffix.
    // They are edited in different functions, and if the writer's naming
    // moved, every crash orphan would become permanent while the sweep's own
    // tests — which hand-write the name — kept passing. The name is captured
    // from a real write here rather than transcribed.
    final file = File('${dir.path}/watched.json');
    final created = <String>[];
    final sub = dir.watch(events: FileSystemEvent.create).listen((e) {
      created.add(e.path.split('/').last);
    });
    // inotify delivery is asynchronous; give the watch a turn to arm.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await writeJsonAtomic(file, {'v': 1});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();

    final temps = created.where((n) => n != 'watched.json').toList();
    expect(temps, isNotEmpty,
        reason: 'no intermediate file was observed; the watch saw nothing and '
            'this case would pass over any naming');
    for (final name in temps) {
      expect(name, endsWith('.tmp'),
          reason: 'writeStringAtomic created $name, which '
              'sweepStoreScratchFiles does not match — a crash orphan under '
              'that name is never collected');
    }
  });

  group('sweepStoreScratchFiles', () {
    test('never deletes a store row, however its name is spelled', () {
      // The direction that loses data. Every store lists `.json` and the
      // sweep must be the exact complement of that: a widened match here
      // deletes the rows the store is made of.
      final rows = <File>[
        File('${dir.path}/plain.json'),
        // Contains the sweep's tokens but is not one: a run titled
        // "a.tmp" or "b.lock" produces exactly these names.
        File('${dir.path}/a.tmp.json'),
        File('${dir.path}/b.lock.json'),
        File('${dir.path}/synced_ids.json'),
      ];
      for (final f in rows) {
        f.writeAsStringSync('{}');
        f.setLastModifiedSync(
            DateTime.now().subtract(kAtomicOrphanMinAge * 10));
      }

      final errors = <String>[];
      sweepStoreScratchFiles(dir, onError: errors.add);

      for (final f in rows) {
        expect(f.existsSync(), isTrue,
            reason: '${f.path} was swept — the sweep is eating store rows');
      }
      expect(errors, isEmpty);
    });

    test('leaves a subdirectory alone even when its name ends in .tmp', () {
      // `listSync` yields directories too, and the sweep's own age gate does
      // not protect one that is old — the `is! File` guard is the only thing
      // that does. Both are aged past the cutoff so the guard is what this
      // measures: an empty directory deletes without complaint, so a sweep
      // that had lost the guard would silently remove them.
      final stale = DateTime.now().subtract(kAtomicOrphanMinAge * 10);
      final temp = Directory('${dir.path}/nested.tmp')..createSync();
      final lock = Directory('${dir.path}/nested.lock')..createSync();
      for (final d in [temp, lock]) {
        Process.runSync('touch', ['-d', stale.toIso8601String(), d.path]);
      }
      final errors = <String>[];
      sweepStoreScratchFiles(dir, onError: errors.add);
      expect(temp.existsSync(), isTrue);
      expect(lock.existsSync(), isTrue);
      expect(errors, isEmpty);
    });

    test('an undeletable temp file is reported and does not stop the sweep',
        () {
      // Best-effort: one unlink failing must not leave the rest of the
      // orphans on disk. A read-only directory makes the unlink fail
      // without needing a filesystem fault.
      final locked = Directory('${dir.path}/ro')..createSync();
      final trapped = File('${locked.path}/x.json.0.tmp')
        ..writeAsStringSync('{}');
      trapped.setLastModifiedSync(
          DateTime.now().subtract(kAtomicOrphanMinAge * 2));
      Process.runSync('chmod', ['a-w', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['u+w', locked.path]));

      final errors = <String>[];
      sweepStoreScratchFiles(locked, onError: errors.add);

      expect(trapped.existsSync(), isTrue);
      expect(errors, hasLength(1));
      expect(errors.single, contains('x.json.0.tmp'));
    });
  });
  // The suffix counter is a Dart static, so it is PER-ISOLATE, and these
  // stores are explicitly written for a second isolate over the same
  // directory (serialiseStoreWrite says its own serialisation stops at that
  // boundary; kAtomicOrphanMinAge exists because a genuinely concurrent
  // writer may own a temp file). Both isolates start at 0, so two concurrent
  // writes to one row picked the SAME `.0.tmp`, both truncated and streamed
  // into it, and whichever renamed second published an interleaved file over
  // the real one — the partial-file corruption the whole function exists to
  // prevent, arriving through the door it left open.
  group('the temp sibling is claimed, not merely named', () {
    int suffixOf(File tmp) {
      final parts = tmp.path.split('.');
      return int.parse(parts[parts.length - 2]);
    }

    test('claiming creates the file, so a second claim cannot pick it',
        () async {
      final file = File('${dir.path}/row.json');

      final a = await debugClaimAtomicTemp(file);
      final b = await debugClaimAtomicTemp(file);

      expect(a.existsSync(), isTrue,
          reason: 'a name nobody holds is not a claim');
      expect(b.existsSync(), isTrue);
      expect(a.path, isNot(b.path));
    });

    test('a temp path a concurrent writer holds is stepped over, not truncated',
        () async {
      final file = File('${dir.path}/row.json');
      file.writeAsStringSync('{"v":0}');

      // Consume one suffix, then free its path again: the counter has moved
      // on but the filesystem has not, which is exactly the state a second
      // isolate leaves — its own counter is at 0 while ours is not.
      final claimed = await debugClaimAtomicTemp(file);
      final next = suffixOf(claimed) + 1;
      if (claimed.existsSync()) claimed.deleteSync();

      // The other isolate's in-flight write, holding the very path this one's
      // counter is about to reach.
      final held = File('${file.path}.$next.tmp')
        ..writeAsStringSync('OTHER ISOLATE PAYLOAD');

      await writeStringAtomic(file, '{"v":1}');

      expect(file.readAsStringSync(), '{"v":1}');
      expect(held.existsSync(), isTrue,
          reason: 'the concurrent write must still own its temp file');
      expect(held.readAsStringSync(), 'OTHER ISOLATE PAYLOAD',
          reason: 'sharing the path is what interleaved the two writes');
    });

    test('a directory that cannot be written reports the filesystem error',
        () async {
      final missing = File('${dir.path}/no-such-dir/row.json');

      await expectLater(
        writeStringAtomic(missing, 'x'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

}
