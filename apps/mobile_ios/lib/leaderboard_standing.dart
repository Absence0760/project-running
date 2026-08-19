/// Where one entrant sits on a challenge leaderboard, relative to the entrants
/// immediately either side of them. Shared with the web twin
/// (apps/web/src/lib/social/leaderboard_standing.ts). Keep the two in lockstep:
/// algorithm, edge cases, outputs, and test counts must match.
///
/// The board itself only answers "who is where"; the competitive signal a
/// participant actually acts on is "how far off is the place above me, and how
/// much cushion do I have below" — and on a board of any size their own row may
/// be well off screen.
///
/// A pure re-shape of rows the caller already holds: no new query, no new data.
/// Every number stays in raw metric units and every neighbour is returned as
/// the ENTRY, not a label, so unit formatting and name/team resolution stay one
/// concern at the UI edge.
///
/// Pure functions, no Flutter / Supabase deps.
library;

/// The shape any board row must carry. `ChallengeLeaderboardEntry` implements
/// it; `rank` is deliberately NOT required — see [standingFor]. Dart has no
/// structural typing, so where the web twin's generic is bounded by an
/// implicitly-satisfied interface this one is bounded by a declared one.
abstract class StandingEntry {
  String? get userId;
  String? get teamClubId;
  num get value;
}

class Neighbour<T extends StandingEntry> {
  final T entry;

  /// Metric units separating this entry from the viewer. Always > 0.
  final num delta;
  const Neighbour(this.entry, this.delta);
}

class Standing<T extends StandingEntry> {
  final T entry;
  final int rank;

  /// Entrants on the board, including the viewer.
  final int total;

  /// How many OTHER entries share the viewer's exact value, and so their rank.
  final int tiedWith;

  /// Nearest entry ranked strictly above (a better value), and the units
  /// needed to draw level. Null when nobody is ahead.
  final Neighbour<T>? chasing;

  /// Nearest entry ranked strictly below, and the viewer's margin over it.
  /// Null when nobody is behind.
  final Neighbour<T>? chasedBy;

  const Standing({
    required this.entry,
    required this.rank,
    required this.total,
    required this.tiedWith,
    required this.chasing,
    required this.chasedBy,
  });
}

/// A team board keys on the club, an individual board on the runner. A row
/// carrying neither is the real unaffiliated bucket (`team_club_id` is nullable
/// and its FK is `on delete set null`), which no viewer can be matched to.
String? entryKey(StandingEntry entry) => entry.userId ?? entry.teamClubId;

/// The viewer's standing on [rows], or null when they aren't on the board (or
/// can't be identified, or their value isn't finite — fail closed to claiming
/// nothing rather than to a fabricated rank).
///
/// Rank is DERIVED as one plus the number of strictly better values rather than
/// read off the row, which is `rank() over (order by value desc)` by definition
/// — so it cannot disagree with the rank the SQL sent and the list renders, and
/// the helper stays usable on any board that hasn't been ranked server-side. A
/// non-finite value on another row fails every comparison, so it lands in
/// neither neighbour slot and never inflates the rank.
///
/// Neighbours tie-break on [entryKey] ascending, mirroring the SQL board's
/// `order by rank, <key> nulls last`, so the card names the same entrant across
/// two refreshes.
Standing<T>? standingFor<T extends StandingEntry>(List<T> rows, String? viewerKey) {
  if (viewerKey == null || viewerKey.isEmpty) return null;
  T? entry;
  for (final r in rows) {
    if (entryKey(r) == viewerKey) {
      entry = r;
      break;
    }
  }
  if (entry == null || !entry.value.isFinite) return null;

  final mine = entry.value;
  var rank = 1;
  var tiedWith = 0;
  Neighbour<T>? chasing;
  Neighbour<T>? chasedBy;

  for (final row in rows) {
    if (identical(row, entry)) continue;
    if (row.value > mine) {
      rank += 1;
      if (chasing == null ||
          row.value < chasing.entry.value ||
          _isPreferredTie(row, chasing.entry)) {
        chasing = Neighbour<T>(row, row.value - mine);
      }
    } else if (row.value < mine) {
      if (chasedBy == null ||
          row.value > chasedBy.entry.value ||
          _isPreferredTie(row, chasedBy.entry)) {
        chasedBy = Neighbour<T>(row, mine - row.value);
      }
    } else if (row.value == mine) {
      tiedWith += 1;
    }
  }

  return Standing<T>(
    entry: entry,
    rank: rank,
    total: rows.length,
    tiedWith: tiedWith,
    chasing: chasing,
    chasedBy: chasedBy,
  );
}

bool _isPreferredTie(StandingEntry candidate, StandingEntry incumbent) {
  if (candidate.value != incumbent.value) return false;
  final a = entryKey(candidate);
  final b = entryKey(incumbent);
  if (a == null) return false;
  if (b == null) return true;
  return a.compareTo(b) < 0;
}
