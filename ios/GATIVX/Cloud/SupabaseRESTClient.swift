import Foundation
import CoreLocation
import Security
import Combine

@MainActor
final class SupabaseRESTClient: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var status = "Sign in with your existing GATIVX web-app account."

    private let baseURL = URL(string: "https://crarbbsvcczwmtvxyrxo.supabase.co")!
    // Supabase publishable key is a client-side key. Never place a service-role key in the app.
    private let publishableKey = "sb_publishable_XAGRFtrWrFqJ-JSfXh2WbRQ_jCcPnr-6"
    private let sessionStore = "com.paramitsolutions.gativx.session"
    private var accessToken: String?
    private var refreshToken: String?

    init() {
        if let saved = readSession() {
            accessToken = saved.accessToken
            refreshToken = saved.refreshToken
            isSignedIn = accessToken != nil
        }
    }

    func signIn(email: String, password: String) async {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/v1/token").appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
            request.httpMethod = "POST"
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw Self.serverError(data)
            }
            let session = try JSONDecoder().decode(AuthSession.self, from: data)
            accessToken = session.accessToken
            refreshToken = session.refreshToken
            saveSession(session)
            isSignedIn = true
            status = "Signed in. Your existing cloud records can be shared with GATIVX."
        } catch {
            status = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func syncSteps(date: Date, steps: Int) async {
        guard steps >= 0 else { return }
        do {
            try await performStepSync(date: date, steps: steps, retryAfterRefresh: true)
            status = "Apple Health steps synced to your GATIVX account."
        } catch {
            status = "Step sync pending: \(error.localizedDescription). Open the app later to retry."
        }
    }

    /// Store the iPhone-only CoreMotion total separately from Apple's
    /// aggregated HealthKit total. These two sources must never overwrite or
    /// be added together in daily_logs.
    func syncMotionDailySteps(date: Date, steps: Int, distanceMeters: Double?, retryAfterRefresh: Bool = true) async {
        guard steps >= 0 else { return }
        do {
            guard let token = accessToken else { throw ClientError.notSignedIn }
            var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/sync_motion_daily_steps"))
            request.httpMethod = "POST"
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = TimeZone.current
            day.dateFormat = "yyyy-MM-dd"
            let updated = ISO8601DateFormatter().string(from: Date())
            var body: [String: Any] = [
                "p_log_date": day.string(from: date),
                "p_steps": steps,
                "p_updated_at": updated
            ]
            if let distanceMeters, distanceMeters.isFinite, distanceMeters >= 0 {
                body["p_distance_m"] = distanceMeters
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
            if http.statusCode == 401 && retryAfterRefresh {
                try await refreshSession()
                await syncMotionDailySteps(date: date, steps: steps, distanceMeters: distanceMeters, retryAfterRefresh: false)
                return
            }
            guard (200..<300).contains(http.statusCode) else { throw Self.serverError(data) }
            status = "iPhone motion steps synced separately from Apple Health."
        } catch {
            status = "Motion sync pending: " + error.localizedDescription
        }
    }

    private func performStepSync(date: Date, steps: Int, retryAfterRefresh: Bool) async throws {
        guard let token = accessToken else { throw ClientError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/sync_healthkit_daily_steps"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "p_log_date": formatter.string(from: date),
            "p_steps": steps,
            "p_updated_at": ISO8601DateFormatter().string(from: Date())
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if http.statusCode == 401, retryAfterRefresh {
            try await refreshSession()
            try await performStepSync(date: date, steps: steps, retryAfterRefresh: false)
            return
        }
        guard (200..<300).contains(http.statusCode) else { throw Self.serverError(data) }
    }

    func syncActivitySession(id: UUID, activity: String, startedAt: Date, finishedAt: Date, steps: Int, retryAfterRefresh: Bool = true) async {
        guard steps >= 0, finishedAt >= startedAt else { return }
        do {
            guard let token = accessToken else { throw ClientError.notSignedIn }
            var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/sync_activity_session_steps"))
            request.httpMethod = "POST"
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "p_session_id": id.uuidString,
                "p_activity": activity,
                "p_started_at": formatter.string(from: startedAt),
                "p_finished_at": formatter.string(from: finishedAt),
                "p_steps": steps
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
            if http.statusCode == 401 && retryAfterRefresh {
                try await refreshSession()
                await syncActivitySession(id: id, activity: activity, startedAt: startedAt, finishedAt: finishedAt, steps: steps, retryAfterRefresh: false)
                return
            }
            guard (200..<300).contains(http.statusCode) else { throw Self.serverError(data) }
            status = "Activity session synced to your GATIVX account."
        } catch {
            status = "Activity saved on this iPhone; cloud sync pending: " + error.localizedDescription
        }
    }
    func syncActivitySessionRoute(id: UUID, startedAt: Date, finishedAt: Date, points: [GATIVXRoutePoint], retryAfterRefresh: Bool = true) async {
        guard !points.isEmpty, points.count <= 20_000 else { return }
        do {
            guard let token = accessToken else { throw ClientError.notSignedIn }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            // GPS route persistence is independent of step-session persistence.
            // sync_activity_session_route only UPDATEs activity_sessions and fails
            // when pedometer steps were unavailable, preventing the walk_sessions
            // write below. The walk RPC is the canonical route-history writer.
            // Mirror native GPS routes into walk_sessions, which the web dashboard reads.
            let coordinates = points.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            var distanceMeters = 0.0
            if coordinates.count > 1 {
                for index in 1..<coordinates.count {
                    distanceMeters += coordinates[index - 1].distance(from: coordinates[index])
                }
            }
            var walkRequest = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/sync_walk_session_route"))
            walkRequest.httpMethod = "POST"
            walkRequest.setValue(publishableKey, forHTTPHeaderField: "apikey")
            walkRequest.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            walkRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            walkRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "p_session_id": id.uuidString,
                "p_started_at": formatter.string(from: startedAt),
                "p_finished_at": formatter.string(from: finishedAt),
                "p_duration_seconds": max(0, min(86400, Int(finishedAt.timeIntervalSince(startedAt)))),
                "p_distance_m": distanceMeters,
                "p_route_points": points.map { $0.cloudValue }
            ])
            let (walkData, walkResponse) = try await URLSession.shared.data(for: walkRequest)
            guard let walkHTTP = walkResponse as? HTTPURLResponse else { throw ClientError.invalidResponse }
            if walkHTTP.statusCode == 401 && retryAfterRefresh {
                try await refreshSession()
                await syncActivitySessionRoute(id: id, startedAt: startedAt, finishedAt: finishedAt, points: points, retryAfterRefresh: false)
                return
            }
            guard (200..<300).contains(walkHTTP.statusCode) else { throw Self.serverError(walkData) }
            status = "GPS route synced to GATIVX walking history."
        } catch {
            status = "GPS route saved on this iPhone; cloud sync pending: " + error.localizedDescription
        }
    }

    private func refreshSession() async throws {
        guard let refreshToken else { throw ClientError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/v1/token").appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")]))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            clearSession()
            throw Self.serverError(data)
        }
        let session = try JSONDecoder().decode(AuthSession.self, from: data)
        accessToken = session.accessToken
        self.refreshToken = session.refreshToken
        saveSession(session)
    }

    func signOut() {
        clearSession()
        status = "Signed out."
    }

    private func saveSession(_ session: AuthSession) {
        let data = try? JSONEncoder().encode(session)
        guard let data else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: sessionStore]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func readSession() -> AuthSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: sessionStore, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    private func clearSession() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: sessionStore]
        SecItemDelete(query as CFDictionary)
        accessToken = nil
        refreshToken = nil
        isSignedIn = false
    }

    private static func serverError(_ data: Data) -> Error {
        let body = String(data: data, encoding: .utf8) ?? "Unknown server response"
        return ClientError.server(body)
    }

    private enum ClientError: LocalizedError {
        case notSignedIn, invalidResponse, server(String)
        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Please sign in first."
            case .invalidResponse: return "The server returned an invalid response."
            case .server(let message): return message
            }
        }
    }
}

private struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
