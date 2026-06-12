import 'package:flutter_test/flutter_test.dart';

import '../lib/routine_editor_build.dart';

({int? group, int? order}) _a(SupersetAssignment s) =>
    (group: s.supersetGroup, order: s.supersetOrder);

void main() {
  test('no flags → every exercise standalone', () {
    final out = assignSupersetGroups([false, false, false]).map(_a).toList();
    expect(out, [
      (group: null, order: null),
      (group: null, order: null),
      (group: null, order: null),
    ]);
  });

  test('single flag brackets a pair into one group, ordered 0 then 1', () {
    final out = assignSupersetGroups([true, false]).map(_a).toList();
    expect(out, [(group: 1, order: 0), (group: 1, order: 1)]);
  });

  test('a run of flags forms one longer group', () {
    final out = assignSupersetGroups([true, true, false]).map(_a).toList();
    expect(out, [
      (group: 1, order: 0),
      (group: 1, order: 1),
      (group: 1, order: 2),
    ]);
  });

  test('overlapping flags merge into one continuous group', () {
    final out =
        assignSupersetGroups([true, false, true, false]).map(_a).toList();
    expect(out, [
      (group: 1, order: 0),
      (group: 1, order: 1),
      (group: 1, order: 2),
      (group: 1, order: 3),
    ]);
  });

  test('two supersets split by a standalone exercise get distinct group ids',
      () {
    final out = assignSupersetGroups([true, false, false, false, true, false])
        .map(_a)
        .toList();
    expect(out, [
      (group: 1, order: 0),
      (group: 1, order: 1),
      (group: null, order: null),
      (group: null, order: null),
      (group: 2, order: 0),
      (group: 2, order: 1),
    ]);
  });

  test('a standalone exercise between two supersets stays ungrouped', () {
    final out = assignSupersetGroups([true, false, false, true, false])
        .map(_a)
        .toList();
    expect(out, [
      (group: 1, order: 0),
      (group: 1, order: 1),
      (group: null, order: null),
      (group: 2, order: 0),
      (group: 2, order: 1),
    ]);
  });

  test('a trailing flag is ignored (nothing follows to superset with)', () {
    final out = assignSupersetGroups([false, true]).map(_a).toList();
    expect(out, [(group: null, order: null), (group: null, order: null)]);
  });

  test('group + order are both-null or both-set (superset_chk invariant)', () {
    for (final a in assignSupersetGroups([true, false, false, true, true, false])) {
      expect(a.supersetGroup == null, a.supersetOrder == null);
    }
  });

  test('empty input yields no assignments', () {
    expect(assignSupersetGroups([]), isEmpty);
  });
}
