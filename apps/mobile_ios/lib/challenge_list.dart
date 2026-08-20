/// Pure shaping for the challenge surfaces: the "My challenges" list on the
/// Challenges screen and the leaderboard's team column. Shared with the web
/// twin (apps/web/src/lib/social/challenge_list.ts). Keep the two in lockstep:
/// algorithm, edge cases, outputs, and test counts must match.
///
/// The list's per-caller value is NOT carried by the `challenges` table read —
/// it only exists in the `challenge_leaderboard` aggregate, surfaced in bulk by
/// `my_active_challenges`. These helpers fold that aggregate onto the list and
/// decide what the row is allowed to claim, so a missing value renders as
/// missing rather than as a confident zero next to the goal.
///
/// Pure functions, no Flutter / Supabase deps.
library;

/// The caller-relative fields `my_active_challenges` can fill in. Dart has no
/// structural typing, so where the web twin's generic is bounded by an
/// implicitly-satisfied interface this one is bounded by a declared one —
/// `ChallengeView` implements it, exactly as `leaderboard_standing`'s
/// `StandingEntry` is implemented by `ChallengeLeaderboardEntry`.
abstract class MyProgressRow {
  String get id;
  num? get myValue;
  int? get myRank;
  DateTime? get completedAt;
}

/// One input row paired with the caller-relative values it should carry after
/// the fold. Dart has no object spread, so where the web twin returns rebuilt
/// rows this returns the row plus its resolved values and the caller applies
/// them — an idiomatic shape difference, not a divergence.
class MergedProgress<T extends MyProgressRow> {
  final T row;
  final num? myValue;
  final int? myRank;
  final DateTime? completedAt;
  const MergedProgress({
    required this.row,
    required this.myValue,
    required this.myRank,
    required this.completedAt,
  });
}

/// Fold the authoritative per-caller values from `my_active_challenges` onto a
/// joined-challenge list, matched by id. Rows the aggregate doesn't cover (it
/// only spans challenges live now or ended within 7 days) keep whatever they
/// already carried — never a fabricated zero. Input order is preserved so the
/// caller's `ends_at` ordering survives.
List<MergedProgress<T>> mergeMyProgress<T extends MyProgressRow>(
  List<T> rows,
  List<MyProgressRow> authoritative,
) {
  final byId = {for (final a in authoritative) a.id: a};
  return rows.map((r) {
    final a = byId[r.id];
    if (a == null) {
      return MergedProgress<T>(
        row: r,
        myValue: r.myValue,
        myRank: r.myRank,
        completedAt: r.completedAt,
      );
    }
    return MergedProgress<T>(
      row: r,
      myValue: a.myValue ?? r.myValue,
      myRank: a.myRank ?? r.myRank,
      completedAt: r.completedAt ?? a.completedAt,
    );
  }).toList();
}

/// What a list row may claim about the caller's progress. [notStarted] is a
/// *known* zero (the aggregate's window is `started_at >= starts_at`, so nothing
/// can have counted yet); [unknown] means the number simply isn't on this page.
enum MyProgressState { known, notStarted, unknown }

class MyProgressView {
  final MyProgressState state;

  /// The value to render. 0 for [MyProgressState.notStarted] (true) and for
  /// [MyProgressState.unknown] (unused — the caller must not render a bar in
  /// that state).
  final num value;
  const MyProgressView({required this.state, required this.value});
}

/// Decide what a "My challenges" row may show. A value from the server always
/// wins over the clock comparison, so a client clock running behind the server's
/// can't downgrade a real number to a presumed zero. A non-finite value falls
/// through to [MyProgressState.unknown] — fail closed to claiming nothing rather
/// than claiming zero. (The web twin also fails closed on an unparseable
/// `starts_at`; a typed `DateTime` cannot reach this side unparsed.)
MyProgressView myProgressView({
  required num? myValue,
  required DateTime startsAt,
  required DateTime now,
}) {
  if (myValue != null && myValue.isFinite) {
    return MyProgressView(state: MyProgressState.known, value: myValue);
  }
  if (now.isBefore(startsAt)) {
    return const MyProgressView(state: MyProgressState.notStarted, value: 0);
  }
  return const MyProgressView(state: MyProgressState.unknown, value: 0);
}

/// What a club-vs-club leaderboard row's team column may say. [noClub] is a
/// real bucket — `challenge_participants.team_club_id` is nullable and its FK is
/// `on delete set null`, so a deleted club leaves its people as an unaffiliated
/// group the SQL aggregate still sums. [unresolved] is a club RLS did not let
/// the viewer read.
enum TeamLabelKind { named, noClub, unresolved }

class TeamLabel {
  final TeamLabelKind kind;

  /// Non-null only for [TeamLabelKind.named].
  final String? name;
  const TeamLabel(this.kind, {this.name});
}

/// Resolve a team row's club id against the names the caller could read. A miss
/// is [TeamLabelKind.unresolved], never the raw id: a uuid is meaningless to a
/// reader and puts an internal identifier on screen. The CALLER localises the
/// two id-less kinds.
TeamLabel teamLabel(String? teamClubId, Map<String, String> clubNames) {
  if (teamClubId == null || teamClubId.isEmpty) {
    return const TeamLabel(TeamLabelKind.noClub);
  }
  final name = clubNames[teamClubId];
  if (name != null && name.trim().isNotEmpty) {
    return TeamLabel(TeamLabelKind.named, name: name);
  }
  return const TeamLabel(TeamLabelKind.unresolved);
}
