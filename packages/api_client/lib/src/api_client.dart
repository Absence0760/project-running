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

  /// Download a track by its Storage path. Used when a caller has a
  /// raw `RunRow` (e.g. public-share screens) and doesn't want to
  /// shape it into a `Run` first.
  Future<List<Waypoint>> fetchTrackByPath(String path) async {
    if (path.isEmpty) return const [];
    return _downloadTrack(path);
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

  /// Recent public runs from a single user — drives the runs tab on
  /// `/u/[id]`-equivalent profile screens. Capped at `limit`.
  /// Fetch a single run by id. RLS gates access — owners see their own
  /// (public or private), other viewers only see runs where `is_public`
  /// is true.
  Future<RunRow?> fetchRunById(String runId) async {
    final row = await _client
        .from(RunRow.table)
        .select()
        .eq(RunRow.colId, runId)
        .maybeSingle();
    return row == null ? null : RunRow.fromJson(row);
  }

  /// Fetch a single route by id. RLS gates: owners see their own
  /// (public or private), other viewers only see public routes or
  /// routes owned by a club they belong to.
  Future<Route?> fetchRouteById(String routeId) async {
    final row = await _client
        .from(RouteRow.table)
        .select()
        .eq(RouteRow.colId, routeId)
        .maybeSingle();
    return row == null ? null : _routeFromRow(row);
  }

  Future<List<RunRow>> fetchPublicRunsByUser(String userId, {int limit = 50}) async {
    final data = await _client
        .from(RunRow.table)
        .select()
        .eq(RunRow.colUserId, userId)
        .eq(RunRow.colIsPublic, true)
        .order(RunRow.colStartedAt, ascending: false)
        .limit(limit);
    return data.map<RunRow>((r) => RunRow.fromJson(r)).toList();
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

  // ──────────────────── Run photos (P1.B) ────────────────────
  //
  // Metadata in `run_photos`; bytes in the public-read `run-photos`
  // Storage bucket at `{owner_id}/{photo_id}.{ext}`. Owner gates
  // upload + delete; visibility on the metadata row tracks the run.

  /// Photos for a run, ordered by position then created_at. Capped.
  Future<List<RunPhotoRow>> fetchRunPhotos(
    String runId, {
    int limit = 50,
  }) async {
    final data = await _client
        .from(RunPhotoRow.table)
        .select()
        .eq(RunPhotoRow.colRunId, runId)
        .order(RunPhotoRow.colPositionIdx, ascending: true)
        .order(RunPhotoRow.colCreatedAt, ascending: true)
        .limit(limit);
    return data.map<RunPhotoRow>((r) => RunPhotoRow.fromJson(r)).toList();
  }

  /// Upload bytes to the `run-photos` bucket and insert the metadata
  /// row. The caller passes the storage extension (e.g. 'jpg', 'png').
  Future<RunPhotoRow> addRunPhoto({
    required String runId,
    required Uint8List bytes,
    required String contentType,
    required String extension,
    String? caption,
    int positionIdx = 0,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final id = _client.auth.currentUser!.id;
    // Storage layout matches web: `{owner_id}/{photo_id}.{ext}`. The
    // photo_id is a fresh uuid generated server-side, so we let the
    // insert return it and *then* upload — keeps the storage path
    // and the row in lockstep without a follow-up update.
    final inserted = await _client
        .from(RunPhotoRow.table)
        .insert({
          RunPhotoRow.colRunId: runId,
          RunPhotoRow.colOwnerId: viewerId,
          RunPhotoRow.colStoragePath: '', // placeholder; updated below
          RunPhotoRow.colCaption: caption,
          RunPhotoRow.colPositionIdx: positionIdx,
        })
        .select()
        .single();
    final photoId = inserted[RunPhotoRow.colId] as String;
    final path = '$id/$photoId.$extension';
    await _client.storage.from('run-photos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    await _client
        .from(RunPhotoRow.table)
        .update({RunPhotoRow.colStoragePath: path})
        .eq(RunPhotoRow.colId, photoId);
    return RunPhotoRow.fromJson({...inserted, RunPhotoRow.colStoragePath: path});
  }

  /// Update an existing photo's caption.
  Future<void> updateRunPhotoCaption({
    required String photoId,
    String? caption,
  }) async {
    await _client
        .from(RunPhotoRow.table)
        .update({RunPhotoRow.colCaption: caption})
        .eq(RunPhotoRow.colId, photoId);
  }

  /// Delete a photo. Removes both the metadata row (RLS gates author
  /// / run-owner permissions) and the underlying Storage object.
  Future<void> deleteRunPhoto(RunPhotoRow photo) async {
    await _client
        .from(RunPhotoRow.table)
        .delete()
        .eq(RunPhotoRow.colId, photo.id);
    if (photo.storagePath.isNotEmpty) {
      await _client.storage.from('run-photos').remove([photo.storagePath]);
    }
  }

  // ──────────────────── Segments (P1.B) ────────────────────
  //
  // Route-anchored segments + per-run efforts. Auto-effort generation
  // is client-side on web (decisions §37); the android equivalent
  // walks the run track in `core_models`/segments and posts efforts
  // through `recordSegmentEffort` below.

  /// Segments anchored on a route, sorted by start distance.
  Future<List<SegmentRow>> fetchSegmentsForRoute(
    String routeId, {
    int limit = 100,
  }) async {
    final data = await _client
        .from(SegmentRow.table)
        .select()
        .eq(SegmentRow.colRouteId, routeId)
        .order(SegmentRow.colStartDistanceM, ascending: true)
        .limit(limit);
    return data.map<SegmentRow>((r) => SegmentRow.fromJson(r)).toList();
  }

  /// Define a new segment on a route. The DB computes `length_m` as
  /// a generated column, so we don't pass it.
  Future<SegmentRow> createSegment({
    required String routeId,
    required String name,
    required double startDistanceM,
    required double endDistanceM,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final inserted = await _client
        .from(SegmentRow.table)
        .insert({
          SegmentRow.colRouteId: routeId,
          SegmentRow.colName: name,
          SegmentRow.colStartDistanceM: startDistanceM,
          SegmentRow.colEndDistanceM: endDistanceM,
          SegmentRow.colCreatedBy: viewerId,
        })
        .select()
        .single();
    return SegmentRow.fromJson(inserted);
  }

  /// Routes owned by a club. Read-gated by RLS to club members; used
  /// by the club home Routes tab and event-editor route pickers.
  Future<List<Route>> fetchClubRoutes(String clubId) async {
    final rows = await _client
        .from(RouteRow.table)
        .select()
        .eq(RouteRow.colClubId, clubId)
        .order(RouteRow.colCreatedAt, ascending: false);
    return rows
        .map<Route>((r) => _routeFromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Transfer a route the viewer owns to a club they admin (or detach
  /// it back to personal by passing `null`). Admin-write-gated by RLS.
  Future<void> setRouteClub({
    required String routeId,
    required String? clubId,
  }) async {
    await _client
        .from(RouteRow.table)
        .update({RouteRow.colClubId: clubId})
        .eq(RouteRow.colId, routeId);
  }

  // ──────────────────── Saved (bookmarked) routes ────────────────────

  /// Bookmark a public route via the `saved_routes` reference table
  /// (decisions §30 — never clone the row). Idempotent against the
  /// composite-PK; duplicates resolve as a no-op.
  Future<void> bookmarkRoute(String routeId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    try {
      await _client.from(SavedRouteRow.table).insert({
        SavedRouteRow.colUserId: viewerId,
        SavedRouteRow.colRouteId: routeId,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  /// Drop the bookmark. Idempotent.
  Future<void> unbookmarkRoute(String routeId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client
        .from(SavedRouteRow.table)
        .delete()
        .eq(SavedRouteRow.colUserId, viewerId)
        .eq(SavedRouteRow.colRouteId, routeId);
  }

  /// Whether the current viewer has bookmarked this route.
  Future<bool> isRouteBookmarked(String routeId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return false;
    final row = await _client
        .from(SavedRouteRow.table)
        .select(SavedRouteRow.colRouteId)
        .eq(SavedRouteRow.colUserId, viewerId)
        .eq(SavedRouteRow.colRouteId, routeId)
        .maybeSingle();
    return row != null;
  }

  /// All routes the current viewer has bookmarked, joined to the parent
  /// `routes` row so callers can render full route cards. Sorted by
  /// `saved_at` desc.
  Future<List<Route>> fetchBookmarkedRoutes({int limit = 200}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    final rows = await _client
        .from(SavedRouteRow.table)
        .select('saved_at, route:${RouteRow.table}(*)')
        .eq(SavedRouteRow.colUserId, viewerId)
        .order(SavedRouteRow.colSavedAt, ascending: false)
        .limit(limit);
    final out = <Route>[];
    for (final r in rows) {
      final inner = r['route'];
      if (inner is Map<String, dynamic>) {
        out.add(_routeFromRow(inner));
      }
    }
    return out;
  }

  /// Delete a segment. RLS lets the route owner remove segments on
  /// their own route; cascades drop the segment_efforts rows.
  Future<void> deleteSegment(String segmentId) async {
    await _client
        .from(SegmentRow.table)
        .delete()
        .eq(SegmentRow.colId, segmentId);
  }

  /// Leaderboard for a single segment — fastest effort per user
  /// already enforced by `unique(segment_id, run_id)` and the client
  /// further dedupes per user. Capped at `limit` raw rows.
  Future<List<SegmentEffortRow>> fetchSegmentLeaderboard(
    String segmentId, {
    int limit = 200,
  }) async {
    final data = await _client
        .from(SegmentEffortRow.table)
        .select()
        .eq(SegmentEffortRow.colSegmentId, segmentId)
        .order(SegmentEffortRow.colTimeSeconds, ascending: true)
        .limit(limit);
    return data
        .map<SegmentEffortRow>((r) => SegmentEffortRow.fromJson(r))
        .toList();
  }

  /// All segment efforts for a single run (so the run-detail page can
  /// surface "you ranked 3rd on Centennial Hill" pills).
  Future<List<SegmentEffortRow>> fetchEffortsForRun(String runId) async {
    final data = await _client
        .from(SegmentEffortRow.table)
        .select()
        .eq(SegmentEffortRow.colRunId, runId);
    return data
        .map<SegmentEffortRow>((r) => SegmentEffortRow.fromJson(r))
        .toList();
  }

  /// Insert a single segment effort row. Idempotent against the
  /// `unique(segment_id, run_id)` constraint — the upsert with
  /// `ignoreDuplicates: true` swallows reimports of the same run.
  Future<void> recordSegmentEffort({
    required String segmentId,
    required String runId,
    required int timeSeconds,
    required DateTime startedAt,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client.from(SegmentEffortRow.table).upsert(
      {
        SegmentEffortRow.colSegmentId: segmentId,
        SegmentEffortRow.colRunId: runId,
        SegmentEffortRow.colUserId: viewerId,
        SegmentEffortRow.colTimeSeconds: timeSeconds,
        SegmentEffortRow.colStartedAt: startedAt.toIso8601String(),
      },
      onConflict:
          '${SegmentEffortRow.colSegmentId},${SegmentEffortRow.colRunId}',
      ignoreDuplicates: true,
    );
  }

  // ──────────────────── Privacy zones (P1.C) ────────────────────

  /// Server-side privacy-zone clipping. The zones never reach the
  /// client; the RPC reads them with security-definer privileges and
  /// returns the clipped middle of the input track. Falls back to
  /// the input if the RPC fails so a transient server error never
  /// leaks the unclipped track to a non-owner viewer of a public run.
  Future<List<Map<String, dynamic>>> clipTrackForUser({
    required String targetUserId,
    required List<Map<String, dynamic>> points,
  }) async {
    if (points.isEmpty) return points;
    try {
      final data = await _client.rpc('clip_track_for_user', params: {
        'target_user_id': targetUserId,
        'points': points,
      });
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      return points;
    } catch (_) {
      return points;
    }
  }

  // ──────────────────── Coach messages (P1.C) ────────────────────
  //
  // Active thread is `archived_at IS NULL` filtered by `(user_id,
  // plan_id)`. `plan_id IS NULL` is its own thread. The streaming
  // send path is mounted as a server-only edge function that the
  // android client should hit over fetch/SSE — that's a separate
  // wire concern; the methods below cover the reads + reactions +
  // archiving.

  /// Active-thread messages, oldest-first.
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    var q = _client
        .from(CoachMessageRow.table)
        .select()
        .eq(CoachMessageRow.colUserId, viewerId)
        .isFilter(CoachMessageRow.colArchivedAt, null);
    q = planId == null
        ? q.isFilter(CoachMessageRow.colPlanId, null)
        : q.eq(CoachMessageRow.colPlanId, planId);
    final data = await q
        .order(CoachMessageRow.colCreatedAt, ascending: true)
        .limit(500);
    return data
        .map<CoachMessageRow>((r) => CoachMessageRow.fromJson(r))
        .toList();
  }

  /// Set / clear the up/down reaction on an assistant bubble.
  Future<void> setCoachReaction({
    required String messageId,
    String? reaction, // 'up' | 'down' | null to clear
  }) async {
    await _client
        .from(CoachMessageRow.table)
        .update({CoachMessageRow.colReaction: reaction})
        .eq(CoachMessageRow.colId, messageId);
  }

  /// Archive every message in the active thread for the current
  /// `(user_id, plan_id)` scope so a fresh conversation can begin.
  Future<void> archiveCoachThread({String? planId}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    final ts = DateTime.now().toIso8601String();
    var q = _client
        .from(CoachMessageRow.table)
        .update({CoachMessageRow.colArchivedAt: ts})
        .eq(CoachMessageRow.colUserId, viewerId)
        .isFilter(CoachMessageRow.colArchivedAt, null);
    q = planId == null
        ? q.isFilter(CoachMessageRow.colPlanId, null)
        : q.eq(CoachMessageRow.colPlanId, planId);
    await q;
  }

  /// Distinct archived_at timestamps (one per archived thread) for
  /// the history sidebar.
  Future<List<DateTime>> listCoachArchives({String? planId}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    var q = _client
        .from(CoachMessageRow.table)
        .select(CoachMessageRow.colArchivedAt)
        .eq(CoachMessageRow.colUserId, viewerId)
        .not(CoachMessageRow.colArchivedAt, 'is', null);
    q = planId == null
        ? q.isFilter(CoachMessageRow.colPlanId, null)
        : q.eq(CoachMessageRow.colPlanId, planId);
    final data = await q.order(CoachMessageRow.colArchivedAt, ascending: false);
    final seen = <String>{};
    final out = <DateTime>[];
    for (final row in data) {
      final raw = row[CoachMessageRow.colArchivedAt] as String?;
      if (raw == null || !seen.add(raw)) continue;
      out.add(DateTime.parse(raw));
    }
    return out;
  }

  /// Fetch a specific archived thread (read-only viewer).
  Future<List<CoachMessageRow>> fetchCoachArchive({
    required DateTime archivedAt,
    String? planId,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    var q = _client
        .from(CoachMessageRow.table)
        .select()
        .eq(CoachMessageRow.colUserId, viewerId)
        .eq(CoachMessageRow.colArchivedAt, archivedAt.toIso8601String());
    q = planId == null
        ? q.isFilter(CoachMessageRow.colPlanId, null)
        : q.eq(CoachMessageRow.colPlanId, planId);
    final data =
        await q.order(CoachMessageRow.colCreatedAt, ascending: true);
    return data
        .map<CoachMessageRow>((r) => CoachMessageRow.fromJson(r))
        .toList();
  }

  /// RPC for the per-user-per-day usage counter. Free tier capped at
  /// 10/day server-side; `is_pro()` lifts the cap.
  Future<int> getCoachUsage() async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return 0;
    final value = await _client.rpc(
      'get_coach_usage',
      params: {'p_user_id': viewerId},
    );
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  /// RPC `is_pro` — true when the viewer's active subscription tier
  /// is paid. Used to short-circuit the daily cap and gate Pro UI.
  Future<bool> isPro() async {
    final value = await _client.rpc('is_pro');
    return value == true;
  }

  // ──────────────────── Clubs + events (P1.D) ────────────────────

  /// Create a new club. `joinPolicy` is one of 'open' | 'request' |
  /// 'invite'. The `enroll_club_owner` trigger auto-inserts the
  /// owner's club_members row, so we don't add it here.
  Future<ClubRow> createClub({
    required String name,
    required String slug,
    String? description,
    String? locationLabel,
    bool isPublic = true,
    String joinPolicy = 'open',
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final inserted = await _client
        .from(ClubRow.table)
        .insert({
          ClubRow.colOwnerId: viewerId,
          ClubRow.colName: name,
          ClubRow.colSlug: slug,
          ClubRow.colDescription: description,
          ClubRow.colLocationLabel: locationLabel,
          ClubRow.colIsPublic: isPublic,
          ClubRow.colJoinPolicy: joinPolicy,
        })
        .select()
        .single();
    return ClubRow.fromJson(inserted);
  }

  /// Edit owner-side club fields.
  Future<void> updateClub({
    required String clubId,
    String? name,
    String? description,
    String? locationLabel,
    bool? isPublic,
    String? joinPolicy,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch[ClubRow.colName] = name;
    if (description != null) patch[ClubRow.colDescription] = description;
    if (locationLabel != null) patch[ClubRow.colLocationLabel] = locationLabel;
    if (isPublic != null) patch[ClubRow.colIsPublic] = isPublic;
    if (joinPolicy != null) patch[ClubRow.colJoinPolicy] = joinPolicy;
    if (patch.isEmpty) return;
    await _client.from(ClubRow.table).update(patch).eq(ClubRow.colId, clubId);
  }

  /// Redeem a join token from a public invite link.
  Future<String> joinClubByToken(String token) async {
    final result =
        await _client.rpc('join_club_by_token', params: {'p_token': token});
    return result as String;
  }

  /// Request to join a club whose policy is `request`. Status starts
  /// `pending`; an admin approves via the methods below.
  Future<void> requestJoinClub(String clubId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client.from(ClubMemberRow.table).insert({
      ClubMemberRow.colClubId: clubId,
      ClubMemberRow.colUserId: viewerId,
      ClubMemberRow.colRole: 'member',
      ClubMemberRow.colStatus: 'pending',
    });
  }

  /// Pending join requests for an admin to action.
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async {
    final data = await _client
        .from(ClubMemberRow.table)
        .select()
        .eq(ClubMemberRow.colClubId, clubId)
        .eq(ClubMemberRow.colStatus, 'pending')
        .order(ClubMemberRow.colJoinedAt, ascending: false);
    return data
        .map<ClubMemberRow>((r) => ClubMemberRow.fromJson(r))
        .toList();
  }

  /// Approve a pending member.
  Future<void> approveJoinRequest({
    required String clubId,
    required String userId,
  }) async {
    await _client
        .from(ClubMemberRow.table)
        .update({ClubMemberRow.colStatus: 'active'})
        .eq(ClubMemberRow.colClubId, clubId)
        .eq(ClubMemberRow.colUserId, userId);
  }

  /// Deny / remove a pending member.
  Future<void> denyJoinRequest({
    required String clubId,
    required String userId,
  }) async {
    await _client
        .from(ClubMemberRow.table)
        .delete()
        .eq(ClubMemberRow.colClubId, clubId)
        .eq(ClubMemberRow.colUserId, userId)
        .eq(ClubMemberRow.colStatus, 'pending');
  }

  /// Create a new event under a club. Recurrence fields are exposed
  /// as raw `recurrence_freq` / `recurrence_byday` strings — the
  /// caller is responsible for the format the backend expects.
  Future<EventRow> createEvent({
    required String clubId,
    required String title,
    required DateTime startsAt,
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
    String? recurrenceByDay,
    DateTime? recurrenceUntil,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final inserted = await _client
        .from(EventRow.table)
        .insert({
          EventRow.colClubId: clubId,
          EventRow.colTitle: title,
          EventRow.colDescription: description,
          EventRow.colStartsAt: startsAt.toIso8601String(),
          EventRow.colDurationMin: durationMin,
          EventRow.colMeetLabel: meetLabel,
          EventRow.colMeetLat: meetLat,
          EventRow.colMeetLng: meetLng,
          EventRow.colRouteId: routeId,
          EventRow.colDistanceM: distanceM,
          EventRow.colPaceTargetSec: paceTargetSec,
          EventRow.colCapacity: capacity,
          EventRow.colCreatedBy: viewerId,
          if (recurrenceFreq != null) 'recurrence_freq': recurrenceFreq,
          if (recurrenceByDay != null) 'recurrence_byday': recurrenceByDay,
          if (recurrenceUntil != null)
            'recurrence_until': recurrenceUntil.toIso8601String(),
        })
        .select()
        .single();
    return EventRow.fromJson(inserted);
  }

  /// Edit any event field — back-end CHECK constraints validate.
  Future<void> updateEvent({
    required String eventId,
    Map<String, dynamic> patch = const {},
  }) async {
    if (patch.isEmpty) return;
    await _client
        .from(EventRow.table)
        .update(patch)
        .eq(EventRow.colId, eventId);
  }

  /// Cancel an event (cascade-deletes attendees + per-instance
  /// updates).
  Future<void> deleteEvent(String eventId) async {
    await _client.from(EventRow.table).delete().eq(EventRow.colId, eventId);
  }

  /// RSVP to an event for the current viewer. `status` is one of
  /// 'going' | 'maybe' | 'declined'. `instanceStart` is the recurring
  /// instance start; for one-off events, pass the event's `startsAt`.
  Future<void> setEventRsvp({
    required String eventId,
    required DateTime instanceStart,
    required String status,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client.from(EventAttendeeRow.table).upsert(
      {
        EventAttendeeRow.colEventId: eventId,
        EventAttendeeRow.colUserId: viewerId,
        EventAttendeeRow.colStatus: status,
        EventAttendeeRow.colInstanceStart: instanceStart.toIso8601String(),
      },
      onConflict:
          '${EventAttendeeRow.colEventId},${EventAttendeeRow.colUserId},${EventAttendeeRow.colInstanceStart}',
    );
  }

  /// Per-instance attendee list.
  Future<List<EventAttendeeRow>> fetchEventAttendees({
    required String eventId,
    required DateTime instanceStart,
  }) async {
    final data = await _client
        .from(EventAttendeeRow.table)
        .select()
        .eq(EventAttendeeRow.colEventId, eventId)
        .eq(EventAttendeeRow.colInstanceStart, instanceStart.toIso8601String());
    return data
        .map<EventAttendeeRow>((r) => EventAttendeeRow.fromJson(r))
        .toList();
  }

  // ──────────────────── Plan templates (P1.D) ────────────────────

  /// Plan templates owned by `clubId` — visible to club members.
  Future<List<TrainingPlanRow>> fetchClubTemplates(
    String clubId, {
    int limit = 100,
  }) async {
    final data = await _client
        .from(TrainingPlanRow.table)
        .select()
        .eq('is_template', true)
        .eq('club_id', clubId)
        .order(TrainingPlanRow.colCreatedAt, ascending: false)
        .limit(limit);
    return data
        .map<TrainingPlanRow>((r) => TrainingPlanRow.fromJson(r))
        .toList();
  }

  /// Publish a personal plan as a club template. Server-side RPC
  /// clones the source plan + its weeks + workouts so the source
  /// stays in the user's plan list (decisions §35).
  Future<String> publishPlanAsTemplate({
    required String planId,
    required String clubId,
  }) async {
    final newId = await _client.rpc(
      'publish_plan_as_template',
      params: {'p_source_plan_id': planId, 'p_club_id': clubId},
    );
    return newId as String;
  }

  /// Adopt a club template — clones the template back into a personal
  /// plan for the current viewer.
  Future<String> clonePlanTemplate({
    required String templateId,
    DateTime? startDate,
  }) async {
    final newId = await _client.rpc(
      'clone_plan_template',
      params: {
        'p_template_id': templateId,
        if (startDate != null) 'p_start_date': startDate.toIso8601String(),
      },
    );
    return newId as String;
  }

  // ──────────────────── Phase 2 — domain joins ────────────────────
  //
  // Methods that combine multiple rows into a `core_models/social.dart`
  // shape. Lives here rather than in the screen layer so every
  // consumer (feed, profile, run-detail comments) sees the same
  // typed view.

  /// Profile + follower / following counts + whether the current
  /// viewer follows. Three reads in flight in parallel; null when
  /// the user doesn't exist or RLS hides the row.
  Future<ProfileSummary?> fetchProfileSummary(String userId) async {
    final results = await Future.wait([
      fetchPublicProfile(userId),
      fetchFollowCounts(userId),
      viewerFollows(userId),
    ]);
    final profile = results[0] as UserProfileRow?;
    if (profile == null) return null;
    final counts = results[1] as ({int followers, int following});
    final follows = results[2] as bool;
    return ProfileSummary(
      id: profile.id,
      displayName: profile.displayName,
      avatarUrl: profile.avatarUrl,
      followerCount: counts.followers,
      followingCount: counts.following,
      viewerFollows: follows,
    );
  }

  /// Activity feed: public runs from people the caller follows in the
  /// last `feedWindowDays` (defaults to 14, matching the web cap on
  /// `FEED_WINDOW_DAYS`). Cursor-paginated on `(started_at desc, id
  /// desc)`. Optional filters scope to a single followee or a single
  /// activity type so the feed toolbar can drive them server-side.
  Future<List<FeedEntry>> fetchFollowingFeed({
    int limit = 20,
    ({DateTime startedAt, String id})? cursor,
    String? authorId,
    String? activityType,
    int feedWindowDays = 14,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];

    final edges = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFolloweeId)
        .eq(UserFollowRow.colFollowerId, viewerId);
    final followeeIds = edges
        .map<String>((e) => e[UserFollowRow.colFolloweeId] as String)
        .toList();
    if (followeeIds.isEmpty) return const [];

    final filtered = authorId == null
        ? followeeIds
        : followeeIds.where((id) => id == authorId).toList();
    if (filtered.isEmpty) return const [];

    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: feedWindowDays))
        .toIso8601String();

    var q = _client
        .from(RunRow.table)
        .select()
        .inFilter(RunRow.colUserId, filtered)
        .eq(RunRow.colIsPublic, true)
        .gte(RunRow.colStartedAt, cutoff);
    if (activityType != null && activityType != 'all') {
      q = q.eq('metadata->>activity_type', activityType);
    }
    if (cursor != null) {
      // Stable (started_at desc, id desc) cursor — strictly less than
      // the cursor row.
      final iso = cursor.startedAt.toIso8601String();
      q = q.or(
        'started_at.lt.$iso,and(started_at.eq.$iso,id.lt.${cursor.id})',
      );
    }
    final runs = await q
        .order(RunRow.colStartedAt, ascending: false)
        .order(RunRow.colId, ascending: false)
        .limit(limit);
    if (runs.isEmpty) return const [];

    final authorIds = runs
        .map<String>((r) => r[RunRow.colUserId] as String)
        .toSet()
        .toList();
    final profileRows = await _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url')
        .inFilter(UserProfileRow.colId, authorIds);
    final profilesById = {
      for (final p in profileRows)
        p['id'] as String: PublicProfile.fromJson(p as Map<String, dynamic>),
    };

    return runs.map<FeedEntry>((r) {
      final row = RunRow.fromJson(r);
      return FeedEntry(
        run: row,
        author: profilesById[row.userId] ??
            PublicProfile(id: row.userId, displayName: null, avatarUrl: null),
      );
    }).toList();
  }

  /// Comments on a run with author profiles joined.
  Future<List<RunCommentWithAuthor>> fetchRunCommentsWithAuthors(
    String runId, {
    int limit = 200,
  }) async {
    final comments = await fetchRunComments(runId, limit: limit);
    if (comments.isEmpty) return const [];
    final authorIds =
        comments.map((c) => c.authorId).toSet().toList();
    final profileRows = await _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url')
        .inFilter(UserProfileRow.colId, authorIds);
    final profilesById = {
      for (final p in profileRows)
        p['id'] as String: PublicProfile.fromJson(p as Map<String, dynamic>),
    };
    return comments
        .map((c) => RunCommentWithAuthor(
              comment: c,
              author: profilesById[c.authorId] ??
                  PublicProfile(
                      id: c.authorId, displayName: null, avatarUrl: null),
            ))
        .toList();
  }

  /// Notifications with actor profiles + lightweight run / comment
  /// metadata joined for the verb line. Three round-trips: notifs,
  /// actors, runs (only the rows referenced).
  Future<List<NotificationView>> fetchNotificationViews({
    int limit = 100,
  }) async {
    final rows = await fetchNotifications(limit: limit);
    if (rows.isEmpty) return const [];

    final actorIds = rows
        .where((r) => r.actorId != null)
        .map<String>((r) => r.actorId!)
        .toSet()
        .toList();
    final runIds = rows
        .where((r) => r.runId != null)
        .map<String>((r) => r.runId!)
        .toSet()
        .toList();
    final commentIds = rows
        .where((r) => r.commentId != null)
        .map<String>((r) => r.commentId!)
        .toSet()
        .toList();

    final actorRowsF = actorIds.isEmpty
        ? Future.value(<dynamic>[])
        : _client
            .from(UserProfileRow.table)
            .select('id, display_name, avatar_url')
            .inFilter(UserProfileRow.colId, actorIds);
    final runRowsF = runIds.isEmpty
        ? Future.value(<dynamic>[])
        : _client
            .from(RunRow.table)
            .select('${RunRow.colId}, ${RunRow.colDistanceM}')
            .inFilter(RunRow.colId, runIds);
    final commentRowsF = commentIds.isEmpty
        ? Future.value(<dynamic>[])
        : _client
            .from(RunCommentRow.table)
            .select('${RunCommentRow.colId}, ${RunCommentRow.colBody}')
            .inFilter(RunCommentRow.colId, commentIds);

    final results = await Future.wait([actorRowsF, runRowsF, commentRowsF]);
    final actorRows = results[0] as List<dynamic>;
    final runRows = results[1] as List<dynamic>;
    final commentRows = results[2] as List<dynamic>;

    final actorsById = <String, PublicProfile>{};
    for (final r in actorRows) {
      final row = r as Map<String, dynamic>;
      actorsById[row['id'] as String] = PublicProfile.fromJson(row);
    }
    final runDistanceById = <String, double>{};
    for (final r in runRows) {
      final row = r as Map<String, dynamic>;
      final dist = row[RunRow.colDistanceM];
      if (dist is num) runDistanceById[row[RunRow.colId] as String] = dist.toDouble();
    }
    final commentBodyById = <String, String>{};
    for (final r in commentRows) {
      final row = r as Map<String, dynamic>;
      commentBodyById[row[RunCommentRow.colId] as String] =
          (row[RunCommentRow.colBody] as String?) ?? '';
    }

    String? excerpt(String? id) {
      if (id == null) return null;
      final body = commentBodyById[id];
      if (body == null || body.isEmpty) return null;
      return body.length > 140 ? '${body.substring(0, 140)}…' : body;
    }

    return rows
        .map((row) => NotificationView(
              row: row,
              actor: row.actorId == null ? null : actorsById[row.actorId!],
              runDistanceM:
                  row.runId == null ? null : runDistanceById[row.runId!],
              commentExcerpt: excerpt(row.commentId),
            ))
        .toList();
  }

  /// Segment leaderboard with athlete profiles + ranks. Sorted
  /// by time ascending; dedupes per user (keeps each athlete's
  /// fastest effort).
  Future<List<SegmentLeaderboardEntry>> fetchSegmentLeaderboardWithAthletes(
    String segmentId, {
    int limit = 200,
  }) async {
    final raw = await fetchSegmentLeaderboard(segmentId, limit: limit);
    if (raw.isEmpty) return const [];

    final byUser = <String, SegmentEffortRow>{};
    for (final eff in raw) {
      final existing = byUser[eff.userId];
      if (existing == null || eff.timeSeconds < existing.timeSeconds) {
        byUser[eff.userId] = eff;
      }
    }
    final efforts = byUser.values.toList()
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    final athleteIds = efforts.map((e) => e.userId).toList();
    final profileRows = await _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url')
        .inFilter(UserProfileRow.colId, athleteIds);
    final athletesById = {
      for (final p in profileRows)
        p['id'] as String: PublicProfile.fromJson(p as Map<String, dynamic>),
    };

    final out = <SegmentLeaderboardEntry>[];
    for (var i = 0; i < efforts.length; i++) {
      final eff = efforts[i];
      out.add(SegmentLeaderboardEntry(
        effort: eff,
        athlete: athletesById[eff.userId] ??
            PublicProfile(
                id: eff.userId, displayName: null, avatarUrl: null),
        rank: i + 1,
      ));
    }
    return out;
  }

  /// Per-run segment efforts joined to their parent segment + a rank
  /// against the segment's leaderboard. Backs the chips on run-detail.
  Future<List<SegmentEffortWithSegment>> fetchEffortsForRunWithSegments(
    String runId,
  ) async {
    final efforts = await fetchEffortsForRun(runId);
    if (efforts.isEmpty) return const [];

    final segIds = efforts.map((e) => e.segmentId).toSet().toList();
    final segRows = await _client
        .from(SegmentRow.table)
        .select()
        .inFilter(SegmentRow.colId, segIds);
    final segById = {
      for (final s in segRows)
        s['id'] as String: SegmentRow.fromJson(s as Map<String, dynamic>),
    };

    final out = <SegmentEffortWithSegment>[];
    for (final eff in efforts) {
      final seg = segById[eff.segmentId];
      if (seg == null) continue;
      // Rank = (count of efforts on this segment with strictly faster
      // time) + 1. The (segment_id, time_seconds) index covers it.
      final faster = await _client
          .from(SegmentEffortRow.table)
          .count(CountOption.exact)
          .eq(SegmentEffortRow.colSegmentId, eff.segmentId)
          .lt(SegmentEffortRow.colTimeSeconds, eff.timeSeconds);
      out.add(SegmentEffortWithSegment(
        effort: eff,
        segment: seg,
        rank: faster + 1,
      ));
    }
    return out;
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
