import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'recurrence.dart';

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
  const AttendeeView({
    required this.userId,
    required this.status,
    this.displayName,
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
  final String userId;
  final String? displayName;
  final String? runId;
  final int durationS;
  final double distanceM;
  final int? rank;
  final String finisherStatus;
  final double? ageGradePct;
  final String? note;
  final DateTime createdAt;

  const EventResultView({
    required this.userId,
    required this.displayName,
    required this.runId,
    required this.durationS,
    required this.distanceM,
    required this.rank,
    required this.finisherStatus,
    required this.ageGradePct,
    required this.note,
    required this.createdAt,
  });
}

/// All Supabase calls for the social layer. Instances are notifier-backed so
/// the screens can subscribe to refresh events (joined a club, posted an
/// update, RSVP'd) without threading callbacks. One instance per app.
class SocialService extends ChangeNotifier {
  SupabaseClient get _c => Supabase.instance.client;

  String? get _uid => _c.auth.currentUser?.id;

  /// Public clubs matching an optional search term.
  Future<List<ClubView>> browseClubs({String? query}) async {
    var q = _c.from('clubs').select().eq('is_public', true);
    if (query != null && query.trim().isNotEmpty) {
      final term = query.trim();
      q = q.or('name.ilike.%$term%,location_label.ilike.%$term%');
    }
    final rows = await q.order('created_at', ascending: false).limit(60);
    return _enrichClubs(rows);
  }

  /// Clubs the current user is a member of (any status).
  Future<List<ClubView>> fetchMyClubs() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _c
        .from('club_members')
        .select('club_id, role, status, clubs!inner(*)')
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
          await _c.from('clubs').select().eq('slug', slug).maybeSingle();
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

  Future<List<EventView>> fetchUpcomingEvents(String clubId) async {
    final rows = await _c
        .from('events')
        .select()
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
    final row = await _c.from('events').select().eq('id', eventId).maybeSingle();
    if (row == null) return null;
    final xs = await _enrichEvents([row]);
    return xs.isEmpty ? null : xs.first;
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
        .select('event_id, instance_start, status, events(*)')
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

  List<Weekday>? _parseByday(dynamic raw) {
    if (raw is! List) return null;
    final codes = raw.cast<String>();
    final ws = codes.map(weekdayFromCode).whereType<Weekday>().toList();
    return ws.isEmpty ? null : ws;
  }

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
    final rows = await _c
        .from('event_results')
        .select()
        .eq('event_id', eventId)
        .eq('instance_start', instance.toIso8601String())
        .order('rank', ascending: true, nullsFirst: false)
        .order('created_at', ascending: true);
    final results = (rows as List).cast<Map<String, dynamic>>();
    if (results.isEmpty) return const [];
    final ids = results.map((r) => r['user_id'] as String).toList();
    final profiles = await _c
        .from('user_profiles')
        .select('id, display_name')
        .inFilter('id', ids);
    final byId = <String, String?>{};
    for (final p in profiles as List) {
      byId[(p as Map)['id'] as String] = p['display_name'] as String?;
    }
    return [
      for (final r in results)
        EventResultView(
          userId: r['user_id'] as String,
          displayName: byId[r['user_id']],
          runId: r['run_id'] as String?,
          durationS: (r['duration_s'] as num).toInt(),
          distanceM: (r['distance_m'] as num).toDouble(),
          rank: r['rank'] as int?,
          finisherStatus: r['finisher_status'] as String,
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
        if (note != null) 'note': note,
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
      } catch (_) {}
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
    } catch (_) {
      return null;
    }
  }

  /// Put the race session into the `armed` state. Upsert on the
  /// composite key, resetting `started_at` / `finished_at` so a rearm
  /// after a finished race starts from a clean slate (common pattern
  /// when testing a recurring event). [autoApprove] flows into the
  /// `auto_approve` column and the participant-submit pipeline reads
  /// it to decide whether to flip new results to `approved` on insert.
  ///
  /// Mirrors `apps/web/src/lib/data.ts:armRace`. Keep the two in sync
  /// — the rest of the stack expects both clients to write identical
  /// rows.
  Future<RaceSessionRow> armRace({
    required String eventId,
    required DateTime instance,
    bool autoApprove = true,
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
            RaceSessionRow.colAutoApprove: autoApprove,
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
        .select('id, started_at, duration_s, distance_m, metadata')
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
          activityType: (r['metadata'] is Map
                  ? (r['metadata'] as Map)['activity_type']
                  : null) as String? ??
              'run',
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

  Future<List<ClubPostView>> fetchPostReplies(String parentId) async {
    final rows = await _c
        .from('club_posts')
        .select()
        .eq('parent_post_id', parentId)
        .order('created_at', ascending: true);
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

String fmtRelative(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final weeks = (diff.inDays / 7).floor();
  if (weeks < 5) return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
  return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
}

String fmtEventDate(DateTime when) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final hh = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final mm = when.minute.toString().padLeft(2, '0');
  final ap = when.hour < 12 ? 'am' : 'pm';
  return '${months[when.month - 1]} ${when.day}, $hh:$mm $ap';
}

String fmtKm(num metres) => (metres / 1000).toStringAsFixed(2);

String fmtPace(int? secPerKm) {
  if (secPerKm == null) return '';
  final m = secPerKm ~/ 60;
  final s = (secPerKm % 60).toString().padLeft(2, '0');
  return '$m:$s /km';
}
