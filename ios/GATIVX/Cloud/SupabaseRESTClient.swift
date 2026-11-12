import Foundation
import CoreLocation
import Security
import Combine

private enum PendingHealthSyncKind: String, Codable {
    case healthSteps
    case activeEnergy
    case motionSteps
}

private struct PendingHealthSync: Codable, Identifiable {
    let ownerID: String
    let kind: PendingHealthSyncKind
    let localDay: String
    var steps: Int?
    var activeEnergyKcal: Int?
    var distanceMeters: Double?
    let queuedAt: Date
    var id: String { ownerID + ":" + kind.rawValue + ":" + localDay }
}

@MainActor
final class SupabaseRESTClient: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var status = "Sign in with your existing GATIVX web-app account."
    @Published private(set) var pendingHealthSyncCount = 0

    private let baseURL = URL(string: "https://crarbbsvcczwmtvxyrxo.supabase.co")!
    // Supabase publishable key is a client-side key. Never place a service-role key in the app.
    private let publishableKey = "sb_publishable_XAGRFtrWrFqJ-JSfXh2WbRQ_jCcPnr-6"
    private let sessionStore = "com.paramitsolutions.gativx.session"
    private let healthOutboxKey = "com.paramitsolutions.gativx.health-sync-outbox.v1"
    private var accessToken: String?
    private var refreshToken: String?

    init() {
        if let saved = readSession() {
            accessToken = saved.accessToken
            refreshToken = saved.refreshToken
            isSignedIn = accessToken != nil
        }
        pendingHealthSyncCount = loadHealthOutbox().filter { $0.ownerID == currentUserID }.count
    }


    private var currentUserID: String? {
        guard let accessToken else { return nil }
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String, !subject.isEmpty else { return nil }
        return subject
    }

    private func localDayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dateForLocalDay(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func loadHealthOutbox() -> [PendingHealthSync] {
        guard let data = UserDefaults.standard.data(forKey: healthOutboxKey),
              let items = try? JSONDecoder().decode([PendingHealthSync].self, from: data) else { return [] }
        return items
    }

    private func saveHealthOutbox(_ items: [PendingHealthSync]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: healthOutboxKey)
            pendingHealthSyncCount = items.filter { $0.ownerID == currentUserID }.count
        }
    }

    private func enqueueHealthSync(_ item: PendingHealthSync) {
        var items = loadHealthOutbox()
        items.removeAll { $0.id == item.id }
        items.append(item)
        items.sort { $0.queuedAt < $1.queuedAt }
        saveHealthOutbox(items)
    }

    private func acknowledgeHealthSync(_ id: String) {
        saveHealthOutbox(loadHealthOutbox().filter { $0.id != id })
    }

    /// Retry durable daily sensor writes after sign-in, foregrounding, or a
    /// previous network failure. Each successful server acknowledgement is
    /// removed independently; failed items remain on this device.
    func retryPendingHealthSyncs() async {
        guard isSignedIn, let ownerID = currentUserID else { return }
        let pending = loadHealthOutbox().filter { $0.ownerID == ownerID }
        for item in pending {
            guard let day = dateForLocalDay(item.localDay) else {
                acknowledgeHealthSync(item.id)
                continue
            }
            switch item.kind {
            case .healthSteps:
                if let steps = item.steps { await syncSteps(date: day, steps: steps) }
            case .activeEnergy:
                if let kcal = item.activeEnergyKcal { await syncActiveEnergy(date: day, kilocalories: kcal) }
            case .motionSteps:
                if let steps = item.steps {
                    _ = await syncMotionDailySteps(date: day, steps: steps, distanceMeters: item.distanceMeters)
                }
            }
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
            await retryPendingHealthSyncs()
        } catch {
            status = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func syncSteps(date: Date, steps: Int) async {
        guard steps >= 0 else { return }
        guard let ownerID = currentUserID else { status = "Step sync pending until a valid account session is available."; return }
        let item = PendingHealthSync(ownerID: ownerID, kind: .healthSteps, localDay: localDayString(date), steps: steps, activeEnergyKcal: nil, distanceMeters: nil, queuedAt: Date())
        enqueueHealthSync(item)
        do {
            try await performStepSync(date: date, steps: steps, retryAfterRefresh: true)
            acknowledgeHealthSync(item.id)
            status = "Apple Health steps synced to your GATIVX account."
        } catch {
            status = "Step sync pending: \(error.localizedDescription). Open the app later to retry."
        }
    }

    func syncActiveEnergy(date: Date, kilocalories: Int, retryAfterRefresh: Bool = true) async {
        guard kilocalories >= 0 else { return }
        guard let ownerID = currentUserID else { status = "Active-energy sync pending until a valid account session is available."; return }
        let item = PendingHealthSync(ownerID: ownerID, kind: .activeEnergy, localDay: localDayString(date), steps: nil, activeEnergyKcal: kilocalories, distanceMeters: nil, queuedAt: Date())
        enqueueHealthSync(item)
        do {
            guard let token = accessToken else { throw ClientError.notSignedIn }
            var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/sync_healthkit_daily_energy"))
            request.httpMethod = "POST"
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = TimeZone.current
            day.dateFormat = "yyyy-MM-dd"
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "p_log_date": day.string(from: date),
                "p_active_energy_kcal": kilocalories,
                "p_updated_at": ISO8601DateFormatter().string(from: Date())
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
            if http.statusCode == 401 && retryAfterRefresh {
                try await refreshSession()
                await syncActiveEnergy(date: date, kilocalories: kilocalories, retryAfterRefresh: false)
                return
            }
            guard (200..<300).contains(http.statusCode) else { throw Self.serverError(data) }
            acknowledgeHealthSync(item.id)
            status = "Apple Health active calories synced to your GATIVX account."
        } catch {
            status = "Active calorie sync pending: " + error.localizedDescription + ". Open the app later to retry."
        }
    }

    /// Store the iPhone-only CoreMotion total separately from Apple's
    /// aggregated HealthKit total. These two sources must never overwrite or
    /// be added together in daily_logs.
    @discardableResult
    func syncMotionDailySteps(date: Date, steps: Int, distanceMeters: Double?, retryAfterRefresh: Bool = true) async -> Bool {
        guard steps >= 0 else { return false }
        guard let ownerID = currentUserID else { status = "Motion sync pending until a valid account session is available."; return false }
        let item = PendingHealthSync(ownerID: ownerID, kind: .motionSteps, localDay: localDayString(date), steps: steps, activeEnergyKcal: nil, distanceMeters: distanceMeters, queuedAt: Date())
        enqueueHealthSync(item)
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
                return await syncMotionDailySteps(date: date, steps: steps, distanceMeters: distanceMeters, retryAfterRefresh: false)
            }
            guard (200..<300).contains(http.statusCode) else { throw Self.serverError(data) }
            acknowledgeHealthSync(item.id)
            status = "iPhone motion steps synced separately from Apple Health."
            return true
        } catch {
            status = "Motion sync pending: " + error.localizedDescription
            return false
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
    func syncActivitySessionRoute(id: UUID, startedAt: Date, finishedAt: Date, steps: Int?, points: [GATIVXRoutePoint], retryAfterRefresh: Bool = true) async {
        guard !points.isEmpty else { return }
        guard steps == nil || (steps! >= 0 && steps! <= 200_000) else {
            status = "GPS route saved on this iPhone; cloud sync is pending because the session step count is invalid."
            return
        }
        // The database RPC caps payloads at 20,000 points. Preserve the full
        // local recording, but uniformly thin oversized cloud payloads while
        // retaining both endpoints and the overall route shape.
        let cloudPoints: [GATIVXRoutePoint]
        if points.count > 20_000 {
            cloudPoints = (0..<20_000).map { index in
                points[index * (points.count - 1) / 19_999]
            }
        } else {
            cloudPoints = points
        }
        do {
            guard let token = accessToken else { throw ClientError.notSignedIn }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            // GPS route persistence is independent of step-session persistence.
            // sync_activity_session_route only UPDATEs activity_sessions and fails
            // when pedometer steps were unavailable, preventing the walk_sessions
            // write below. The walk RPC is the canonical route-history writer.
            // Mirror native GPS routes into walk_sessions, which the web dashboard reads.
            let coordinates = cloudPoints.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            var distanceMeters = 0.0
            if coordinates.count > 1 {
                for index in 1..<coordinates.count {
                    // A breakBefore point begins a new segment after a GPS outage,
                    // invalid fix or implausible jump. Never count across that gap.
                    if cloudPoints[index].breakBefore { continue }
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
                "p_steps": steps.map { $0 as Any } ?? NSNull(),
                "p_route_points": cloudPoints.map { $0.cloudValue }
            ])
            let (walkData, walkResponse) = try await URLSession.shared.data(for: walkRequest)
            guard let walkHTTP = walkResponse as? HTTPURLResponse else { throw ClientError.invalidResponse }
            if walkHTTP.statusCode == 401 && retryAfterRefresh {
                try await refreshSession()
                await syncActivitySessionRoute(id: id, startedAt: startedAt, finishedAt: finishedAt, steps: steps, points: points, retryAfterRefresh: false)
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
