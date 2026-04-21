#if DEBUG
import Foundation
import Compression

/// DEBUG-only direct-to-Supabase path for watch-simulator-alone dev.
/// Release builds ship without this file — the watch transfers runs to the
/// paired iPhone via `WCSession.transferFile` and the phone owns the Supabase
/// write. See `ContentView.syncRunDirect()`.
actor SupabaseService {
    static let shared = SupabaseService()

    // Defaults used only by the DEBUG seed sign-in fallback in `ContentView`.
    // In production the paired iPhone hands over baseURL + anonKey + token
    // over `WCSession.updateApplicationContext(_:)`.
    private var baseURL = "http://127.0.0.1:54321"
    private var anonKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"

    private var accessToken: String?
    private var userId: String?

    // MARK: - Credentials handoff

    /// Apply credentials handed over from the paired iPhone via WCSession.
    func applyCredentials(accessToken: String, userId: String, baseURL: String, anonKey: String) {
        self.accessToken = accessToken
        self.userId = userId
        self.baseURL = baseURL
        self.anonKey = anonKey
    }

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

    /// Insert a finished run into the `runs` table. The GPS trace is uploaded
    /// as a gzipped JSON object to the `runs` Storage bucket; the row stores
    /// only the object path in `track_url`.
    func syncRun(_ run: WorkoutManager.FinishedRun) async throws {
        guard let token = accessToken, let userId = userId else {
            throw SupabaseError.notAuthenticated
        }

        let objectPath = "\(userId)/\(run.id).json.gz"

        let trackJson = try JSONEncoder().encode(run.track)
        let gzipped = try gzip(trackJson)
        try await uploadTrack(path: objectPath, body: gzipped, token: token)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let runPayload = RunPayload(
            id: run.id,
            user_id: userId,
            started_at: formatter.string(from: run.startedAt),
            duration_s: run.durationSeconds,
            distance_m: run.distanceMetres,
            track_url: objectPath,
            source: "watch"
        )

        let url = URL(string: "\(baseURL)/rest/v1/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(runPayload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.syncFailed(message)
        }
    }

    private func uploadTrack(path: String, body: Data, token: String) async throws {
        let url = URL(string: "\(baseURL)/storage/v1/object/runs/\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.syncFailed("Track upload failed: \(message)")
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
        let id: String
        let user_id: String
        let started_at: String
        let duration_s: Int
        let distance_m: Double
        let track_url: String
        let source: String
    }

    enum SupabaseError: LocalizedError {
        case authFailed(String)
        case notAuthenticated
        case syncFailed(String)
        case compressionFailed

        var errorDescription: String? {
            switch self {
            case .authFailed(let msg): return "Auth failed: \(msg)"
            case .notAuthenticated: return "Not signed in"
            case .syncFailed(let msg): return "Sync failed: \(msg)"
            case .compressionFailed: return "Track compression failed"
            }
        }
    }
}

// MARK: - Gzip

/// Wraps raw DEFLATE output from `Compression.framework` in a standard gzip
/// envelope (10-byte header + CRC32 + ISIZE trailer) so the web and mobile
/// clients can decompress it with any off-the-shelf gzip reader.
private func gzip(_ data: Data) throws -> Data {
    let bufferSize = max(data.count + 128, 256)
    var compressed = Data(count: bufferSize)

    let compressedSize: Int = compressed.withUnsafeMutableBytes { destPtr -> Int in
        guard let dest = destPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        return data.withUnsafeBytes { srcPtr -> Int in
            guard let src = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_encode_buffer(dest, bufferSize, src, data.count, nil, COMPRESSION_ZLIB)
        }
    }
    guard compressedSize > 0 else { throw SupabaseService.SupabaseError.compressionFailed }
    compressed.count = compressedSize

    var out = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff])
    out.append(compressed)

    let crc = crc32(data)
    out.append(contentsOf: withUnsafeBytes(of: crc.littleEndian, Array.init))

    let size = UInt32(truncatingIfNeeded: data.count)
    out.append(contentsOf: withUnsafeBytes(of: size.littleEndian, Array.init))

    return out
}

private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFFFFFF
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            let mask = UInt32(0) &- (crc & 1)
            crc = (crc >> 1) ^ (0xEDB88320 & mask)
        }
    }
    return ~crc
}

/// Convenience for the DEBUG fallback: sign in with the seed user and sync
/// the finished run directly to the local Supabase instance, bypassing the
/// phone. Used when the watch simulator is running alone.
func syncRunDirectDebug(_ run: WorkoutManager.FinishedRun) async throws {
    if await !SupabaseService.shared.isAuthenticated {
        _ = try await SupabaseService.shared.signIn(email: "runner@test.com", password: "testtest")
    }
    try await SupabaseService.shared.syncRun(run)
}
#endif
