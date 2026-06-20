import 'dart:math';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'event_category.dart';
import 'event_gym_template.dart';
import 'geocoding.dart';
import 'l10n/date_format.dart';
import 'l10n/gen/app_localizations.dart';
import 'l10n/locale_support.dart';
import 'l10n/number_format.dart';
import 'recurrence.dart';

// Column-level grant lockdown: `clubs.invite_token` is revoked from
// anon + authenticated (migration 20260801_001 + 20260818_001 redo).
// Selecting `*` (i.e. `.select()` with no args) raises 42501. Every
// read enumerates these safe columns; admin reads of `invite_token`
// go through the `get_club_invite_token` SECURITY DEFINER RPC. The
// arch-guard test scans for `from('clubs').select()` to keep this in
// lockstep.
const String _clubSelectCols =
    'id, owner_id, name, slug, description, avatar_url, location_label, '
    'is_public, is_verified, join_policy, member_count, '
    'website_url, instagram_url, strava_url, facebook_url, created_at, updated_at';

// Column-level grant lockdown: `events.meet_lat` / `meet_lng` are
// revoked from anon + authenticated (migrations 20260723_001 +
// 20260806_001 + 20260818_001 redo). Same `select('*')` constraint
// as clubs above; same arch-guard discipline.
//
// `host_user_id` (the paid-events payout recipient) is deliberately NOT
// selected — it stays revoked from authenticated/anon (20261228_001 /
// 20261230_001), so selecting it returns 42501 "permission denied for
// table events". Mirrors web's EVENT_SELECT_COLS, which omits it too.
const String _eventSelectCols =
    'id, club_id, title, description, starts_at, timezone, duration_min, '
    'meet_label, route_id, distance_m, pace_target_sec, capacity, '
    'author_id, created_at, updated_at, recurrence_freq, '
    'recurrence_byday, recurrence_until, recurrence_count, '
    'category, discipline, gym_template';

/// Parse the `events.recurrence_byday` jsonb array (a list of weekday
/// short-codes like `['MO','WE']`) into a list of `Weekday`s. Returns
/// null when the input isn't an array or when no code parses — the
/// EventRecurrence shape treats null and empty as "no day-of-week
/// override", which is the only behaviour callers care about.
///
/// Pulled out of `SocialService._parseByday` so it can be unit-tested
/// without booting Supabase.
List<Weekday>? parseBydayCodes(dynamic raw) {
  if (raw is! List) return null;
  final codes = raw.cast<String>();
  final ws = codes.map(weekdayFromCode).whereType<Weekday>().toList();
  return ws.isEmpty ? null : ws;
}

/// View-model for a club enriched with the current user's membership and the
/// live member count. Mirrors `ClubWithMeta` on web.
class ClubView {
  final ClubRow row;
  final int memberCount;
  final String? viewerRole; // 'owner' | 'admin' | 'member' | null
  final String? viewerStatus; // 'active' | 'pending' | null
  final String joinPolicy; // 'open' | 'request' | 'invite'

  const ClubView({
    required this.row,
    required this.memberCount,
    required this.viewerRole,
    required this.viewerStatus,
    required this.joinPolicy,
  });

  bool get isAdmin => viewerRole == 'owner' || viewerRole == 'admin';
  bool get isEventOrganiser =>
      isAdmin || viewerRole == 'event_organiser';
  bool get isRaceDirector =>
      isAdmin || viewerRole == 'race_director';
  bool get isMember => viewerRole != null;
}

class EventView {
  final EventRow row;
  final List<Weekday>? byday;
  final int attendeeCount;
  final String? viewerRsvp; // 'going' | 'maybe' | 'declined' | null
  final DateTime nextInstanceStart;

  const EventView({
    required this.row,
    required this.byday,
    required this.attendeeCount,
    required this.viewerRsvp,
    required this.nextInstanceStart,
  });

  RecurrenceFreq? get freq => recurrenceFromString(row.recurrenceFreq);

  EventRecurrence toRecurrence() => EventRecurrence(
        startsAt: row.startsAt,
        freq: freq,
        byday: byday,
        until: row.recurrenceUntil,
        count: row.recurrenceCount,
        timezone: row.timezone,
      );
}

class ClubPostView {
  final ClubPostRow row;
  final String? authorName;
  final int replyCount;

  const ClubPostView({
    required this.row,
    required this.authorName,
    required this.replyCount,
  });
}

class AttendeeView {
  final String userId;
  final String status;
  final String? displayName;
  // 'attended' | 'no_show' | null. Orthogonal to RSVP status; host-written
  // via mark_attendance (instructor_business.md M6).
  final String? attendance;
  const AttendeeView({
    required this.userId,
    required this.status,
    this.displayName,
    this.attendance,
  });
}

/// A challenge plus the caller-relative meta the list + detail surfaces need.
/// `metric` / `scope` stay raw strings here (the narrow unions live in
/// challenge_progress.dart's enum + the DB CHECK); the UI maps them.
class ChallengeView {
  final String id;
  final String? creatorId;
  final String? clubId;
  final String title;
  final String? description;
  final String metric;
  final String scope;
  final num? goalValue;
  final String? activityType;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isPublic;
  final bool joined;
  final num? myValue;
  final int? myRank;
  final int participantCount;
  final DateTime? completedAt;

  const ChallengeView({
    required this.id,
    required this.creatorId,
    required this.clubId,
    required this.title,
    required this.description,
    required this.metric,
    required this.scope,
    required this.goalValue,
    required this.activityType,
    required this.startsAt,
    required this.endsAt,
    required this.isPublic,
    this.joined = false,
    this.myValue,
    this.myRank,
    this.participantCount = 0,
    this.completedAt,
  });
}

/// One row from the `challenge_leaderboard` RPC (not a table, so hand-modelled).
class ChallengeLeaderboardEntry {
  final String? userId;
  final String? displayName;
  final String? teamClubId;
  final num value;
  final int rank;
  const ChallengeLeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.teamClubId,
    required this.value,
    required this.rank,
  });
}

/// Minimal projection of a `runs` row used by the event-result picker.
/// Deliberately smaller than the full [Run] domain class — we don't need
/// the track or pace, just enough to identify the run in a list.
class RecentRunRow {
  final String id;
  final DateTime startedAt;
  final int durationS;
  final double distanceM;
  final String activityType;
  const RecentRunRow({
    required this.id,
    required this.startedAt,
    required this.durationS,
    required this.distanceM,
    required this.activityType,
  });
}

/// One row on the event leaderboard. `rank` is null for DNF/DNS and for
/// newly inserted finishers that the server-side rerank trigger hasn't
/// caught up on — UIs render null as an em-dash.
class EventResultView {
  // Null for bib-only finishers imported from a chip-timing CSV (persona
  // #43) — those carry [bib] + [finisherName] instead of an account.
  final String? userId;
  final String? bib;
  final String? finisherName;
  final String? displayName;
  final String? runId;
  final int durationS;
  final double distanceM;
  final int? rank;
  final String finisherStatus;
  final bool organiserApproved;
  final double? ageGradePct;
  final String? note;
  final DateTime createdAt;

  const EventResultView({
    required this.userId,
    this.bib,
    this.finisherName,
    required this.displayName,
    required this.runId,
    required this.durationS,
    required this.distanceM,
    required this.rank,
    required this.finisherStatus,
    required this.organiserApproved,
    required this.ageGradePct,
    required this.note,
    required this.createdAt,
  });
}

/// A charity fundraiser attached to a run or event (fundraising.md). Mobile is
/// read + web-handoff only: it reads the fundraiser row (RLS-gated to a public
/// anchor), the thermometer totals, and the public donation feed. Donation
/// checkout is a web handoff (the `/fundraisers/[id]` page), mirroring how paid-
/// event registration is web-checkout-only.
class FundraiserView {
  final String id;
  final String title;
  final String charityName;
  final String? charityUrl;
  final String? story;
  final int goalCents;
  final String currency;
  final String status;

