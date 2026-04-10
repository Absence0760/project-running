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
  Future<void> saveRun(Run run) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    String? trackUrl;
    if (run.track.isNotEmpty) {
      trackUrl = await _uploadTrack(userId: userId, runId: run.id, track: run.track);
    }

    await _client.from('runs').upsert({
      'id': run.id,
      'user_id': userId,
      'started_at': run.startedAt.toIso8601String(),
      'duration_s': run.duration.inSeconds,
      'distance_m': run.distanceMetres,
      'track_url': trackUrl,
      'source': run.source.name,
      'external_id': run.externalId,
      'metadata': run.metadata,
    });
  }

  /// Fetch the user's runs, newest first.
  ///
  /// Returned runs have an empty `track`. Use [fetchTrack] to download the
  /// GPS waypoints for a single run when its detail page is opened.
  Future<List<Run>> getRuns({int limit = 50, DateTime? before}) async {
    var query = _client.from('runs').select();

    if (before != null) {
      query = query.lt('started_at', before.toIso8601String());
    }

    final data = await query
        .order('started_at', ascending: false)
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
        'ts': w.timestamp?.toIso8601String(),
      };

  static Waypoint _waypointFromJson(Map<String, dynamic> m) => Waypoint(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        elevationMetres: (m['ele'] as num?)?.toDouble(),
        timestamp: m['ts'] != null ? DateTime.tryParse(m['ts'] as String) : null,
      );

  /// Saves a [Route] to the backend.
  Future<void> saveRoute(Route route) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await _client.from('routes').insert({
      'user_id': userId,
      'name': route.name,
      'waypoints': route.waypoints.map((w) => {
        'lat': w.lat,
        'lng': w.lng,
        'ele': w.elevationMetres,
      }).toList(),
      'distance_m': route.distanceMetres,
      'elevation_m': route.elevationGainMetres,
      'is_public': route.isPublic,
    });
  }

  /// Fetches the user's saved routes.
  Future<List<Route>> getRoutes() async {
    final data = await _client
        .from('routes')
        .select()
        .order('created_at', ascending: false);

    return data.map<Route>((row) => _routeFromRow(row)).toList();
  }

  // -- Row mapping (Supabase snake_case → Dart models) --

  static Run _runFromRow(Map<String, dynamic> row) {
    // Stash the storage path on metadata so callers can pass the run back
    // to fetchTrack() to lazy-load the GPS waypoints. The track field itself
    // stays empty until fetched.
    final metadata = Map<String, dynamic>.from(
      (row['metadata'] as Map<String, dynamic>?) ?? const {},
    );
    final trackUrl = row['track_url'] as String?;
    if (trackUrl != null) metadata['track_url'] = trackUrl;

    return Run(
      id: row['id'] as String,
      startedAt: DateTime.parse(row['started_at'] as String),
      duration: Duration(seconds: (row['duration_s'] as num).toInt()),
      distanceMetres: (row['distance_m'] as num).toDouble(),
      track: const [],
      source: RunSource.values.firstWhere(
        (s) => s.name == row['source'],
        orElse: () => RunSource.app,
      ),
      externalId: row['external_id'] as String?,
      metadata: metadata.isEmpty ? null : metadata,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : null,
    );
  }

  static Route _routeFromRow(Map<String, dynamic> row) {
    final wpList = (row['waypoints'] as List<dynamic>?) ?? [];
    return Route(
      id: row['id'] as String,
      name: row['name'] as String,
      waypoints: wpList.map((w) {
        final m = w as Map<String, dynamic>;
        return Waypoint(
          lat: (m['lat'] as num).toDouble(),
          lng: (m['lng'] as num).toDouble(),
          elevationMetres: (m['ele'] as num?)?.toDouble(),
        );
      }).toList(),
      distanceMetres: (row['distance_m'] as num).toDouble(),
      elevationGainMetres: (row['elevation_m'] as num?)?.toDouble() ?? 0,
      isPublic: row['is_public'] as bool? ?? false,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : null,
    );
  }
}
