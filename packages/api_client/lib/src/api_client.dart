import 'package:core_models/core_models.dart';

/// Typed HTTP client for the Supabase REST API.
///
/// Handles token refresh, retry logic, and offline queuing.
class ApiClient {
  /// Saves a completed [Run] to the backend.
  Future<void> saveRun(Run run) async {
    // TODO: Implement Supabase REST call
  }

  /// Fetches the user's runs, newest first.
  Future<List<Run>> getRuns({int limit = 20, DateTime? before}) async {
    // TODO: Implement Supabase REST call
    return [];
  }

  /// Saves a [Route] to the backend.
  Future<void> saveRoute(Route route) async {
    // TODO: Implement Supabase REST call
  }

  /// Fetches the user's saved routes.
  Future<List<Route>> getRoutes() async {
    // TODO: Implement Supabase REST call
    return [];
  }
}
