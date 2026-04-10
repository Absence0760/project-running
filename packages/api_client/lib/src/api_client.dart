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

  /// Saves a completed [Run] to the backend.
  Future<void> saveRun(Run run) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // Map from Dart model to Supabase snake_case schema
    final trackJson = run.track.map((w) => {
      'lat': w.lat,
      'lng': w.lng,
      'ele': w.elevationMetres,
      'ts': w.timestamp?.toIso8601String(),
    }).toList();

    await _client.from('runs').insert({
      'user_id': userId,
      'started_at': run.startedAt.toIso8601String(),
      'duration_s': run.duration.inSeconds,
      'distance_m': run.distanceMetres,
      'track': trackJson,
      'source': run.source.name,
      'external_id': run.externalId,
      'metadata': run.metadata,
    });
  }

  /// Fetches the user's runs, newest first.
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
    final trackList = (row['track'] as List<dynamic>?) ?? [];
    return Run(
      id: row['id'] as String,
      startedAt: DateTime.parse(row['started_at'] as String),
      duration: Duration(seconds: (row['duration_s'] as num).toInt()),
      distanceMetres: (row['distance_m'] as num).toDouble(),
      track: trackList.map((t) {
        final m = t as Map<String, dynamic>;
        return Waypoint(
          lat: (m['lat'] as num).toDouble(),
          lng: (m['lng'] as num).toDouble(),
          elevationMetres: (m['ele'] as num?)?.toDouble(),
          timestamp: m['ts'] != null ? DateTime.tryParse(m['ts'] as String) : null,
        );
      }).toList(),
      source: RunSource.values.firstWhere(
        (s) => s.name == row['source'],
        orElse: () => RunSource.app,
      ),
      externalId: row['external_id'] as String?,
      metadata: row['metadata'] as Map<String, dynamic>?,
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