  const FundraiserView({
    required this.id,
    required this.title,
    required this.charityName,
    required this.charityUrl,
    required this.story,
    required this.goalCents,
    required this.currency,
    required this.status,
  });

  bool get isClosed => status == 'closed';
}

/// Thermometer totals for a fundraiser — the `fundraiser_totals` RPC projection.
class FundraiserTotalsView {
  final int raisedCents;
  final int donorCount;
  final int goalCents;
  final String currency;

  const FundraiserTotalsView({
    required this.raisedCents,
    required this.donorCount,
    required this.goalCents,
    required this.currency,
  });
}

/// A public donation-feed entry — the `fundraiser_feed` RPC projection
/// (public-safe columns only; donor identity / Stripe ids never surface).
class DonationFeedEntry {
  final String? displayName;
  final String? message;
  final int amountCents;
  final String currency;
  final bool isAnonymous;
  final DateTime? paidAt;

  const DonationFeedEntry({
    required this.displayName,
    required this.message,
    required this.amountCents,
    required this.currency,
    required this.isAnonymous,
    required this.paidAt,
  });
}

/// All Supabase calls for the social layer. Instances are notifier-backed so
/// the screens can subscribe to refresh events (joined a club, posted an
/// update, RSVP'd) without threading callbacks. One instance per app.
class SocialService extends ChangeNotifier {
  final SupabaseClient? _override;

  SocialService() : _override = null;

  /// Test-only DI seam. Production callsites use the unnamed constructor
  /// and resolve through the global. Mirrors `ApiClient.withClient` so
  /// wire-level methods can be driven against a real local Supabase
  /// without booting `Supabase.initialize` in the test isolate.
  @visibleForTesting
  SocialService.withClient(SupabaseClient client) : _override = client;

  SupabaseClient get _c {
    final override = _override;
    if (override != null) return override;
    if (!ApiClient.isInitialized) {
      throw StateError(
        'SocialService called before Supabase.initialize() resolved.',
      );
    }
    return Supabase.instance.client;
  }

  /// True iff [_c] would succeed — i.e. the override is set or
  /// `Supabase.initialize()` has resolved. Callers can probe this
  /// BEFORE invoking a Supabase-backed method so the UI surfaces
  /// a friendly "you need to be online + signed in to do this"
  /// message instead of letting the raw StateError bubble up
  /// (which was the user-reported `Bad state: SocialService called
  /// before Supabase.initialize() resolved.` crash on the New Club
  /// page).
  bool get isReady {
    if (_override != null) return true;
    return ApiClient.isInitialized;
  }

  String? get _uid => _c.auth.currentUser?.id;

  /// Public mirror of [_uid] for screens that need the viewer id but
  /// shouldn't be reaching into `Supabase.instance.client.auth` directly.
  String? get currentUserId => _uid;

  // ── Fundraisers (fundraising.md) — read + web-handoff only on mobile ──────
  // The fundraisers SELECT policy returns the row only when its anchor (run or
  // event) is publicly visible (or the caller owns it). The thermometer + feed
  // come from the visibility-gated `fundraiser_totals` / `fundraiser_feed`
  // SECURITY DEFINER RPCs, which project public-safe columns only. There is no
  // create/donate path here — authoring + checkout are web-canonical.

  FundraiserView? _fundraiserFromRow(Map<String, dynamic> row) {
    return FundraiserView(
      id: row['id'] as String,
      title: row['title'] as String,
      charityName: row['charity_name'] as String,
      charityUrl: row['charity_url'] as String?,
      story: row['story'] as String?,
      goalCents: (row['goal_cents'] as num).toInt(),
      currency: (row['currency'] as String?) ?? 'usd',
      status: (row['status'] as String?) ?? 'open',
    );
  }

  Future<FundraiserView?> fetchFundraiserForRun(String runId) async {
    final row = await _c
        .from('fundraisers')
        .select(
          'id, title, charity_name, charity_url, story, goal_cents, currency, status',
        )
        .eq('run_id', runId)
        .maybeSingle();
    if (row == null) return null;
    return _fundraiserFromRow(Map<String, dynamic>.from(row));
  }

  Future<FundraiserView?> fetchFundraiserForEvent(String eventId) async {
    final row = await _c
        .from('fundraisers')
        .select(
          'id, title, charity_name, charity_url, story, goal_cents, currency, status',
        )
        .eq('event_id', eventId)
        .maybeSingle();
    if (row == null) return null;
    return _fundraiserFromRow(Map<String, dynamic>.from(row));
  }

  Future<FundraiserTotalsView?> fetchFundraiserTotals(
    String fundraiserId,
  ) async {
    final raw = await _c.rpc(
      'fundraiser_totals',
      params: {'p_fundraiser_id': fundraiserId},
    );
    if (raw is! List || raw.isEmpty) return null;
    final row = Map<String, dynamic>.from(raw.first as Map);
    return FundraiserTotalsView(
      raisedCents: (row['raised_cents'] as num?)?.toInt() ?? 0,
      donorCount: (row['donor_count'] as num?)?.toInt() ?? 0,
      goalCents: (row['goal_cents'] as num?)?.toInt() ?? 0,
      currency: (row['currency'] as String?) ?? 'usd',
    );
  }

  Future<List<DonationFeedEntry>> fetchFundraiserFeed(
    String fundraiserId, {
    int limit = 50,
  }) async {
    final raw = await _c.rpc(
      'fundraiser_feed',
      params: {'p_fundraiser_id': fundraiserId, 'p_limit': limit},
    );
    if (raw is! List) return const [];
    return raw.map((r) {
      final row = Map<String, dynamic>.from(r as Map);
      final paid = row['paid_at'] as String?;
      return DonationFeedEntry(
        displayName: row['display_name'] as String?,
        message: row['message'] as String?,
        amountCents: (row['amount_cents'] as num?)?.toInt() ?? 0,
        currency: (row['currency'] as String?) ?? 'usd',
        isAnonymous: (row['is_anonymous'] as bool?) ?? false,
        paidAt: paid != null ? DateTime.tryParse(paid) : null,
      );
    }).toList();
  }

  /// Public clubs matching an optional search term.
  Future<List<ClubView>> browseClubs({String? query}) async {
    var q = _c.from('clubs').select(_clubSelectCols).eq('is_public', true);
    if (query != null && query.trim().isNotEmpty) {
      final term = query.trim();
      q = q.or('name.ilike.%$term%,location_label.ilike.%$term%');
    }
    final rows = await q.order('created_at', ascending: false).limit(60);
    return _enrichClubs(rows);
  }

