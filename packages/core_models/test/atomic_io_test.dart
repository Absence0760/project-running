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
}
