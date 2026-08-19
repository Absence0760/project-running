// Dart mirror of apps/web/src/lib/social/challenge_list.test.ts. Case-for-case
// with the web suite bar one: the web twin's "unparseable start" case has no
// analogue here, because a typed `DateTime` cannot reach `myProgressView`
// unparsed. 17 tests here, 18 there.

import 'package:flutter_test/flutter_test.dart';

import '../lib/challenge_list.dart';

class _Row implements MyProgressRow {
  @override
  final String id;
  @override
  final num? myValue;
  @override
  final int? myRank;
  @override
  final DateTime? completedAt;
  const _Row(this.id, {this.myValue, this.myRank, this.completedAt});
}

final _jan2 = DateTime.utc(2026, 1, 2);
final _jan1 = DateTime.utc(2026, 1, 1);
final _jun6 = DateTime.utc(2026, 6, 6);

final _now = DateTime.utc(2026, 3, 10, 12);
const _club = '2c1cf5b0-0000-4000-8000-000000000001';

void main() {
  group('mergeMyProgress', () {
    test('folds the aggregate onto matching ids', () {
      final out = mergeMyProgress(
        [const _Row('a'), const _Row('b')],
        [_Row('b', myValue: 42, myRank: 3, completedAt: _jan2)],
      );
      expect(out[0].row.id, 'a');
      expect(out[0].myValue, isNull);
      expect(out[0].myRank, isNull);
      expect(out[0].completedAt, isNull);
      expect(out[1].myValue, 42);
      expect(out[1].myRank, 3);
      expect(out[1].completedAt, _jan2);
    });

    test('leaves uncovered rows null rather than zeroing them', () {
      final out = mergeMyProgress([const _Row('old')], const []);
      expect(out[0].myValue, isNull);
      expect(out[0].myRank, isNull);
    });

    test('preserves input order', () {
      final out = mergeMyProgress(
        [const _Row('c'), const _Row('a'), const _Row('b')],
        [
          const _Row('a', myValue: 1, myRank: 1),
          const _Row('b', myValue: 2, myRank: 2),
        ],
      );
      expect(out.map((r) => r.row.id).toList(), ['c', 'a', 'b']);
    });

    test('keeps a zero value from the aggregate', () {
      final out = mergeMyProgress(
        [const _Row('a')],
        [const _Row('a', myValue: 0, myRank: 5)],
      );
      expect(out[0].myValue, 0);
      expect(out[0].myRank, 5);
    });

    test('does not drop an existing value when the aggregate has none', () {
      final out = mergeMyProgress(
        [const _Row('a', myValue: 7, myRank: 2)],
        [const _Row('a')],
      );
      expect(out[0].myValue, 7);
      expect(out[0].myRank, 2);
    });

    test('prefers the row completedAt it already read', () {
      final out = mergeMyProgress(
        [_Row('a', completedAt: _jan1)],
        [_Row('a', myValue: 1, myRank: 1, completedAt: _jun6)],
      );
      expect(out[0].completedAt, _jan1);
    });

    test('does not mutate its inputs', () {
      final rows = [const _Row('a')];
      mergeMyProgress(rows, [const _Row('a', myValue: 9, myRank: 1)]);
      expect(rows[0].myValue, isNull);
    });
  });

  group('myProgressView', () {
    test('reports a served value as known', () {
      final v = myProgressView(
          myValue: 12345, startsAt: DateTime.utc(2026, 3, 1), now: _now);
      expect(v.state, MyProgressState.known);
      expect(v.value, 12345);
    });

    test('treats a served zero as known, not missing', () {
      final v = myProgressView(
          myValue: 0, startsAt: DateTime.utc(2026, 3, 1), now: _now);
      expect(v.state, MyProgressState.known);
      expect(v.value, 0);
    });

    test('calls an unopened window a true zero', () {
      final v = myProgressView(
          myValue: null, startsAt: DateTime.utc(2026, 4, 1), now: _now);
      expect(v.state, MyProgressState.notStarted);
      expect(v.value, 0);
    });

    test('will not claim zero for an open window with no value', () {
      expect(
        myProgressView(
                myValue: null, startsAt: DateTime.utc(2026, 1, 1), now: _now)
            .state,
        MyProgressState.unknown,
      );
    });

    test('treats the exact start instant as started', () {
      expect(
        myProgressView(myValue: null, startsAt: _now, now: _now).state,
        MyProgressState.unknown,
      );
    });

    test('a served value outranks a client clock that thinks the window is shut',
        () {
      // Client clock behind the server's: the aggregate only covers challenges
      // the SERVER considers started, so its value must win over the local
      // comparison.
      final v = myProgressView(
          myValue: 500, startsAt: DateTime.utc(2026, 4, 1), now: _now);
      expect(v.state, MyProgressState.known);
      expect(v.value, 500);
    });

    test('fails closed on a non-finite value', () {
      expect(
        myProgressView(
                myValue: double.nan,
                startsAt: DateTime.utc(2026, 1, 1),
                now: _now)
            .state,
        MyProgressState.unknown,
      );
      expect(
        myProgressView(
                myValue: double.infinity,
                startsAt: DateTime.utc(2026, 1, 1),
                now: _now)
            .state,
        MyProgressState.unknown,
      );
    });
  });

  group('teamLabel', () {
    test('resolves a readable club to its name', () {
      final l = teamLabel(_club, const {_club: 'Trail Pack'});
      expect(l.kind, TeamLabelKind.named);
      expect(l.name, 'Trail Pack');
    });

    test('never renders the raw club id for an unreadable club', () {
      expect(teamLabel(_club, const {}).kind, TeamLabelKind.unresolved);
      expect(teamLabel(_club, const {_club: '   '}).kind,
          TeamLabelKind.unresolved);
      expect(teamLabel(_club, const {'other': 'Trail Pack'}).kind,
          TeamLabelKind.unresolved);
      expect(teamLabel(_club, const {}).name, isNull);
    });

    test('reports the unaffiliated bucket separately from an unreadable club',
        () {
      expect(teamLabel(null, const {_club: 'Trail Pack'}).kind,
          TeamLabelKind.noClub);
      expect(teamLabel(null, const {}).kind, TeamLabelKind.noClub);
      expect(teamLabel('', const {}).kind, TeamLabelKind.noClub);
    });
  });
}
