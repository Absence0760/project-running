import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Typed client for the Supabase REST API.
///
/// Must call [initialize] before using any methods.
class ApiClient {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Initialize Supabase. Call once at app startup.
  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  /// Sign in with email/password. Returns the user ID.
  Future<String> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.user!.id;
  }

  /// Register a new account with email/password. Returns the user ID.
  ///
  /// Throws if the address is already registered or the password is too weak.
  Future<String> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    return response.user!.id;
  }

  /// Exchange a Google ID token (obtained by the host app via the native
  /// Android `google_sign_in` flow) for a Supabase session. Returns the
  /// user ID.
  ///
  /// Host app is responsible for driving the Google Sign-In UI and
  /// capturing the ID token — this keeps `api_client` platform-agnostic.
  /// See `mobile_android/lib/screens/sign_in_screen.dart` for the caller
  /// and `apps/mobile_android/local_testing.md` for Google Cloud Console +
  /// Supabase dashboard setup instructions.
  Future<String> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) async {
    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    return response.user!.id;
  }

  /// The current user ID, or null if not signed in.
  String? get userId => _client.auth.currentUser?.id;

  /// The current user's email, or null if not signed in.
  String? get userEmail => _client.auth.currentUser?.email;

  /// Sign out the current user.
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Save a completed [Run] to the backend.
  ///
  /// The GPS track is uploaded as a gzipped JSON file to the `runs` Storage
  /// bucket at `{user_id}/{run_id}.json.gz` and a reference to it is stored
  /// in `runs.track_url`. The dashboard list never loads the track — it's
  /// fetched on demand by [fetchTrack] when a run detail page is opened.
  ///
  /// The upsert body is built from a generated [RunRow], so renaming a column
  /// in a migration forces `scripts/gen_dart_models.dart` to regenerate the
  /// row class — any stale field reference fails to compile here.
  Future<void> saveRun(Run run) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    String? trackUrl;
    final existingTrackUrl = run.metadata?['track_url'] as String?;
    if (run.track.isNotEmpty) {
      trackUrl = await _uploadTrack(userId: userId, runId: run.id, track: run.track);
    } else if (existingTrackUrl != null && existingTrackUrl.isNotEmpty) {
      trackUrl = existingTrackUrl;
    }

    // `startedAt` is captured as `DateTime.now()` — a local-tz DateTime.
    // `toIso8601String()` on a local DateTime emits a naive string with no
    // Z or offset, which PostgreSQL's `timestamptz` column interprets as
    // UTC — off by the user's offset and potentially a full calendar day.
    // Force UTC here so the stored instant is unambiguous.
    final row = RunRow(
      id: run.id,
      userId: userId,
      startedAt: run.startedAt.toUtc(),
      durationS: run.duration.inSeconds,
      distanceM: run.distanceMetres,
      source: run.source.name,
      externalId: run.externalId,
      metadata: run.metadata,
      trackUrl: trackUrl,
    );
    final json = row.toJson();
    if (run.externalId != null && run.externalId!.isNotEmpty) {
      await _client
          .from(RunRow.table)
          .upsert(json, onConflict: RunRow.colExternalId);
    } else {
      await _client.from(RunRow.table).upsert(json);
    }
  }

  /// Mark a run as publicly visible so it can be viewed at
  /// `/share/run/{id}` without authentication.
  Future<void> makeRunPublic(String runId) async {
    await _client
        .from(RunRow.table)
        .update({RunRow.colIsPublic: true})
        .eq(RunRow.colId, runId);
  }

  /// Batch-save a list of runs. Uploads tracks in parallel groups of
  /// [uploadConcurrency] and upserts rows in chunks of [rowChunkSize].
  ///
  /// [onProgress] is called after each row chunk is saved, with the number
  /// of runs saved so far.
  Future<void> saveRunsBatch(
    List<Run> runs, {
    int uploadConcurrency = 8,
    int rowChunkSize = 100,
    void Function(int saved)? onProgress,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    if (runs.isEmpty) return;

    // Upload tracks in parallel groups.
    final trackUrls = <String, String>{};
    final runsWithTracks = runs.where((r) => r.track.isNotEmpty).toList();
    for (var i = 0; i < runsWithTracks.length; i += uploadConcurrency) {
      final batch = runsWithTracks.skip(i).take(uploadConcurrency);
      final futures = batch.map((r) async {
        final url = await _uploadTrack(
            userId: userId, runId: r.id, track: r.track);
        trackUrls[r.id] = url;
      });
      await Future.wait(futures);
    }

    // Build rows and upsert in chunks.
    final rows = runs.map((r) {
      final trackUrl = trackUrls[r.id] ??
          (r.metadata?['track_url'] as String?) ??
          '';
      return RunRow(
        id: r.id,
        userId: userId,
        // Same UTC-normalisation as saveRun — see comment there.
        startedAt: r.startedAt.toUtc(),
        durationS: r.duration.inSeconds,
        distanceM: r.distanceMetres,
        source: r.source.name,
        externalId: r.externalId,
        metadata: r.metadata,
        trackUrl: trackUrl.isEmpty ? null : trackUrl,
      ).toJson();
    }).toList();

    int saved = 0;
    for (var i = 0; i < rows.length; i += rowChunkSize) {
      final chunk = rows.skip(i).take(rowChunkSize).toList();
      // Split each chunk by whether a row carries an external_id.
      // Rows with an external_id upsert on that column so re-imports
      // of Strava / Health Connect runs dedup correctly. Rows without
      // an external_id (app-recorded) upsert on the primary key `id`,
      // which is always set and is the correct dedup key for live runs.
      // Using a single onConflict spec for a mixed batch would apply
      // the external_id conflict clause to null-external_id rows,
      // bypassing the partial unique index and creating duplicates.
      final withExtId = chunk
          .where((r) =>
              (r[RunRow.colExternalId] as String?) != null &&
              (r[RunRow.colExternalId] as String).isNotEmpty)
          .toList();
      final withoutExtId = chunk
          .where((r) {
            final id = r[RunRow.colExternalId] as String?;
            return id == null || id.isEmpty;
          })
          .toList();
      if (withExtId.isNotEmpty) {
        await _client
            .from(RunRow.table)
            .upsert(withExtId, onConflict: RunRow.colExternalId);
      }
      if (withoutExtId.isNotEmpty) {
        await _client.from(RunRow.table).upsert(withoutExtId);
      }
      saved += chunk.length;
      onProgress?.call(saved);
    }
  }

  /// Delete a run from the backend, including its gzipped track file in
  /// Storage.
  Future<void> deleteRun(Run run) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final trackPath = run.metadata?['track_url'] as String?;
    if (trackPath != null && trackPath.isNotEmpty) {
      try {
        await _client.storage.from('runs').remove([trackPath]);
      } catch (e) {
        // Best-effort — the row delete is more important than the file cleanup.
      }
    }
    await _client.from(RunRow.table).delete().eq(RunRow.colId, run.id);
  }

  /// Fetch the user's runs, newest first.
  ///
  /// Returned runs have an empty `track`. Use [fetchTrack] to download the
  /// GPS waypoints for a single run when its detail page is opened.
  ///
  /// [before] paginates backwards — pass the `startedAt` of the oldest
  /// row from a previous page to get the next older batch.
  ///
  /// [updatedSince] enables delta fetches: only rows whose `last_modified_at`
  /// (in metadata) is newer than the supplied timestamp are returned. The
  /// caller stores its `lastFetchedAt` locally and passes it on subsequent
  /// opens so we don't re-fetch the entire history on every Runs tab
  /// visit.
  Future<List<Run>> getRuns({
    int limit = 50,
    DateTime? before,
    DateTime? updatedSince,
  }) async {
    var query = _client.from(RunRow.table).select();

    if (before != null) {
      query = query.lt(RunRow.colStartedAt, before.toIso8601String());
    }
    if (updatedSince != null) {
      // `last_modified_at` lives in metadata as an ISO-8601 string stamped
      // by LocalRunStore on every write. `->>` projects the JSON field as
      // text; Postgres lexicographic-compares ISO-8601 strings correctly.
      query = query.gt(
        "${RunRow.colMetadata}->>'last_modified_at'",
        updatedSince.toIso8601String(),
      );
    }

    final data = await query
        .order(RunRow.colStartedAt, ascending: false)
        .limit(limit);

    return data.map<Run>((row) => _runFromRow(row)).toList();
  }

  /// Download and decode the GPS track for a single run.
  ///
  /// Reads the gzipped JSON from Supabase Storage at the path stored in
  /// `metadata['track_url']` (returned by [getRuns] / [_runFromRow]).
  /// Returns an empty list if the run has no track.
  Future<List<Waypoint>> fetchTrack(Run run) async {
    final url = run.metadata?['track_url'] as String?;
    if (url == null || url.isEmpty) return const [];
    return _downloadTrack(url);
  }

  /// Download the raw gzipped track bytes from Storage without decoding.
  /// Used by the backup flow which wants to archive the gzipped blob
  /// verbatim so restore is a byte-for-byte upload.
  Future<Uint8List> downloadTrackBytes(String path) async {
    return _client.storage.from('runs').download(path);
  }

  /// Upload pre-gzipped track bytes to Storage at `{userId}/{runId}.json.gz`.
  /// Used on the restore path to re-home a track without re-encoding.
  Future<void> uploadTrackBytes({
    required String userId,
    required String runId,
    required Uint8List gzippedBytes,
  }) async {
    final path = '$userId/$runId.json.gz';
    await _client.storage.from('runs').uploadBinary(
          path,
          gzippedBytes,
          fileOptions: const FileOptions(
            contentType: 'application/json',
            upsert: true,
          ),
        );
  }

  /// Raw-row read of the `runs` table. Returns the underlying row
  /// `Map<String, dynamic>` rather than a `Run` domain object — the
  /// backup writer needs every column verbatim so round-trips preserve
  /// source-specific metadata, `event_id`, and anything else added to
  /// the schema later.
  Future<List<Map<String, dynamic>>> fetchRunRowsRaw() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final data = await _client
        .from(RunRow.table)
        .select()
        .eq(RunRow.colUserId, userId)
        .order(RunRow.colStartedAt, ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Upsert a raw run row. The backup restore path builds these
  /// directly from the archive so `metadata`, `source`, and every other
  /// column survive untouched.
  Future<void> upsertRunRowRaw(Map<String, dynamic> row) async {
    await _client.from(RunRow.table).upsert(row);
  }

  // -- Storage helpers --

  Future<String> _uploadTrack({
    required String userId,
    required String runId,
    required List<Waypoint> track,
  }) async {
    final json = jsonEncode(track.map(_waypointToJson).toList());
    final bytes = Uint8List.fromList(gzip.encode(utf8.encode(json)));
    final path = '$userId/$runId.json.gz';
    await _client.storage.from('runs').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/json',
            upsert: true,
          ),
        );
    return path;
  }

  Future<List<Waypoint>> _downloadTrack(String path) async {
    final bytes = await _client.storage.from('runs').download(path);
    final json = utf8.decode(gzip.decode(bytes));
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((t) => _waypointFromJson(t as Map<String, dynamic>)).toList();
  }

  static Map<String, dynamic> _waypointToJson(Waypoint w) => {
        'lat': w.lat,
        'lng': w.lng,
        'ele': w.elevationMetres,
        'ts': w.timestamp?.toUtc().toIso8601String(),
        if (w.bpm != null) 'bpm': w.bpm,
      };

  static Waypoint _waypointFromJson(Map<String, dynamic> m) => Waypoint(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        elevationMetres: (m['ele'] as num?)?.toDouble(),
        timestamp: m['ts'] != null ? DateTime.tryParse(m['ts'] as String) : null,
        bpm: (m['bpm'] as num?)?.toInt(),
      );

  /// Saves a [Route] to the backend.
  Future<void> saveRoute(Route route) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final row = RouteRow(
      id: route.id,
      userId: userId,
      name: route.name,
      waypoints: route.waypoints
          .map((w) => <String, dynamic>{
                'lat': w.lat,
                'lng': w.lng,
                'ele': w.elevationMetres,
              })
          .toList(),
      distanceM: route.distanceMetres,
      elevationM: route.elevationGainMetres,
      isPublic: route.isPublic,
      surface: route.surface,
      tags: route.tags,
      featured: route.featured,
      runCount: route.runCount,
    );
    // Drop null / server-default columns so Postgres fills them in.
    final body = Map<String, dynamic>.from(row.toJson())
      ..removeWhere((k, v) => v == null);
    body.remove(RouteRow.colId);
    await _client.from(RouteRow.table).insert(body);
  }

  /// Fetches the user's saved routes.
  Future<List<Route>> getRoutes() async {
    final data = await _client
        .from(RouteRow.table)
        .select()
        .order(RouteRow.colCreatedAt, ascending: false);

    return data.map<Route>((row) => _routeFromRow(row)).toList();
  }

  /// Search public routes. Supports full-text name search, distance range
  /// filtering, and surface type filtering. Uses the `routes_public` partial
  /// index and `routes_name_search` GIN index.
  Future<List<Route>> searchPublicRoutes({
    String? query,
    double? minDistanceM,
    double? maxDistanceM,
    String? surface,
    List<String>? tags,
    bool featuredOnly = false,
    String sort = 'newest',
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _client.rpc('search_public_routes', params: {
      'p_query': (query != null && query.trim().isNotEmpty) ? query.trim() : null,
      'p_min_distance_m': minDistanceM,
      'p_max_distance_m': maxDistanceM,
      'p_surface': (surface != null && surface.isNotEmpty) ? surface : null,
      'p_tags': (tags != null && tags.isNotEmpty) ? tags : null,
      'p_featured_only': featuredOnly,
      'p_sort': sort,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (data as List)
        .map<Route>((row) => _routeFromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// The N most-used tags across public routes, for filter-chip population.
  /// Calls the `popular_route_tags` RPC so aggregation happens in Postgres
  /// (one GIN-indexed scan, returns a few KB) instead of pulling up to
  /// 500 rows down the wire and counting in memory.
  Future<List<String>> fetchPopularRouteTags({int limit = 20}) async {
    final rows = await _client
        .rpc('popular_route_tags', params: {'tag_limit': limit});
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => r['tag'] as String)
        .toList();
  }

  Future<void> updateRouteTags(String routeId, List<String> tags) async {
    await _client.from(RouteRow.table).update({
      'tags': tags,
      RouteRow.colUpdatedAt: DateTime.now().toUtc().toIso8601String(),
    }).eq(RouteRow.colId, routeId);
  }

  /// Find public routes near a geographic point, sorted by distance.
  /// Uses the PostGIS-backed `nearby_routes` RPC.
  Future<List<Route>> nearbyPublicRoutes({
    required double lat,
    required double lng,
    double radiusM = 50000,
    int limit = 50,
  }) async {
    final data = await _client.rpc('nearby_routes', params: {
      'lat': lat,
      'lng': lng,
      'radius_m': radiusM,
      'max_results': limit,
    });
    return (data as List)
        .map<Route>((row) => _routeFromRow(row as Map<String, dynamic>))
        .toList();
  }

  // -- Route reviews --

  /// Fetch all reviews for a route, newest first.
  Future<List<RouteReviewRow>> getRouteReviews(String routeId) async {
    final data = await _client
        .from(RouteReviewRow.table)
        .select()
        .eq(RouteReviewRow.colRouteId, routeId)
        .order(RouteReviewRow.colCreatedAt, ascending: false);
    return data
        .map<RouteReviewRow>(
            (row) => RouteReviewRow.fromJson(row))
        .toList();
  }

  /// Submit or update a review for a route (one per user per route).
  Future<void> upsertRouteReview({
    required String routeId,
    required int rating,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await _client.from(RouteReviewRow.table).upsert({
      RouteReviewRow.colRouteId: routeId,
      RouteReviewRow.colUserId: userId,
      RouteReviewRow.colRating: rating,
      RouteReviewRow.colComment: comment,
    }, onConflict: '${RouteReviewRow.colRouteId},${RouteReviewRow.colUserId}');
  }

  /// Delete the current user's review of a route.
  Future<void> deleteRouteReview(String routeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from(RouteReviewRow.table)
        .delete()
        .eq(RouteReviewRow.colRouteId, routeId)
        .eq(RouteReviewRow.colUserId, userId);
  }

  /// Update a route's is_public flag.
  Future<void> setRoutePublic(String routeId, bool isPublic) async {
    await _client
        .from(RouteRow.table)
        .update({RouteRow.colIsPublic: isPublic})
        .eq(RouteRow.colId, routeId);
  }

  // ────────────────── Following + public profiles ──────────────────
  //
  // Mirror of `apps/web/src/lib/data.ts` — the social engagement loop
  // is web-canonical (decisions §31), and the android app needs the
  // same primitives to build feed / profile / notifications screens.
  // Methods are intentionally narrow wrappers over the row classes;
  // any cross-shape (FeedEntry, ProfileSummary) lives in core_models.

  /// Follow `targetUserId`. No-op if already following (composite-PK
  /// duplicate is swallowed by the unique-violation guard).
  Future<void> followUser(String targetUserId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    if (viewerId == targetUserId) return;
    await _client.from(UserFollowRow.table).insert({
      UserFollowRow.colFollowerId: viewerId,
      UserFollowRow.colFolloweeId: targetUserId,
    });
  }

  /// Stop following `targetUserId`.
  Future<void> unfollowUser(String targetUserId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(UserFollowRow.table)
        .delete()
        .eq(UserFollowRow.colFollowerId, viewerId)
        .eq(UserFollowRow.colFolloweeId, targetUserId);
  }

  /// People who follow `userId`. `limit` is a protective cap, not a
  /// pagination cursor — promote to cursor pagination if any user
  /// approaches the ceiling in practice.
  Future<List<UserProfileRow>> fetchFollowers(
    String userId, {
    int limit = 100,
  }) async {
    final edges = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFollowerId)
        .eq(UserFollowRow.colFolloweeId, userId)
        .order(UserFollowRow.colFollowedAt, ascending: false)
        .limit(limit);
    final ids = edges
        .map<String>((e) => e[UserFollowRow.colFollowerId] as String)
        .toList();
    if (ids.isEmpty) return const [];
    final profiles = await _client
        .from(UserProfileRow.table)
        .select()
        .inFilter(UserProfileRow.colId, ids);
    return profiles
        .map<UserProfileRow>((row) => UserProfileRow.fromJson(row))
        .toList();
  }

  /// People `userId` follows.
  Future<List<UserProfileRow>> fetchFollowing(
    String userId, {
    int limit = 100,
  }) async {
    final edges = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFolloweeId)
        .eq(UserFollowRow.colFollowerId, userId)
        .order(UserFollowRow.colFollowedAt, ascending: false)
        .limit(limit);
    final ids = edges
        .map<String>((e) => e[UserFollowRow.colFolloweeId] as String)
        .toList();
    if (ids.isEmpty) return const [];
    final profiles = await _client
        .from(UserProfileRow.table)
        .select()
        .inFilter(UserProfileRow.colId, ids);
    return profiles
        .map<UserProfileRow>((row) => UserProfileRow.fromJson(row))
        .toList();
  }

  /// Public profile lookup by user ID. Returns null when the row
  /// doesn't exist or RLS hides it.
  Future<UserProfileRow?> fetchPublicProfile(String userId) async {
    final row = await _client
        .from(UserProfileRow.table)
        .select()
        .eq(UserProfileRow.colId, userId)
        .maybeSingle();
    if (row == null) return null;
    return UserProfileRow.fromJson(row);
  }

  /// Follower / following counts via `count: 'exact', head: true`.
  /// Returned as a `(followers, following)` tuple to keep the call
  /// sites readable.
  Future<({int followers, int following})> fetchFollowCounts(
    String userId,
  ) async {
    final followers = await _client
        .from(UserFollowRow.table)
        .count(CountOption.exact)
        .eq(UserFollowRow.colFolloweeId, userId);
    final following = await _client
        .from(UserFollowRow.table)
        .count(CountOption.exact)
        .eq(UserFollowRow.colFollowerId, userId);
    return (followers: followers, following: following);
  }

  /// Whether the current viewer follows `userId`.
  Future<bool> viewerFollows(String userId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null || viewerId == userId) return false;
    final row = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFollowerId)
        .eq(UserFollowRow.colFollowerId, viewerId)
        .eq(UserFollowRow.colFolloweeId, userId)
        .maybeSingle();
    return row != null;
  }

  // ───────────────────── Kudos on runs ─────────────────────

  /// One-tap kudos on a run. Composite-PK enforcement makes this
  /// idempotent — a second tap is a no-op rather than a duplicate.
  Future<void> giveKudos(String runId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client.from(RunKudosRow.table).insert({
      RunKudosRow.colUserId: viewerId,
      RunKudosRow.colRunId: runId,
    });
  }

  /// Rescind kudos previously given on a run.
  Future<void> rescindKudos(String runId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(RunKudosRow.table)
        .delete()
        .eq(RunKudosRow.colUserId, viewerId)
        .eq(RunKudosRow.colRunId, runId);
  }

  /// Per-run engagement summary (kudos count, comment count, whether
  /// the viewer has given kudos). Mirrors the web `fetchEngagement
  /// Summaries` shape — used by feed cards and run-detail pages.
  Future<Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>>
      fetchEngagementSummaries(List<String> runIds) async {
    if (runIds.isEmpty) return const {};
    final viewerId = _client.auth.currentUser?.id;

    final kudos = await _client
        .from(RunKudosRow.table)
        .select('${RunKudosRow.colRunId}, ${RunKudosRow.colUserId}')
        .inFilter(RunKudosRow.colRunId, runIds);
    final comments = await _client
        .from(RunCommentRow.table)
        .select(RunCommentRow.colRunId)
        .inFilter(RunCommentRow.colRunId, runIds);

    final kudosCount = <String, int>{};
    final viewerHas = <String, bool>{};
    for (final row in kudos) {
      final rid = row[RunKudosRow.colRunId] as String;
      kudosCount[rid] = (kudosCount[rid] ?? 0) + 1;
      if (viewerId != null && row[RunKudosRow.colUserId] == viewerId) {
        viewerHas[rid] = true;
      }
    }
    final commentCount = <String, int>{};
    for (final row in comments) {
      final rid = row[RunCommentRow.colRunId] as String;
      commentCount[rid] = (commentCount[rid] ?? 0) + 1;
    }
    return {
      for (final id in runIds)
        id: (
          kudosCount: kudosCount[id] ?? 0,
          viewerHasKudos: viewerHas[id] ?? false,
          commentCount: commentCount[id] ?? 0,
        ),
    };
  }

  // ──────────────────── Comments on runs ────────────────────

  /// Comments on a run, sorted oldest-first. Capped at `limit` rows
  /// (default 200) — promote to cursor pagination if a viral run
  /// regularly hits the cap.
  Future<List<RunCommentRow>> fetchRunComments(
    String runId, {
    int limit = 200,
  }) async {
    final data = await _client
        .from(RunCommentRow.table)
        .select()
        .eq(RunCommentRow.colRunId, runId)
        .order(RunCommentRow.colCreatedAt, ascending: true)
        .limit(limit);
    return data
        .map<RunCommentRow>((row) => RunCommentRow.fromJson(row))
        .toList();
  }

  /// Post a comment on a run. `parentCommentId` is set for replies
  /// (one-level deep — the INSERT policy rejects deeper nesting via
  /// the `_run_comment_parent_is_top_level` helper).
  Future<RunCommentRow> addRunComment({
    required String runId,
    required String body,
    String? parentCommentId,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final inserted = await _client
        .from(RunCommentRow.table)
        .insert({
          RunCommentRow.colRunId: runId,
          RunCommentRow.colAuthorId: viewerId,
          RunCommentRow.colBody: body,
          if (parentCommentId != null)
            RunCommentRow.colParentCommentId: parentCommentId,
        })
        .select()
        .single();
    return RunCommentRow.fromJson(inserted);
  }

  /// Edit your own comment body. The `run_comments_set_updated_at`
  /// trigger keeps `updated_at` honest so consumers can tell edited
  /// comments apart.
  Future<void> editRunComment({
    required String commentId,
    required String body,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(RunCommentRow.table)
        .update({RunCommentRow.colBody: body})
        .eq(RunCommentRow.colId, commentId)
        .eq(RunCommentRow.colAuthorId, viewerId);
  }

  /// Delete a comment. The author can always delete their own; the
  /// run owner can delete any comment on their run (separate DELETE
  /// policy). RLS enforces the rest.
  Future<void> deleteRunComment(String commentId) async {
    await _client
        .from(RunCommentRow.table)
        .delete()
        .eq(RunCommentRow.colId, commentId);
  }

  // ──────────────────── Notifications inbox ────────────────────

  /// The viewer's notifications, newest-first. Capped at `limit`.
  Future<List<NotificationRow>> fetchNotifications({int limit = 100}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    final data = await _client
        .from(NotificationRow.table)
        .select()
        .eq(NotificationRow.colUserId, viewerId)
        .order(NotificationRow.colCreatedAt, ascending: false)
        .limit(limit);
    return data
        .map<NotificationRow>((row) => NotificationRow.fromJson(row))
        .toList();
  }

  /// Unread count for the bell badge. Hot read-path so we use
  /// `count: 'exact', head: true` against the partial index
  /// `notifications_user_unread`.
  Future<int> fetchUnreadNotificationCount() async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return 0;
    return _client
        .from(NotificationRow.table)
        .count(CountOption.exact)
        .eq(NotificationRow.colUserId, viewerId)
        .isFilter(NotificationRow.colReadAt, null);
  }

  /// Mark one notification read. Optimistic-write friendly — the
  /// bell decrements its badge before this fires.
  Future<void> markNotificationRead(String id) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(NotificationRow.table)
        .update({NotificationRow.colReadAt: DateTime.now().toIso8601String()})
        .eq(NotificationRow.colId, id)
        .eq(NotificationRow.colUserId, viewerId)
        .isFilter(NotificationRow.colReadAt, null);
  }

  /// Bulk mark-all-read for the viewer's unread inbox.
  Future<void> markAllNotificationsRead() async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(NotificationRow.table)
        .update({NotificationRow.colReadAt: DateTime.now().toIso8601String()})
        .eq(NotificationRow.colUserId, viewerId)
        .isFilter(NotificationRow.colReadAt, null);
  }

  /// Per-row dismiss.
  Future<void> deleteNotification(String id) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(NotificationRow.table)
        .delete()
        .eq(NotificationRow.colId, id)
        .eq(NotificationRow.colUserId, viewerId);
  }

  // -- Row mapping (generated RunRow/RouteRow → domain Run/Route) --
  //
  // These go through the generated row classes so that column renames surface
  // as compile errors on the consuming fields below, not as silent runtime
  // drift.

  static Run _runFromRow(Map<String, dynamic> row) {
    final r = RunRow.fromJson(row);
    // Stash the storage path on metadata so callers can pass the run back
    // to fetchTrack() to lazy-load the GPS waypoints. The track field itself
    // stays empty until fetched.
    final metadata = Map<String, dynamic>.from(r.metadata ?? const {});
    if (r.trackUrl != null) metadata['track_url'] = r.trackUrl;

    return Run(
      id: r.id,
      startedAt: r.startedAt,
      duration: Duration(seconds: r.durationS),
      distanceMetres: r.distanceM,
      track: const [],
      source: RunSource.values.firstWhere(
        (s) => s.name == r.source,
        orElse: () => RunSource.app,
      ),
      externalId: r.externalId,
      metadata: metadata.isEmpty ? null : metadata,
      createdAt: r.createdAt,
    );
  }

  static Route _routeFromRow(Map<String, dynamic> row) {
    final r = RouteRow.fromJson(row);
    return Route(
      id: r.id,
      name: r.name,
      waypoints: r.waypoints.map((m) => Waypoint(
            lat: (m['lat'] as num).toDouble(),
            lng: (m['lng'] as num).toDouble(),
            elevationMetres: (m['ele'] as num?)?.toDouble(),
          )).toList(),
      distanceMetres: r.distanceM,
      elevationGainMetres: r.elevationM ?? 0,
      isPublic: r.isPublic ?? false,
      surface: r.surface,
      createdAt: r.createdAt,
      tags: (row['tags'] as List?)?.cast<String>() ?? const [],
      featured: row['featured'] == true,
      runCount: (row['run_count'] as num?)?.toInt() ?? 0,
    );
  }
}
