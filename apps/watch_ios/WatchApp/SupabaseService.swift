import Foundation

/// Lightweight Supabase client for the watch app.
/// Authenticates with email/password and syncs runs via the REST API.
actor SupabaseService {
    static let shared = SupabaseService()

    // Local Supabase instance — change for production
    private let baseURL = "http://127.0.0.1:54321"
    private let anonKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"

    private var accessToken: String?
    private var userId: String?

    // MARK: - Auth

    /// Sign in with email/password. Returns the user ID.
    func signIn(email: String, password: String) async throws -> String {
        let url = URL(string: "\(baseURL)/auth/v1/token?grant_type=password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.authFailed(message)
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        self.accessToken = authResponse.access_token
        self.userId = authResponse.user.id
        return authResponse.user.id
    }

    var isAuthenticated: Bool {
        accessToken != nil
    }

    // MARK: - Sync Run

    /// Insert a finished run into the `runs` table.
    func syncRun(_ run: WorkoutManager.FinishedRun) async throws {
        guard let token = accessToken, let userId = userId else {
            throw SupabaseError.notAuthenticated
        }

        let url = URL(string: "\(baseURL)/rest/v1/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let runPayload = RunPayload(
            user_id: userId,
            started_at: formatter.string(from: run.startedAt),
            duration_s: run.durationSeconds,
            distance_m: run.distanceMetres,
            track: run.track,
            source: "app"
        )

        request.httpBody = try JSONEncoder().encode(runPayload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.syncFailed(message)
        }
    }

    // MARK: - Types

    private struct AuthResponse: Decodable {
        let access_token: String
        let user: AuthUser
    }

    private struct AuthUser: Decodable {
        let id: String
    }

    private struct RunPayload: Encodable {
        let user_id: String
        let started_at: String
        let duration_s: Int
        let distance_m: Double
        let track: [WorkoutManager.TrackPoint]
        let source: String
    }

    enum SupabaseError: LocalizedError {
        case authFailed(String)
        case notAuthenticated
        case syncFailed(String)

        var errorDescription: String? {
            switch self {
            case .authFailed(let msg): return "Auth failed: \(msg)"
            case .notAuthenticated: return "Not signed in"
            case .syncFailed(let msg): return "Sync failed: \(msg)"
            }
        }
    }
}
