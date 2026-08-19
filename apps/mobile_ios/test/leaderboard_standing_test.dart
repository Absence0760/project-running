import 'package:flutter_test/flutter_test.dart';
import '../lib/leaderboard_standing.dart';

class _Row implements StandingEntry {
  @override
  final String? userId;
  @override
  final String? teamClubId;
  @override
  final num value;
  _Row({this.userId, this.teamClubId, required this.value});
}

_Row u(String id, num value) => _Row(userId: id, teamClubId: null, value: value);
_Row team(String? id, num value) => _Row(userId: null, teamClubId: id, value: value);

void main() {
  test('entryKey prefers the runner, falls back to the team, else null', () {
    expect(entryKey(u('runner', 1)), 'runner');
    expect(entryKey(team('club', 1)), 'club');
    expect(entryKey(team(null, 1)), null);
  });

  test('a viewer who is not on the board has no standing', () {
    expect(standingFor([u('a', 10), u('b', 5)], 'c'), null);
  });

  test('an empty board has no standing', () {
    expect(standingFor(<_Row>[], 'a'), null);
  });

  test('an unidentifiable viewer has no standing', () {
    expect(standingFor([u('a', 10)], null), null);
    expect(standingFor([u('a', 10)], ''), null);
  });

  test('a non-finite own value claims nothing rather than a rank', () {
    expect(standingFor([u('a', double.nan), u('b', 5)], 'a'), null);
  });

  test('a lone entrant leads with nobody either side', () {
    final s = standingFor([u('a', 10)], 'a');
    expect(s, isNotNull);
    expect(s!.rank, 1);
    expect(s.total, 1);
    expect(s.tiedWith, 0);
    expect(s.chasing, null);
    expect(s.chasedBy, null);
  });

  test('the leader is chased but chases nobody', () {
    final s = standingFor([u('a', 30), u('b', 20), u('c', 10)], 'a');
    expect(s, isNotNull);
    expect(s!.rank, 1);
    expect(s.total, 3);
    expect(s.chasing, null);
    expect(s.chasedBy?.entry.userId, 'b');
    expect(s.chasedBy?.delta, 10);
  });

  test('the last entrant chases but is chased by nobody', () {
    final s = standingFor([u('a', 30), u('b', 20), u('c', 10)], 'c');
    expect(s, isNotNull);
    expect(s!.rank, 3);
    expect(s.chasing?.entry.userId, 'b');
    expect(s.chasing?.delta, 10);
    expect(s.chasedBy, null);
  });

  test('a mid-board entrant reports both neighbours, nearest first', () {
    final s = standingFor([u('a', 100), u('b', 60), u('c', 50), u('d', 20)], 'c');
    expect(s, isNotNull);
    expect(s!.rank, 3);
    expect(s.chasing?.entry.userId, 'b');
    expect(s.chasing?.delta, 10);
    expect(s.chasedBy?.entry.userId, 'd');
    expect(s.chasedBy?.delta, 30);
  });

  test('rank is competition rank — a tie shares it and pushes the next entrant down', () {
    final s = standingFor([u('a', 50), u('b', 50), u('c', 10)], 'b');
    expect(s, isNotNull);
    expect(s!.rank, 1);
    expect(s.tiedWith, 1);
    expect(standingFor([u('a', 50), u('b', 50), u('c', 10)], 'c')?.rank, 3);
  });

  test('a tied entrant is neither chased nor chasing — the neighbours skip past them', () {
    final rows = [u('a', 80), u('b', 50), u('c', 50), u('d', 20)];
    final s = standingFor(rows, 'b');
    expect(s, isNotNull);
    expect(s!.tiedWith, 1);
    expect(s.chasing?.entry.userId, 'a');
    expect(s.chasedBy?.entry.userId, 'd');
  });

  test('neighbours tie-break on key ascending, mirroring the SQL board order', () {
    final rows = [u('zeta', 90), u('alpha', 90), u('me', 50), u('yankee', 20), u('bravo', 20)];
    final s = standingFor(rows, 'me');
    expect(s, isNotNull);
    expect(s!.chasing?.entry.userId, 'alpha');
    expect(s.chasedBy?.entry.userId, 'bravo');
  });

  test('a keyless row sorts last inside its tie group, never first', () {
    final rows = [team(null, 90), team('club-z', 90), team('club-me', 50)];
    final s = standingFor(rows, 'club-me');
    expect(s, isNotNull);
    expect(s!.chasing?.entry.teamClubId, 'club-z');
  });

  test('a team board keys on the club', () {
    final s = standingFor([team('c1', 400), team('c2', 300), team(null, 100)], 'c2');
    expect(s, isNotNull);
    expect(s!.rank, 2);
    expect(s.chasing?.entry.teamClubId, 'c1');
    expect(s.chasing?.delta, 100);
    expect(s.chasedBy?.entry.teamClubId, null);
    expect(s.chasedBy?.delta, 200);
  });

  test('a non-finite rival is counted on the board but lands in neither neighbour slot', () {
    final s = standingFor([u('a', double.nan), u('b', 30), u('me', 20)], 'me');
    expect(s, isNotNull);
    expect(s!.total, 3);
    expect(s.rank, 2);
    expect(s.chasing?.entry.userId, 'b');
    expect(s.chasedBy, null);
  });

  test('a zero-valued board is all ties, not a ranking', () {
    final s = standingFor([u('a', 0), u('b', 0), u('c', 0)], 'a');
    expect(s, isNotNull);
    expect(s!.rank, 1);
    expect(s.tiedWith, 2);
    expect(s.chasing, null);
    expect(s.chasedBy, null);
  });
}
