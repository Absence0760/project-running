import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// Parity tests for `ApiClient.comparePeopleRank` — Dart port of
/// `apps/web/src/lib/search_ranking.ts:comparePeopleRank`. Anti-spam
/// phase 1: a bot mass-creating empty accounts has zero public runs
/// and zero shared clubs. Ranking on those signals first surfaces
/// real users above bots even when a bot's display name is a closer
/// ILIKE match.
///
/// The comparator was previously web-only; mobile's `searchPeople`
/// returned candidates in whatever order PostgREST handed back, so
/// searching for a common first name surfaced bots-and-active-users
/// in arbitrary order. Mobile now applies the same comparator
/// post-fetch so search results match across platforms.
///
/// Pairs 1:1 with `apps/web/src/lib/search_ranking.test.ts`.
void main() {
  PeopleSuggestion p({
    String id = 'id',
    String? displayName,
    int publicRunsCount = 0,
    int sharedClubs = 0,
  }) =>
      PeopleSuggestion(
        id: id,
        displayName: displayName,
        avatarUrl: null,
        publicRunsCount: publicRunsCount,
        sharedClubs: sharedClubs,
        viewerFollows: false,
      );

  group('comparePeopleRank — primary key (public_runs_count)', () {
    test('account with more public runs sorts BEFORE one with fewer', () {
      final active = p(id: 'a', publicRunsCount: 50);
      final bot = p(id: 'b', publicRunsCount: 0);
      final sorted = [bot, active]..sort(ApiClient.comparePeopleRank);
      expect(sorted.first.id, 'a',
          reason: 'Active user must rank above zero-runs account.');
    });

    test('zero-runs accounts are NOT hidden — they just rank last', () {
      // Pin the "rank last, not removed" contract: a friend the
      // viewer searches for by exact name may have posted no runs yet.
      final friend = p(id: 'f', publicRunsCount: 0, displayName: 'Alice');
      final stranger = p(id: 's', publicRunsCount: 5, displayName: 'Bob');
      final sorted = [friend, stranger]..sort(ApiClient.comparePeopleRank);
      expect(sorted.length, 2);
      expect(sorted[0].id, 's',
          reason: '5-run stranger ranks above 0-run friend.');
      expect(sorted[1].id, 'f', reason: 'Friend still in the result set.');
    });
  });

  group('comparePeopleRank — secondary key (shared_clubs)', () {
    test('shared_clubs is the tie-breaker when public_runs is equal', () {
      final coMember = p(id: 'co', publicRunsCount: 5, sharedClubs: 3);
      final stranger = p(id: 'st', publicRunsCount: 5, sharedClubs: 0);
      final sorted = [stranger, coMember]..sort(ApiClient.comparePeopleRank);
      expect(sorted.first.id, 'co');
    });

    test('shared_clubs only breaks ties on public_runs — primary still wins',
        () {
      // Even if a stranger has more shared clubs, an account with
      // more public runs ranks higher. Public runs is the more
      // reliable activity signal.
      final talker = p(id: 't', publicRunsCount: 0, sharedClubs: 100);
      final runner = p(id: 'r', publicRunsCount: 50, sharedClubs: 0);
      final sorted = [talker, runner]..sort(ApiClient.comparePeopleRank);
      expect(sorted.first.id, 'r');
    });
  });

  group('comparePeopleRank — tertiary key (display_name alphabetical)', () {
    test('alphabetical break-tie when public_runs + shared_clubs both equal',
        () {
      final aBob = p(id: 'a', displayName: 'Bob', publicRunsCount: 5);
      final bAlice = p(id: 'b', displayName: 'Alice', publicRunsCount: 5);
      final sorted = [aBob, bAlice]..sort(ApiClient.comparePeopleRank);
      expect(sorted.first.displayName, 'Alice');
      expect(sorted.last.displayName, 'Bob');
    });

    test('null display_name compares as empty string (lands first)', () {
      final nullName =
          p(id: 'n', displayName: null, publicRunsCount: 5, sharedClubs: 0);
      final withName =
          p(id: 'w', displayName: 'Alice', publicRunsCount: 5, sharedClubs: 0);
      final sorted = [withName, nullName]..sort(ApiClient.comparePeopleRank);
      expect(sorted.first.id, 'n',
          reason: 'Empty string < "Alice" so null lands first. '
              'Matches web `(a.display_name ?? "").localeCompare(...)`.');
    });
  });

  group('comparePeopleRank — composite ordering on a realistic mix', () {
    test('end-to-end sort of a heterogeneous list', () {
      final pool = [
        p(id: 'bot-1', displayName: 'John', publicRunsCount: 0, sharedClubs: 0),
        p(
            id: 'bot-2',
            displayName: 'John Smith',
            publicRunsCount: 0,
            sharedClubs: 0),
        p(
            id: 'casual',
            displayName: 'John',
            publicRunsCount: 3,
            sharedClubs: 0),
        p(
            id: 'co-member',
            displayName: 'Johnny',
            publicRunsCount: 3,
            sharedClubs: 2),
        p(
            id: 'top',
            displayName: 'Johnathan',
            publicRunsCount: 50,
            sharedClubs: 0),
      ]..sort(ApiClient.comparePeopleRank);
      // Expected order:
      //   - top (50 runs)
      //   - co-member (3 runs, 2 clubs)
      //   - casual    (3 runs, 0 clubs)
      //   - bot-1     (0 runs, 0 clubs, "John")
      //   - bot-2     (0 runs, 0 clubs, "John Smith")
      expect(pool.map((p) => p.id), [
        'top',
        'co-member',
        'casual',
        'bot-1',
        'bot-2',
      ]);
    });
  });
}