  /// Region-aware club search. Mirrors web's `searchClubs` in
  /// `apps/web/src/lib/data.ts`. Tries to geocode the query first
  /// (so "Virginia" → centroid + ~470 km radius → ST_DWithin against
  /// `clubs.location_point`) and forwards the bbox params to the
  /// `search_clubs` RPC. Falls back to [browseClubs] when the
  /// geocode-less RPC errors. Honours an empty query by short-
  /// circuiting through [browseClubs].
  ///
  /// [mapTilerKey] threads the key in from the screen so the service
  /// stays free of `flutter_dotenv` (mirrors the way `route_builder_screen`
  /// passes the key to `searchPlaces`). [geocoder] is a test seam — pass
  /// a stub to replay canned responses without hitting MapTiler.
  Future<List<ClubView>> searchClubs(
    String query, {
    required String mapTilerKey,
    Future<GeocodedPlace?> Function(String)? geocoder,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return browseClubs();
    final place = await (geocoder ?? (q) => geocodePlace(q, apiKey: mapTilerKey))(term);
    try {
      final params = <String, dynamic>{
        'p_query': term,
        'p_limit': 60,
      };
      if (place != null) {
        params['p_center_lng'] = place.lng;
        params['p_center_lat'] = place.lat;
        params['p_radius_m'] = place.radiusM;
      }
      final raw = await _c.rpc('search_clubs', params: params);
      final rows = ((raw ?? <dynamic>[]) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      return _enrichClubs(rows);
    } catch (e, s) {
      // Per the web fallback: if the RPC fails (e.g. it's not deployed
      // in a dev env, or the planner threw on a malformed bbox) we
      // degrade to plain ILIKE rather than surfacing a red error toast.
      debugPrint('SocialService.searchClubs RPC failed, falling back: $e\n$s');
      return browseClubs(query: term);
    }
  }

  /// Clubs the current user is a member of (any status).
  Future<List<ClubView>> fetchMyClubs() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _c
        .from('club_members')
        .select('club_id, role, status, clubs!inner($_clubSelectCols)')
        .eq('user_id', uid)
        .order('joined_at', ascending: false);
    final clubs = <Map<String, dynamic>>[];
    for (final row in rows as List) {
      final club = (row as Map<String, dynamic>)['clubs'];
      if (club is Map<String, dynamic>) clubs.add(club);
    }
    return _enrichClubs(clubs);
  }

  Future<ClubView?> fetchClubBySlug(String slug) async {
    try {
      final row =
          await _c.from('clubs').select(_clubSelectCols).eq('slug', slug).maybeSingle();
      if (row == null) {
        debugPrint('fetchClubBySlug: no row for slug=$slug');
        return null;
      }
      final enriched = await _enrichClubs([row]);
      if (enriched.isEmpty) {
        debugPrint('fetchClubBySlug: enrichment returned empty (slug=$slug)');
        return null;
      }
      return enriched.first;
    } catch (e, s) {
      debugPrint('fetchClubBySlug failed: $e\n$s');
      rethrow;
    }
  }

  Future<List<ClubView>> _enrichClubs(List<dynamic> rawRows) async {
    final rows = rawRows.cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const [];
    final clubs = rows.map(ClubRow.fromJson).toList();
    final ids = clubs.map((c) => c.id).toList();

    final countsFut = _c
        .from('club_members')
        .select('club_id')
        .inFilter('club_id', ids)
        .eq('status', 'active');
    final uid = _uid;
    final rolesFut = uid == null
        ? Future.value(<dynamic>[])
        : _c
            .from('club_members')
            .select('club_id, role, status')
            .inFilter('club_id', ids)
            .eq('user_id', uid);

    final results = await Future.wait([countsFut, rolesFut]);
    final counts = <String, int>{};
    for (final r in results[0]) {
      final id = (r as Map)['club_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final roles = <String, String>{};
    final statuses = <String, String>{};
    for (final r in results[1]) {
      final m = r as Map;
      final cid = m['club_id'] as String;
      final status = m['status'] as String? ?? 'active';
      statuses[cid] = status;
      if (status == 'active') roles[cid] = m['role'] as String;
    }

    return [
      for (var i = 0; i < clubs.length; i++)
        ClubView(
          row: clubs[i],
          memberCount: counts[clubs[i].id] ?? 0,
          viewerRole: roles[clubs[i].id],
          viewerStatus: statuses[clubs[i].id],
          joinPolicy: (rows[i]['join_policy'] as String?) ?? 'open',
        ),
    ];
  }

  /// Create a new club. The `enroll_club_owner` trigger auto-inserts
  /// the owner's `club_members` row, so we don't add it here.
  /// Create a club. Mirrors `apps/web/src/lib/data.ts:createClub`:
  ///   - trims `name` and normalises `description` / `locationLabel`
  ///     (trim → empty becomes null), so whitespace-only inputs don't
  ///     survive to the DB regardless of how the caller pre-processed
  ///     them.
  ///   - generates a 32-hex-char `invite_token` client-side when
  ///     `joinPolicy == 'invite'`. The column has no DB-side default,
  ///     so without this an invite-only club created on mobile has a
  ///     null token and can't be shared via a join link.
  ///   - retries up to 4 times on slug-uniqueness conflicts (23505),
  ///     suffixing the slug with 4 random alphanumeric chars on each
  ///     retry. Matches the web behaviour so two users creating
  ///     "Hackney Half" at the same moment don't have the second one
  ///     fail with a raw Postgres error.
  Future<ClubRow> createClub({
    required String name,
    required String slug,
    String? description,
    String? locationLabel,
    bool isPublic = true,
    String joinPolicy = 'open',
    String? websiteUrl,
    String? instagramUrl,
    String? stravaUrl,
    String? facebookUrl,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final inviteToken = joinPolicy == 'invite' ? genInviteToken() : null;
    for (var attempt = 0; attempt < 4; attempt++) {
      final candidate =
          attempt == 0 ? slug : '$slug-${_randomSlugSuffix()}';
      final body = buildCreateClubBody(
        ownerId: uid,
        name: name,
        slug: candidate,
        description: description,
        locationLabel: locationLabel,
        isPublic: isPublic,
        joinPolicy: joinPolicy,
        inviteToken: inviteToken,
        websiteUrl: websiteUrl,
        instagramUrl: instagramUrl,
        stravaUrl: stravaUrl,
        facebookUrl: facebookUrl,
      );
      try {
        final inserted = await _c
            .from('clubs')
            .insert(body)
            .select(_clubSelectCols)
            .single();
        notifyListeners();
        return ClubRow.fromJson(inserted);
      } on PostgrestException catch (e) {
        // 23505 is the slug-uniqueness conflict — retry with a
        // suffix. Anything else (including the create_club rate-limit
        // P0001 from migration 20260907_001) bubbles to the caller.
        if (e.code != '23505') rethrow;
      }
    }
    throw Exception(
      'Could not allocate a slug for "$name" after 4 attempts',
    );
  }

  /// Pure helper: build the `clubs.insert` body with web-parity
  /// normalisation. Lifted to a static so the row shape can be
  /// unit-tested without standing up a Supabase fixture.
  @visibleForTesting
  static Map<String, dynamic> buildCreateClubBody({
    required String ownerId,
    required String name,
    required String slug,
    String? description,
    String? locationLabel,
    required bool isPublic,
    required String joinPolicy,
    String? inviteToken,
    String? websiteUrl,
    String? instagramUrl,
    String? stravaUrl,
    String? facebookUrl,
  }) {
    String? trimToNull(String? s) {
      final t = s?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }
    return <String, dynamic>{
      'owner_id': ownerId,
      'name': name.trim(),
      'slug': slug,
      'description': trimToNull(description),
      'location_label': trimToNull(locationLabel),
      'is_public': isPublic,
      'join_policy': joinPolicy,
      'invite_token': inviteToken,
      'website_url': normaliseClubLink(websiteUrl),
      'instagram_url': normaliseClubLink(instagramUrl),
      'strava_url': normaliseClubLink(stravaUrl),
      'facebook_url': normaliseClubLink(facebookUrl),
    };
  }

  /// Trim a club link, returning null for empty / non-http(s) input so a
  /// `javascript:`/`data:` URL can't be stored (XSS). The DB CHECK is the
  /// authoritative backstop; this is the friendly client-side gate. Twin of
  /// web's `normaliseClubLink` in `data.ts`.
  static String? normaliseClubLink(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    return RegExp(r'^https?://', caseSensitive: false).hasMatch(v) ? v : null;
  }

  /// Update a club's editable fields (admin-gated by RLS). Links are
  /// normalised the same way as on create.
  Future<void> updateClub(
    String id, {
    String? name,
    String? description,
    String? locationLabel,
    bool? isPublic,
    String? websiteUrl,
    String? instagramUrl,
    String? stravaUrl,
    String? facebookUrl,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name.trim();
    if (description != null) {
      patch['description'] = description.trim().isEmpty ? null : description.trim();
    }
    if (locationLabel != null) {
      patch['location_label'] =
          locationLabel.trim().isEmpty ? null : locationLabel.trim();
    }
    if (isPublic != null) patch['is_public'] = isPublic;
    if (websiteUrl != null) patch['website_url'] = normaliseClubLink(websiteUrl);
    if (instagramUrl != null) patch['instagram_url'] = normaliseClubLink(instagramUrl);
    if (stravaUrl != null) patch['strava_url'] = normaliseClubLink(stravaUrl);
    if (facebookUrl != null) patch['facebook_url'] = normaliseClubLink(facebookUrl);
    if (patch.isEmpty) return;
    await _c.from('clubs').update(patch).eq('id', id);
    notifyListeners();
  }

  /// Pure helper: generate a 32-hex-char invite token. Mirrors web's
  /// `genToken()` (16 random bytes → hex). Pass [rng] in tests for
  /// deterministic output; production always uses `Random.secure()`.
  @visibleForTesting
  static String genInviteToken({Random? rng}) {
    final r = rng ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _randomSlugSuffix() {
    // Matches the spirit of web's `Math.random().toString(36).slice(2, 6)`
    // — 4 chars from the base36 alphabet, lowercase. Collision odds at
    // this length are still under 1 in a million for the small number
    // of retries per request.
    final r = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(4, (_) => chars[r.nextInt(chars.length)])
        .join();
  }

  /// Pending join requests on a club (admins only — RLS will filter).
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async {
    final rows = await _c
        .from('club_members')
        .select()
        .eq('club_id', clubId)
        .eq('status', 'pending')
        .order('joined_at', ascending: false);
    return (rows as List)
        .map<ClubMemberRow>((r) =>
            ClubMemberRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Approve a pending join request.
  Future<void> approveJoinRequest({
    required String clubId,
    required String userId,
  }) async {
    await _c
        .from('club_members')
        .update({'status': 'active'})
        .eq('club_id', clubId)
        .eq('user_id', userId);
    notifyListeners();
  }

  /// Deny / remove a pending join request.
  Future<void> denyJoinRequest({
    required String clubId,
    required String userId,
  }) async {
    await _c
        .from('club_members')
        .delete()
        .eq('club_id', clubId)
        .eq('user_id', userId)
        .eq('status', 'pending');
    notifyListeners();
  }

  /// Routes owned by this club. Read-gated by RLS to club members.
  Future<List<Route>> fetchClubRoutes(String clubId) async {
    final rows = await _c
        .from('routes')
        .select()
        .eq('club_id', clubId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map<Route>((r) => _routeFromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Transfer a route the viewer owns to a club they admin (or detach
  /// it back to personal by passing `null`).
  Future<void> setRouteClub({
    required String routeId,
    required String? clubId,
  }) async {
    await _c.from('routes').update({'club_id': clubId}).eq('id', routeId);
    notifyListeners();
  }

  // Mirrors `ApiClient._routeFromRow` shape — kept here to avoid a
  // circular import. Update both if the row → domain mapping changes.
  Route _routeFromRow(Map<String, dynamic> row) {
    final r = RouteRow.fromJson(row);
    return Route(
      id: r.id,
      userId: r.userId,
      name: r.name,
      waypoints: r.waypoints
          .map((m) => Waypoint(
                lat: (m['lat'] as num).toDouble(),
                lng: (m['lng'] as num).toDouble(),
                elevationMetres: (m['ele'] as num?)?.toDouble(),
              ))
          .toList(),
      distanceMetres: r.distanceM,
      elevationGainMetres: r.elevationM ?? 0,
      isPublic: r.isPublic ?? false,
      surface: r.surface,
      createdAt: r.createdAt,
      tags: (row['tags'] as List?)?.cast<String>() ?? const [],
      featured: row['is_featured'] == true,
      runCount: (row['run_count'] as num?)?.toInt() ?? 0,
      clubId: r.clubId,
    );
  }

  Future<String> joinClub(String clubId, String policy) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final status = policy == 'request' ? 'pending' : 'active';
    await _c.from('club_members').insert({
      'club_id': clubId,
      'user_id': uid,
      'role': 'member',
      'status': status,
    });
    notifyListeners();
    return status;
  }

  /// Redeem a club invite token. Returns the slug of the club the
  /// user just joined so the caller can navigate to its detail
  /// screen. Mirrors web `joinClubByToken` (apps/web/src/lib/data.ts).
  /// Surfaces the RPC's own error messages on failure ("expired",
  /// "already a member", "invalid token") so the caller can render
  /// them as-is.
  Future<String> joinClubByToken(String token) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final result = await _c.rpc(
      'join_club_by_token',
      params: {'p_token': token.trim()},
    );
    notifyListeners();
    return result as String;
  }

  Future<void> leaveClub(String clubId) async {
    final uid = _uid;
    if (uid == null) return;
    await _c
        .from('club_members')
        .delete()
        .eq('club_id', clubId)
        .eq('user_id', uid);
    notifyListeners();
  }

  // ─────────────────────── Events ───────────────────────

  /// Create a new event under a club. Recurrence fields are raw
  /// strings — `recurrence.dart` produces them. Admin-write-gated by RLS.
  /// Create an event. Mirrors `apps/web/src/lib/data.ts:createEvent`:
  ///   - trims `title` and normalises `description` / `meetLabel`
  ///     (trim → empty becomes null) regardless of how the caller
  ///     pre-processed them.
  ///   - accepts `recurrenceByDay` as `List<String>?` (matches the
  ///     `events.recurrence_byday text[]` column type). The previous
  ///     mobile signature took a bare `String?` and sent it into a
  ///     `text[]` column — Postgrest doesn't auto-coerce, so the
  ///     recurrence rule was either rejected or silently dropped.
  ///   - accepts `recurrenceCount` (the "end after N occurrences"
  ///     half of the recurrence rule that mobile previously ignored).
  Future<EventRow> createEvent({
    required String clubId,
    required String title,
    required DateTime startsAt,
    String category = 'run',
    String? discipline,
    EventGymTemplate? gymTemplate,
    String? description,
    int? durationMin,
    String? meetLabel,
    double? meetLat,
    double? meetLng,
    String? routeId,
    double? distanceM,
    int? paceTargetSec,
    int? capacity,
    String? recurrenceFreq,
    List<String>? recurrenceByDay,
    DateTime? recurrenceUntil,
    int? recurrenceCount,
    bool isPublic = true,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final body = buildCreateEventBody(
      authorId: uid,
      clubId: clubId,
      title: title,
      startsAt: startsAt,
      category: category,
      discipline: discipline,
      gymTemplate: gymTemplate,
      description: description,
      durationMin: durationMin,
      meetLabel: meetLabel,
      meetLat: meetLat,
      meetLng: meetLng,
      routeId: routeId,
      distanceM: distanceM,
      paceTargetSec: paceTargetSec,
      capacity: capacity,
      recurrenceFreq: recurrenceFreq,
      recurrenceByDay: recurrenceByDay,
      recurrenceUntil: recurrenceUntil,
      recurrenceCount: recurrenceCount,
      isPublic: isPublic,
    );
    final inserted = await _c
        .from('events')
        .insert(body)
        .select(_eventSelectCols)
        .single();
    notifyListeners();
    return EventRow.fromJson(inserted);
  }

  /// Pure helper: build the `events.insert` body with web-parity
  /// normalisation. Lifted to a static so the row shape can be
  /// unit-tested without standing up a Supabase fixture.
  @visibleForTesting
  static Map<String, dynamic> buildCreateEventBody({
    required String authorId,
    required String clubId,
    required String title,
    required DateTime startsAt,
    String category = 'run',
    String? discipline,
    EventGymTemplate? gymTemplate,
    String? description,
    int? durationMin,
    String? meetLabel,
    double? meetLat,
    double? meetLng,
    String? routeId,
    double? distanceM,
    int? paceTargetSec,
    int? capacity,
    String? recurrenceFreq,
    List<String>? recurrenceByDay,
    DateTime? recurrenceUntil,
    int? recurrenceCount,
    bool isPublic = true,
  }) {
    String? trimToNull(String? s) {
      final t = s?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }
    final athletic = isAthleticEventCategory(category);
    final isClass = category == 'class';
    return <String, dynamic>{
      'club_id': clubId,
      'title': title.trim(),
      'category': category,
      'is_public': isPublic,
      'discipline': isClass ? trimToNull(discipline) : null,
      'gym_template': isClass && gymTemplate != null
          ? <String, dynamic>{
              'discipline': gymTemplate.discipline,
              'duration_min': gymTemplate.durationMin,
            }
          : null,
      'description': trimToNull(description),
      'starts_at': startsAt.toIso8601String(),
      'duration_min': durationMin,
      'meet_label': trimToNull(meetLabel),
      'meet_lat': meetLat,
      'meet_lng': meetLng,
      'route_id': athletic ? routeId : null,
      'distance_m': athletic ? distanceM : null,
      'pace_target_sec': athletic ? paceTargetSec : null,
      'capacity': capacity,
      'author_id': authorId,
      'recurrence_freq': recurrenceFreq,
      'recurrence_byday': recurrenceByDay,
      'recurrence_until': recurrenceUntil?.toIso8601String(),
      'recurrence_count': recurrenceCount,
    };
  }

  Future<List<EventView>> fetchUpcomingEvents(String clubId) async {
    final rows = await _c
        .from('events')
        .select(_eventSelectCols)
        .eq('club_id', clubId)
        .order('starts_at', ascending: true);
    final events = await _enrichEvents(rows as List);
    final now = DateTime.now();
    return events
        .where((e) => !e.nextInstanceStart.isBefore(now))
        .toList(growable: false)
      ..sort((a, b) => a.nextInstanceStart.compareTo(b.nextInstanceStart));
  }

  Future<EventView?> fetchEventById(String eventId) async {
    final row = await _c.from('events').select(_eventSelectCols).eq('id', eventId).maybeSingle();
    if (row == null) return null;
    final xs = await _enrichEvents([row]);
    return xs.isEmpty ? null : xs.first;
  }

  /// Event meetup coordinates, gated to active club members by the
  /// `get_event_meet_point` SECURITY DEFINER RPC. The `meet_lat` /
  /// `meet_lng` columns are revoked from every client role (precise
  /// meeting points leak organiser home addresses — migrations
  /// 20260723_001 / 20260806_001), so a direct column read can't reach
  /// them. Returns null for non-members and events with no point set.
  /// Persona-hunt social-group #10.
  Future<({double lat, double lng})?> fetchEventMeetPoint(String eventId) async {
    final res = await _c.rpc('get_event_meet_point', params: {'p_event_id': eventId});
    if (res is! List || res.isEmpty) return null;
    final row = res.first;
    if (row is! Map) return null;
    final lat = row['meet_lat'];
    final lng = row['meet_lng'];
    if (lat is! num || lng is! num) return null;
    return (lat: lat.toDouble(), lng: lng.toDouble());
  }

  /// Events that the current user is going to (status='going') in the next N
  /// hours. Used by the Run tab's "upcoming event" card. Returns the nearest.
  Future<EventView?> fetchNextRsvpedEvent({Duration window = const Duration(hours: 48)}) async {
    final uid = _uid;
    if (uid == null) return null;
    final now = DateTime.now();
    final end = now.add(window);
    final rsvps = await _c
        .from('event_attendees')
        .select('event_id, instance_start, status, events($_eventSelectCols)')
        .eq('user_id', uid)
        .eq('status', 'going')
        .gte('instance_start', now.toIso8601String())
        .lte('instance_start', end.toIso8601String())
        .order('instance_start', ascending: true)
        .limit(1);
    final rows = rsvps as List;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    final event = row['events'] as Map<String, dynamic>?;
    if (event == null) return null;
    final instanceIso = row['instance_start'] as String;
    final er = EventRow.fromJson(event);
    return EventView(
      row: er,
      byday: _parseByday(event['recurrence_byday']),
      attendeeCount: 0, // not needed for the card
      viewerRsvp: 'going',
      nextInstanceStart: DateTime.parse(instanceIso),
    );
  }

  Future<List<EventView>> _enrichEvents(List<dynamic> rawRows) async {
    if (rawRows.isEmpty) return const [];
    final rows = rawRows.cast<Map<String, dynamic>>();
    final ids = <String>[];
    final byRawId = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      ids.add(r['id'] as String);
      byRawId[r['id'] as String] = r;
    }
    final nexts = <String, DateTime>{};
    for (final r in rows) {
      final er = EventRow.fromJson(r);
      final byday = _parseByday(r['recurrence_byday']);
      final freq = recurrenceFromString(er.recurrenceFreq);
      final next = freq == null
          ? er.startsAt
          : (nextInstanceAfter(EventRecurrence(
                  startsAt: er.startsAt,
                  freq: freq,
                  byday: byday,
                  until: er.recurrenceUntil,
                  count: er.recurrenceCount,
                  timezone: er.timezone,
                )) ??
              er.startsAt);
      nexts[er.id] = next;
    }

    // Fetch going counts for each (event_id, instance_start) pair.
    final counts = <String, int>{};
    final uid = _uid;
    final myRsvps = <String, String>{};
    await Future.wait([
      Future.wait([
        for (final id in ids)
          _c
              .from('event_attendees')
              .select('event_id')
              .eq('event_id', id)
              .eq('status', 'going')
              .eq('instance_start', nexts[id]!.toIso8601String())
              .count()
              .then((res) => counts[id] = res.count),
      ]),
      if (uid != null)
        Future.wait([
          for (final id in ids)
            _c
                .from('event_attendees')
                .select('status')
                .eq('event_id', id)
                .eq('user_id', uid)
                .eq('instance_start', nexts[id]!.toIso8601String())
                .maybeSingle()
                .then((res) {
              final s = (res as Map?)?['status'];
              if (s is String) myRsvps[id] = s;
            }),
        ]),
    ]);

    return [
      for (final r in rows)
        EventView(
          row: EventRow.fromJson(r),
          byday: _parseByday(r['recurrence_byday']),
          attendeeCount: counts[r['id']] ?? 0,
          viewerRsvp: myRsvps[r['id']],
          nextInstanceStart: nexts[r['id']]!,
        ),
    ];
  }

  List<Weekday>? _parseByday(dynamic raw) => parseBydayCodes(raw);

  Future<void> rsvpEvent(String eventId, String status, DateTime instance) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _c.from('event_attendees').upsert(
      {
        'event_id': eventId,
        'user_id': uid,
        'status': status,
        'instance_start': instance.toIso8601String(),
      },
      onConflict: 'event_id,user_id,instance_start',
    );
    notifyListeners();
  }

  Future<void> clearRsvp(String eventId, DateTime instance) async {
    final uid = _uid;
    if (uid == null) return;
    await _c
        .from('event_attendees')
        .delete()
        .eq('event_id', eventId)
        .eq('user_id', uid)
        .eq('instance_start', instance.toIso8601String());
    notifyListeners();
  }

  /// Host-only: mark whether an attendee actually showed up. Routes through
  /// the organiser-only mark_attendance RPC; pass null to clear a prior mark.
  Future<void> markAttendance(String eventId, String userId, DateTime instance,
      String? attendance) async {
    await _c.rpc('mark_attendance', params: {
      'p_event_id': eventId,
      'p_user_id': userId,
      'p_instance_start': instance.toUtc().toIso8601String(),
      'p_attendance': attendance,
    });
    notifyListeners();
  }

  Future<List<AttendeeView>> fetchAttendees(String eventId, DateTime instance) async {
    final rows = await _c
        .from('event_attendees')
        .select()
        .eq('event_id', eventId)
        .eq('instance_start', instance.toIso8601String())
        .order('joined_at', ascending: true);
    final attendees = (rows as List).cast<Map<String, dynamic>>();
    if (attendees.isEmpty) return const [];
    final ids = attendees.map((r) => r['user_id'] as String).toList();
    final profiles = await _c
        .from('user_profiles')
        .select('id, display_name')
        .inFilter('id', ids);
    final byId = <String, String?>{};
    for (final p in profiles as List) {
      byId[(p as Map)['id'] as String] = p['display_name'] as String?;
    }
    return [
      for (final a in attendees)
        AttendeeView(
          userId: a['user_id'] as String,
          status: a['status'] as String,
          displayName: byId[a['user_id']],
          attendance: a['attendance'] as String?,
        ),
    ];
  }

  // ─────────────────────── Event results ───────────────────────

  /// Leaderboard for a single (event, instance). Results come back
  /// pre-ordered by the DB — finishers ascending by `rank`, then
  /// DNF/DNS rows last in insert order.
  Future<List<EventResultView>> fetchEventResults(
    String eventId,
    DateTime instance,
  ) async {
    // Read from `event_results_redacted` (migration 20260805_001), not
    // the base `event_results` table. The view nulls `run_id` for
    // non-owner rows so the public leaderboard can't bridge to a
    // participant's private run, and the explicit column projection
    // omits the admin-operational `organiser_approved_by` /
    // `organiser_approved_at` (only the boolean `organiser_approved`
    // is needed by the leaderboard UI). Mobile previously read the
    // base table with `select()`, leaking those fields to non-owner
    // viewers — the same data-leak the audit-pass-3 fix closed on
    // web's `fetchEventResults`. See apps/web/src/lib/data.ts.
    final rows = await _c
        .from('event_results_redacted')
        .select(
          'user_id, bib, finisher_name, run_id, duration_s, distance_m, '
          'rank, finisher_status, age_grade_pct, note, created_at, '
          'organiser_approved',
        )
        .eq('event_id', eventId)
        .eq('instance_start', instance.toIso8601String())
        .order('rank', ascending: true, nullsFirst: false)
        .order('created_at', ascending: true);
    final results = (rows as List).cast<Map<String, dynamic>>();
    if (results.isEmpty) return const [];
    // Bib-only imported finishers (persona #43) have no account; only
    // fetch profiles for the rows that carry a user_id.
    final ids = [
      for (final r in results)
        if (r['user_id'] != null) r['user_id'] as String,
    ];
    final byId = <String, String?>{};
    if (ids.isNotEmpty) {
      final profiles = await _c
          .from('user_profiles')
          .select('id, display_name')
          .inFilter('id', ids);
      for (final p in profiles as List) {
        byId[(p as Map)['id'] as String] = p['display_name'] as String?;
      }
    }
    return [
      for (final r in results)
        EventResultView(
          userId: r['user_id'] as String?,
          bib: r['bib'] as String?,
          finisherName: r['finisher_name'] as String?,
          // Account rows resolve through the profile map; bib-only rows
          // fall back to the name printed on the results sheet.
          displayName: r['user_id'] != null
              ? byId[r['user_id']]
              : r['finisher_name'] as String?,
          runId: r['run_id'] as String?,
          durationS: (r['duration_s'] as num).toInt(),
          distanceM: (r['distance_m'] as num).toDouble(),
          rank: r['rank'] as int?,
          finisherStatus: r['finisher_status'] as String,
          organiserApproved: r['organiser_approved'] as bool? ?? false,
          ageGradePct: (r['age_grade_pct'] as num?)?.toDouble(),
          note: r['note'] as String?,
          createdAt: DateTime.parse(r['created_at'] as String),
        ),
    ];
  }

  /// Submit or overwrite the current user's result for an event instance.
  /// Either [runId] + [durationS] + [distanceM] (attach an existing run)
  /// or [durationS] + [distanceM] alone (manual entry). Pass
  /// [finisherStatus] = `'dnf'` / `'dns'` to record a non-finish.
  ///
  /// Also stamps `runs.event_id` when [runId] is supplied so the run
  /// detail page can link back to the event.
  Future<void> submitEventResult({
    required String eventId,
    required DateTime instance,
    required int durationS,
    required double distanceM,
    String? runId,
    String finisherStatus = 'finished',
    double? ageGradePct,
    String? note,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final noteTrimmed = note?.trim();
    final normalisedNote =
        (noteTrimmed == null || noteTrimmed.isEmpty) ? null : noteTrimmed;
    await _c.from('event_results').upsert(
      {
        'event_id': eventId,
        'instance_start': instance.toIso8601String(),
        'user_id': uid,
        if (runId != null) 'run_id': runId,
        'duration_s': durationS,
        'distance_m': distanceM,
        'finisher_status': finisherStatus,
        if (ageGradePct != null) 'age_grade_pct': ageGradePct,
        // Trim + collapse empty-after-trim to null. Matches web's
        // submitEventResult and the trim-and-null contract used
        // across createClub / createEvent / saveRoute / etc.
        'note': normalisedNote,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'event_id,instance_start,user_id',
    );
    if (runId != null) {
      // Best-effort back-link. If the run isn't owned by this user
      // (shouldn't happen via this UI path, but RLS would block it
      // anyway) we swallow the error — the result row still exists.
      try {
        await _c
            .from('runs')
            .update({'event_id': eventId})
            .eq('id', runId)
            .eq('user_id', uid);
      } catch (e) {
        debugPrint('[SocialService.submitEventResult backlink] $e');
      }
    }
    notifyListeners();
  }

  /// Fetch the current race session for a specific event instance.
  /// Returns null when no session exists (the admin hasn't armed it
  /// yet). Read-only — mutation methods below write.
  Future<RaceSessionRow?> fetchRaceSession(
    String eventId,
    DateTime instance,
  ) async {
    try {
      final row = await _c
          .from(RaceSessionRow.table)
          .select()
          .eq(RaceSessionRow.colEventId, eventId)
          .eq(RaceSessionRow.colInstanceStart, instance.toIso8601String())
          .maybeSingle();
      if (row == null) return null;
      return RaceSessionRow.fromJson(row);
    } catch (e) {
      debugPrint('[SocialService.fetchRaceSession] $e');
      return null;
    }
  }

  /// Put the race session into the `armed` state. Upsert on the
  /// composite key, resetting `started_at` / `finished_at` so a rearm
  /// after a finished race starts from a clean slate (common pattern
  /// when testing a recurring event). [isAutoApprove] flows into the
  /// `is_auto_approve` column and the participant-submit pipeline reads
  /// it to decide whether to flip new results to `approved` on insert.
  ///
  /// Mirrors `apps/web/src/lib/data.ts:armRace`. Keep the two in sync
  /// — the rest of the stack expects both clients to write identical
  /// rows.
  Future<RaceSessionRow> armRace({
    required String eventId,
    required DateTime instance,
    bool isAutoApprove = true,
  }) async {
    if (_uid == null) throw Exception('Not authenticated');
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await _c
        .from(RaceSessionRow.table)
        .upsert(
          {
            RaceSessionRow.colEventId: eventId,
            RaceSessionRow.colInstanceStart: instance.toIso8601String(),
            RaceSessionRow.colStatus: 'armed',
            RaceSessionRow.colStartedAt: null,
            RaceSessionRow.colStartedBy: null,
            RaceSessionRow.colFinishedAt: null,
            RaceSessionRow.colIsAutoApprove: isAutoApprove,
            RaceSessionRow.colUpdatedAt: now,
          },
          onConflict:
              '${RaceSessionRow.colEventId},${RaceSessionRow.colInstanceStart}',
        )
        .select()
        .single();
    notifyListeners();
    return RaceSessionRow.fromJson(row);
  }

  /// Fire the starting gun — flips the session to `running` and stamps
  /// `started_at` + `started_by`. Requires a row already in `armed`
  /// state; returns the updated row. The spectator leaderboard and the
  /// participants' watches pick up the change via their race_sessions
  /// realtime subscriptions.
  Future<RaceSessionRow> startRace({
    required String eventId,
    required DateTime instance,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await _c
        .from(RaceSessionRow.table)
        .update({
          RaceSessionRow.colStatus: 'running',
          RaceSessionRow.colStartedAt: now,
          RaceSessionRow.colStartedBy: uid,
          RaceSessionRow.colUpdatedAt: now,
        })
        .eq(RaceSessionRow.colEventId, eventId)
        .eq(RaceSessionRow.colInstanceStart, instance.toIso8601String())
        .select()
        .single();
    notifyListeners();
    return RaceSessionRow.fromJson(row);
  }

  /// Flip the session to a terminal state — `finished` (happy path) or
  /// `cancelled` (stopped the race before it began or mid-run for
  /// weather / safety). In both cases the banner on participants'
  /// watches clears.
  Future<RaceSessionRow> endRace({
    required String eventId,
    required DateTime instance,
    String status = 'finished',
  }) async {
    if (_uid == null) throw Exception('Not authenticated');
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await _c
        .from(RaceSessionRow.table)
        .update({
          RaceSessionRow.colStatus: status,
          RaceSessionRow.colFinishedAt: now,
          RaceSessionRow.colUpdatedAt: now,
        })
        .eq(RaceSessionRow.colEventId, eventId)
        .eq(RaceSessionRow.colInstanceStart, instance.toIso8601String())
        .select()
        .single();
    notifyListeners();
    return RaceSessionRow.fromJson(row);
  }

  /// Recent runs for the current user, newest first. Used by the Submit
  /// Time flow to let users attach an existing run to an event. Kept on
  /// SocialService (rather than a per-screen fetcher) so the event
  /// detail screen doesn't need a direct [LocalRunStore] dependency.
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _c
        .from('runs')
        .select('id, started_at, duration_s, distance_m, activity_type')
        .eq('user_id', uid)
        .order('started_at', ascending: false)
        .limit(limit);
    return [
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        RecentRunRow(
          id: r['id'] as String,
          startedAt: DateTime.parse(r['started_at'] as String),
          durationS: (r['duration_s'] as num).toInt(),
          distanceM: (r['distance_m'] as num).toDouble(),
          activityType: (r['activity_type'] as String?) ?? 'run',
        ),
    ];
  }

  Future<void> removeEventResult(String eventId, DateTime instance) async {
    final uid = _uid;
    if (uid == null) return;
    await _c
        .from('event_results')
        .delete()
        .eq('event_id', eventId)
        .eq('instance_start', instance.toIso8601String())
        .eq('user_id', uid);
    notifyListeners();
  }

  // ─────────────────────── Club posts ───────────────────────

  Future<List<ClubPostView>> fetchClubPosts(String clubId, {int limit = 20}) async {
    final rows = await _c
        .from('club_posts')
        .select()
        .eq('club_id', clubId)
        .isFilter('parent_post_id', null)
        .order('created_at', ascending: false)
        .limit(limit);
    return _enrichPosts(rows as List);
  }

  /// Replies to [parentId], oldest-first. Capped at [limit] (default
  /// 200) to match `apps/web/src/lib/data.ts:fetchPostReplies` — a
  /// popular thread that accumulates thousands of replies otherwise
  /// pulls them all down on every open.
  Future<List<ClubPostView>> fetchPostReplies(
    String parentId, {
    int limit = 200,
  }) async {
    final rows = await _c
        .from('club_posts')
        .select()
        .eq('parent_post_id', parentId)
        .order('created_at', ascending: true)
        .limit(limit);
    return _enrichPosts(rows as List);
  }

  Future<List<ClubPostView>> _enrichPosts(List<dynamic> rawRows) async {
    if (rawRows.isEmpty) return const [];
    final rows = rawRows.cast<Map<String, dynamic>>();
    final posts = rows.map(ClubPostRow.fromJson).toList();
    final authorIds = posts.map((p) => p.authorId).toSet().toList();
    final topLevelIds = posts.where((p) => p.parentPostId == null).map((p) => p.id).toList();

    final futures = <Future<dynamic>>[
      _c
          .from('user_profiles')
          .select('id, display_name')
          .inFilter('id', authorIds),
    ];
    if (topLevelIds.isNotEmpty) {
      futures.add(_c
          .from('club_posts')
          .select('parent_post_id')
          .inFilter('parent_post_id', topLevelIds));
    }
    final results = await Future.wait(futures);
    final byId = <String, String?>{};
    for (final p in results[0] as List) {
      byId[(p as Map)['id'] as String] = p['display_name'] as String?;
    }
    final counts = <String, int>{};
    if (results.length > 1) {
      for (final r in results[1] as List) {
        final id = (r as Map)['parent_post_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }

    return [
      for (final p in posts)
        ClubPostView(
          row: p,
          authorName: byId[p.authorId],
          replyCount: counts[p.id] ?? 0,
        ),
    ];
  }

  Future<void> createPost({
    required String clubId,
    required String body,
    String? parentPostId,
    String? eventId,
    DateTime? eventInstanceStart,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _c.from('club_posts').insert({
      'club_id': clubId,
      'author_id': uid,
      'body': body.trim(),
      if (parentPostId != null) 'parent_post_id': parentPostId,
      if (eventId != null) 'event_id': eventId,
      if (eventInstanceStart != null)
        'event_instance_start': eventInstanceStart.toIso8601String(),
    });
    notifyListeners();
  }

  Future<void> deletePost(String postId) async {
    await _c.from('club_posts').delete().eq('id', postId);
    notifyListeners();
  }

  // ─────────────────────── Realtime ───────────────────────
  //
  // Screens pass a reload callback; the service wires the Supabase channel
  // and returns a `RealtimeChannel` the caller must `unsubscribe` from in
  // dispose. RLS is the authoritative filter — the payload is ignored and
  // the callback just triggers a fresh fetch so the caller gets enriched
  // `ClubView`/`EventView` objects, not raw rows.

  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) {
    return _c
        .channel('club-$clubId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'club_posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'club_id',
            value: clubId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'club_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'club_id',
            value: clubId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  RealtimeChannel subscribeToEvent(
    String eventId,
    String clubId,
    void Function() onChange,
  ) {
    return _c
        .channel('event-$eventId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'event_attendees',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: eventId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'club_posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'club_id',
            value: clubId,
          ),
          callback: (_) => onChange(),
        )
        // Race-session transitions (armed → running → finished). The
        // event detail screen refreshes the admin control panel +
        // status banner when a row flips; participants' watches pick
        // up the same change via `RaceController`'s own channel.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'race_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: eventId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _c.removeChannel(channel);
  }

  // ─────────────────────── Challenges & competitions ───────────────────────

  ChallengeView _challengeFromRow(Map<String, dynamic> r,
      {bool joined = false,
      num? myValue,
      int? myRank,
      int participantCount = 0,
      DateTime? completedAt}) {
    return ChallengeView(
      id: r['id'] as String,
      creatorId: r['creator_id'] as String?,
      clubId: r['club_id'] as String?,
      title: r['title'] as String,
      description: r['description'] as String?,
      metric: r['metric'] as String,
      scope: r['scope'] as String,
      goalValue: (r['goal_value'] as num?),
      activityType: r['activity_type'] as String?,
      startsAt: DateTime.parse(r['starts_at'] as String),
      endsAt: DateTime.parse(r['ends_at'] as String),
      isPublic: (r['is_public'] as bool?) ?? true,
      joined: joined,
      myValue: myValue,
      myRank: myRank,
      participantCount: participantCount,
      completedAt: completedAt,
    );
  }

  /// Challenges the caller can see (RLS scopes public + creator + participant +
  /// club member), enriched with participant counts + the joined flag.
  Future<List<ChallengeView>> fetchChallenges() async {
    final rows = await _c
        .from('challenges')
        .select()
        .order('ends_at', ascending: true) as List;
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => (r as Map)['id'] as String).toList();
    final parts = await _c
        .from('challenge_participants')
        .select('challenge_id, user_id')
        .inFilter('challenge_id', ids) as List;
    final counts = <String, int>{};
    final mine = <String>{};
    final uid = _uid;
    for (final p in parts) {
      final m = p as Map;
      final cid = m['challenge_id'] as String;
      counts[cid] = (counts[cid] ?? 0) + 1;
      if (uid != null && m['user_id'] == uid) mine.add(cid);
    }
    return rows
        .map((r) => _challengeFromRow(
              (r as Map).cast<String, dynamic>(),
              joined: mine.contains(r['id']),
              participantCount: counts[r['id']] ?? 0,
            ))
        .toList();
  }

  Future<ChallengeView?> fetchChallengeById(String id) async {
    final row = await _c.from('challenges').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    final parts = await _c
        .from('challenge_participants')
        .select('user_id, completed_at')
        .eq('challenge_id', id) as List;
    final uid = _uid;
    Map? mineRow;
    for (final p in parts) {
      if (uid != null && (p as Map)['user_id'] == uid) mineRow = p;
    }
    final completedRaw = mineRow?['completed_at'] as String?;
    return _challengeFromRow(
      row.cast<String, dynamic>(),
      joined: mineRow != null,
      participantCount: parts.length,
      completedAt: completedRaw == null ? null : DateTime.parse(completedRaw),
    );
  }

  Future<String> createChallenge({
    required String title,
    String? description,
    required String metric,
    required String scope,
    num? goalValue,
    String? activityType,
    String? clubId,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isPublic = true,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not authenticated');
    final row = await _c
        .from('challenges')
        .insert({
          'creator_id': uid,
          'title': title.trim(),
          'description': (description?.trim().isEmpty ?? true) ? null : description!.trim(),
          'metric': metric,
          'scope': scope,
          'goal_value': goalValue,
          'activity_type': activityType,
          'club_id': scope == 'club_vs_club' ? null : clubId,
          'starts_at': startsAt.toUtc().toIso8601String(),
          'ends_at': endsAt.toUtc().toIso8601String(),
          'is_public': isPublic,
        })
        .select('id')
        .single();
    notifyListeners();
    return row['id'] as String;
  }

  Future<void> deleteChallenge(String id) async {
    await _c.from('challenges').delete().eq('id', id);
    notifyListeners();
  }

  Future<void> joinChallenge(String id, {String? teamClubId}) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not authenticated');
    await _c.from('challenge_participants').insert({
      'challenge_id': id,
      'user_id': uid,
      'team_club_id': teamClubId,
    });
    notifyListeners();
  }

  Future<void> leaveChallenge(String id) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not authenticated');
    await _c
        .from('challenge_participants')
        .delete()
        .eq('challenge_id', id)
        .eq('user_id', uid);
    notifyListeners();
  }

  Future<List<ChallengeLeaderboardEntry>> fetchChallengeLeaderboard(
    String id, {
    bool byTeam = false,
  }) async {
    final raw = await _c.rpc('challenge_leaderboard', params: {
      'p_challenge_id': id,
      'p_by_team': byTeam,
    });
    return ((raw ?? <dynamic>[]) as List)
        .whereType<Map>()
        .map((r) => ChallengeLeaderboardEntry(
              userId: r['user_id'] as String?,
              displayName: r['display_name'] as String?,
              teamClubId: r['team_club_id'] as String?,
              value: (r['value'] as num?) ?? 0,
              rank: (r['rank'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  /// The self-hide driver: challenges the caller has joined that are live or
  /// recently ended. An empty list means render nothing.
  Future<List<ChallengeView>> myActiveChallenges() async {
    final raw = await _c.rpc('my_active_challenges');
    return ((raw ?? <dynamic>[]) as List).whereType<Map>().map((r) {
      final completedRaw = r['completed_at'] as String?;
      return _challengeFromRow(
        r.cast<String, dynamic>(),
        joined: true,
        myValue: r['my_value'] as num?,
        myRank: (r['my_rank'] as num?)?.toInt(),
        participantCount: (r['participant_count'] as num?)?.toInt() ?? 0,
        completedAt: completedRaw == null ? null : DateTime.parse(completedRaw),
      );
    }).toList();
  }

  /// Best-effort completion recompute after a run saves. Swallow-to-debug like
  /// other auxiliary effects — the daily cron sweep is the durable backstop.
  Future<void> recomputeChallengeCompletion(String id) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _c.rpc('recompute_challenge_completion', params: {
        'p_challenge_id': id,
        'p_user_id': uid,
      });
    } catch (e) {
      debugPrint('recomputeChallengeCompletion failed: $e');
    }
  }
}

/// Hash a user id to a hue 0-360 so avatars colour-diff consistently.
int hashHue(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h % 360;
}

/// Initial letter for an avatar bubble.
String initialFor(String? name) {
  final c = (name ?? '?').trim();
  return c.isEmpty ? '?' : c.substring(0, 1).toUpperCase();
}

/// Localized relative-time label for a feed/comment timestamp. The
/// canonical formatter — feed_screen + run_social_section delegate here
/// so every relative timestamp reads consistently and in the user's
/// language. [now] is a test seam; production uses `DateTime.now()`.
String fmtRelative(DateTime when, String localeTag, {DateTime? now}) {
  final l10n = lookupAppLocalizations(localeFromTag(localeTag) ?? defaultLocale);
  final diff = (now ?? DateTime.now()).difference(when);
  if (diff.inMinutes < 1) return l10n.relativeJustNow;
  if (diff.inMinutes < 60) return l10n.relativeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.relativeHoursAgo(diff.inHours);
  if (diff.inDays == 1) return l10n.relativeYesterday;
  if (diff.inDays < 7) return l10n.relativeDaysAgo(diff.inDays);
  final weeks = (diff.inDays / 7).floor();
  if (weeks < 5) return l10n.relativeWeeksAgo(weeks);
  return formatDateMed(when, localeTag);
}

String fmtEventDate(DateTime when, String localeTag) =>
    '${formatMonthDayShort(when, localeTag)}, ${formatTime(when, localeTag)}';

String fmtKm(num metres) =>
    formatFixed(metres / 1000, 2, activeLocaleTag);

String fmtPace(int? secPerKm) {
  if (secPerKm == null) return '';
  final m = secPerKm ~/ 60;
  final s = (secPerKm % 60).toString().padLeft(2, '0');
  return '$m:$s /km';
}
