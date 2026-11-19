import Foundation
import CoreLocation
import Security
import Combine

enum PendingHealthSyncKind: String, Codable {
    case healthSteps
    case activeEnergy
    case motionSteps
}

struct PendingHealthSync: Codable, Identifiable {
    let ownerID: String
    let revisionID: UUID
    let kind: PendingHealthSyncKind
    let localDay: String
    var steps: Int?
    var activeEnergyKcal: Int?
    var distanceMeters: Double?
    let queuedAt: Date
    var id: String { ownerID + ":" + kind.rawValue + ":" + localDay }
}


struct PendingActivitySession: Codable, Identifiable, Equatable {
    let ownerID: String
    let revisionID: UUID
    let record: ActivitySessionRecord
    let queuedAt: Date
    var id: String { ownerID + ":" + record.id.uuidString }
}

/// Pure revision-aware reconciliation for completed activity uploads.
/// A crash-recovered session can improve an already-pending payload without
/// allowing an older in-flight acknowledgement to remove the newer revision.
enum ActivitySessionOutboxQueue {
    static func upserting(
        _ record: ActivitySessionRecord,
        ownerID: String,
        into items: [PendingActivitySession],
        revisionID: UUID = UUID(),
        queuedAt: Date = Date()
    ) -> [PendingActivitySession] {
        var updated = items
        if let index = updated.firstIndex(where: { $0.ownerID == ownerID && $0.record.id == record.id }) {
            let existing = updated[index]
            let merged = existing.record.mergingRecovery(record)
            guard merged != existing.record else { return items }
            updated[index] = PendingActivitySession(
                ownerID: existing.ownerID,
                revisionID: revisionID,
                record: merged,
                queuedAt: existing.queuedAt
            )
        } else {
            updated.append(PendingActivitySession(
                ownerID: ownerID,
                revisionID: revisionID,
                record: record,
                queuedAt: queuedAt
            ))
        }
        return updated
    }

    static func acknowledging(
        _ item: PendingActivitySession,
        from items: [PendingActivitySession]
    ) -> [PendingActivitySession] {
        items.filter { !($0.id == item.id && $0.revisionID == item.revisionID) }
    }
}

@MainActor
final class SupabaseRESTClient: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var status = "Sign in with your existing GATIVX web-app account."
    @Published private(set) var pendingHealthSyncCount = 0
    @Published private(set) var isHealthOutboxReadable = true
    @Published private(set) var pendingActivitySyncCount = 0
    @Published private(set) var isActivityOutboxReadable = true

    private let baseURL = URL(string: "https://crarbbsvcczwmtvxyrxo.supabase.co")!
    // Supabase publishable key is a client-side key. Never place a service-role key in the app.
    private let publishableKey = "sb_publishable_XAGRFtrWrFqJ-SfXh2WbRQ_jCcPnr-6"
    private let sessionStore = "com.paramitsolutions.gativx.session"
    private let healthOutbox = HealthSyncOutboxStore()
    private let activityOutboxKey = "com.paramitsolutions.gativx.activity-sync-outbox.v1"
    private var accessToken: String?
    private var refreshToken: String?
    private var isRetryingHealthOutbox = false
    private var isRetryingActivityOutbox = false

    init() {
        if let saved = readSession() {
            accessToken = saved.accessToken
            refreshToken = saved.refreshToken
            isSignedIn = accessToken != nil
        }
        if let items = loadHealthOutbox() {
            pendingHealthSyncCount = items.filter { $0.ownerID == currentUserID }.count
        }
        if let items = loadActivityOutbox() {
            pendingActivitySyncCount = items.filter { $0.ownerID == currentUserID }.count
        }
    }


    var authenticatedUserID: String? { currentUserID }

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

    private func loadHealthOutbox() -> [PendingHealthSync]? {
        do {
            let items = try healthOutbox.load()
            isHealthOutboxReadable = true
            return items
        } catch {
            // Never interpret unreadable queued sensor records as an empty queue or
            // present the pending count as zero: the real count is unknown.
            isHealthOutboxReadable = false
            status = "Sensor sync paused: the on-device retry queue could not be read. Pending count is unknown; original data was left untouched. Contact support before clearing app data."
            return nil
        }
    }

    private func saveHealthOutbox(_ items: [PendingHealthSync]) -> Bool {
        do {
            try healthOutbox.save(items)
            isHealthOutboxReadable = true
            pendingHealthSyncCount = items.filter { $0.ownerID == currentUserID }.count
            return true
        } catch {
            isHealthOutboxReadable = false
            status = "Sensor sync queue could not be saved and verified: " + error.localizedDescription
            return false
        }
    }

    private func enqueueHealthSync(_ item: PendingHealthSync) -> Bool {
        do {
            let items = try healthOutbox.enqueue(item)
            isHealthOutboxReadable = true
            pendingHealthSyncCount = items.filter { $0.ownerID == currentUserID }.count
            return true
        } catch {
            isHealthOutboxReadable = false
            status = "Sensor sync queue could not be safely updated: " + error.localizedDescription
            return false
        }
    }

    private func acknowledgeHealthSync(_ item: PendingHealthSync) -> Bool {
        // An older in-flight request must not remove a newer reading for the
        // same member/day that was queued while the request was awaiting I/O.
        do {
            let remaining = try healthOutbox.acknowledge(item)
            isHealthOutboxReadable = true
            pendingHealthSyncCount = remaining.filter { $0.ownerID == currentUserID }.count
            return true
        } catch {
            isHealthOutboxReadable = false
            status = "Sensor sync acknowledgement could not be verified. Original queue data was preserved."
            return false
        }
    }

    private func loadActivityOutbox() -> [PendingActivitySession]? {
        guard let data = UserDefaults.standard.data(forKey: activityOutboxKey) else {
            isActivityOutboxReadable = true
            return []
        }
        do {
            let items = try JSONDecoder().decode([PendingActivitySession].self, from: data)
            isActivityOutboxReadable = true
            return items
        } catch {
            isActivityOutboxReadable = false
            status = "Activity cloud sync paused: the on-device retry queue could not be read. Original data was preserved; pending count is unknown."
            return nil
        }
    }

    private func saveActivityOutbox(_ items: [PendingActivitySession]) -> Bool {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: activityOutboxKey)
            guard let saved = UserDefaults.standard.data(forKey: activityOutboxKey),
                  let verified = try? JSONDecoder().decode([PendingActivitySession].self, from: saved),
                  verified == items else {
                status = "Activity sync queue could not be verified after saving. The activity remains saved locally."
                return false
            }
            pendingActivitySyncCount = items.filter { $0.ownerID == currentUserID }.count
            return true
        } catch {
            status = "Activity sync queue could not be encoded: " + error.localizedDescription
            return false
        }
    }

    /// Persist a completed local activity before attempting any cloud request.
    func enqueueActivitySession(_ record: ActivitySessionRecord) {
        guard let ownerID = currentUserID else {
            status = "Activity saved on this iPhone. Sign in to queue its cloud upload."
            return
        }
        guard record.ownerID == ownerID else {
            status = "Activity remains local because its recording account cannot be verified for this signed-in member."
            return
        }
        guard let items = loadActivityOutbox() else { return }
        let updated = ActivitySessionOutboxQueue.upserting(record, ownerID: ownerID, into: items)
        guard updated != items else { return }
        guard saveActivityOutbox(updated) else { return }
        status = "Activity saved locally and safely queued for cloud sync."
    }

    /// Retry each activity's step and route writes independently. Remove the
    /// queue item only after every deliverable present in the local record is acknowledged.
    func retryPendingActivitySessions() async {
        guard !isRetryingActivityOutbox, isSignedIn, let ownerID = currentUserID else { return }
        guard let pending = loadActivityOutbox() else { return }
        isRetryingActivityOutbox = true
        defer { isRetryingActivityOutbox = false }
        for item in pending where item.ownerID == ownerID {
            let record = item.record
            guard record.steps != nil || !(record.routePoints?.isEmpty ?? true) else {
                status = "Activity cloud sync paused: a queued session has no verified step count or GPS route. The original record was retained."
                continue
            }
            var allAcknowledged = true
            if let steps = record.steps {
                allAcknowledged = await syncActivitySession(id: record.id, activity: record.activity, startedAt: record.startedAt, finishedAt: record.finishedAt, steps: steps) && allAcknowledged
            }
            if let points = record.routePoints, !points.isEmpty {
                allAcknowledged = await syncActivitySessionRoute(id: record.id, startedAt: record.startedAt, finishedAt: record.finishedAt, steps: record.steps, points: points) && allAcknowledged
            }
            guard allAcknowledged else { continue }
            guard let current = loadActivityOutbox() else { return }
            _ = saveActivityOutbox(ActivitySessionOutboxQueue.acknowledging(item, from: current))
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
            pendingHealthSyncCount = (loadHealthOutbox() ?? []).filter { $0.ownerID == currentUserID }.count
            status = "Signed in. Your existing cloud records can be shared with GATIVX."
            await retryPendingHealthSyncs()
            await retryPendingActivitySessions()
        } catch {
            status = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    /// Create a new GATIVX account through Supabase Auth. If email confirmation
    /// is enabled, Supabase returns a user without a session; the member must
    /// verify the email and then sign in normally.
    func signUp(email: String, password: String) async {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/v1/signup"))
            request.httpMethod = "POST"
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw Self.serverError(data)
            }
            if let session = try? JSONDecoder().decode(AuthSession.self, from: data) {
                accessToken = session.accessToken
                refreshToken = session.refreshToken
                saveSession(session)
                isSignedIn = true
                if let items = loadHealthOutbox() {
                    pendingHealthSyncCount = items.filter { $0.ownerID == currentUserID }.count
                }
                status = "Account created and signed in."
                await retryPendingHealthSyncs()
                await retryPendingActivitySessions()
            } else {
                status = "Account request accepted. Check your email to verify the account, then sign in."
            }
        } catch {
            status = "Account creation failed: \(error.localizedDescription)"
        }
    }

    /// Send Supabase's password-recovery email. The app never handles or stores
    /// a password-reset token; the secure recovery flow is completed by email.
    func sendPasswordReset(email: String) async {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/v1/recover"))
            request.httpMethod = "POST"
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw Self.serverError(data)
            }
            status = "If this email belongs to a GATIVX account, password-recovery instructions have been sent."
        } catch {
            status = "Password recovery could not be requested: \(error.localizedDescription)"
        }
    }

    func syncSteps(date: Date, steps: Int, pendingItem: PendingHealthSync? = nil) async {
        guard steps >= 0 else { return }
        guard let ownerID = currentUserID else { status = "Step sync pending until a valid account session is available."; return }
        let item = pendingItem ?? PendingHealthSync(ownerID: ownerID, revisionID: UUID(), kind: .healthSteps, localDay: localDayString(date), steps: steps, activeEnergyKcal: nil, distanceMeters: nil, queuedAt: Date())
        if pendingItem == nil && !enqueueHealthSync(item) {
            status = "Step sync paused: the on-device retry queue could not be verified, so no network request was sent."
            return
        }
        do {
            try await performStepSync(date: date, steps: steps, retryAfterRefresh: true)
            guard acknowledgeHealthSync(item) else {
                status = "Apple Health steps reached the server, but local queue acknowledgement could not be verified. A safe retry remains possible."
                return
            }
            status = "Apple Health steps synced to your GATIVX account."
        } catch {
            status = "Step sync pending: \(error.localizedDescription). Open the app later to retry."
        }
    }

    func syncActiveEnergy(date: Date, kilocalories: Int, retryAfterRefresh: Bool = true, pendingItem: PendingHealthSync? = nil) async {
        guard kilocalories >= 0 else { return }
        guard let ownerID = currentUserID else { status = "Active-energy sync pending until a valid account session is available."; return }
        let item = pendingItem ?? PendingHealthSync(ownerID: ownerID, revisionID: UUID(), kind: .activeEnergy, localDay: localDayString(date), steps: nil, activeEnergyKcal: kilocalories, distanceMeters: nil, queuedAt: Date())
        if pendingItem == nil && !enqueueHealthSync(item) {
            status = "Active-energy sync paused: the on-device retry queue could not be verified, so no network request was sent."
            return
        }
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
                await syncActiveEnergy(date: date, kilocalories: kilocalories, retryAfterRefresh: false, pendingItem: item)
                return
            }
            guard (200..<300).contains(http.statusCode) else { throw Self.serverError(data) }
            guard acknowledgeHealthSync(item) else {
                status = "Apple Health active calories reached the server, but local queue acknowledgement could not be verified. A safe retry remains possible."
                return
            }
            status = "Apple Health active calories synced to your GATIVX account."
        } catch {
            status = "Active calorie sync pending: " + error.localizedDescription + ". Open the app later to retry."
        }
    }

    /// Store the iPhone-only CoreMotion total separately from Apple's
    /// aggregated HealthKit total. These two sources must never overwrite or
    /// be added together in daily_logs.
    @discardableResult
    func syncMotionDailySteps(date: Date, steps: Int, distanceMeters: Double?, retryAfterRefresh: Bool = true, pendingItem: PendingHealthSync? = nil) async -> Bool {
        guard steps >= 0 else { return false }
        guard let ownerID = currentUserID else { status = "Motion sync pending until a valid account session is available."; return false }
        let item = pendingItem ?? PendingHealthSync(ownerID: ownerID, revisionID: UUID(), kind: .motionSteps, localDay: localDayString(date), steps: steps, activeEnergyKcal: nil, distanceMeters: distanceMeters, queuedAt: Date())
        if pendingItem == nil && !enqueueHealthSync(item) {
            status = "Motion sync paused: the on-device retry queue could not be verified, so no network request was sent."
            return false
        }
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
                return await syncMotionDailySteps(date: date, steps: steps, distanceMeters: distanceMeters, retryAfterRefresh: false, pendingItem: item)
            }
            guard (200..<300).contains(http.statusCode) else { throw Self.serverError(data) }
            guard acknowledgeHealthSync(item) else {
                status = "iPhone motion steps reached the server, but local queue acknowledgement could not be verified. A safe retry remains possible."
                return false
            }
            status = "iPhone motion steps synced separately from Apple Health."
            return true
        } catch {
            status = "Motion sync pending: " + error.localizedDescription
            return false
        }
    }

    /// Drain the durable sensor outbox for the currently authenticated member.
    /// Each item retains its original revision through network/token retries; the
    /// store only acknowledges that exact revision after a successful server write.
    func retryPendingHealthSyncs() async {
        guard !isRetryingHealthOutbox, isSignedIn, let ownerID = currentUserID else { return }
        guard let pending = loadHealthOutbox() else { return }

        isRetryingHealthOutbox = true
        defer { isRetryingHealthOutbox = false }

        for item in pending where item.ownerID == ownerID {
            guard let date = HealthSyncOutboxStore.dateForLocalDay(item.localDay) else {
                status = "Sensor sync paused: a queued local date is invalid. The original queue item was retained for recovery."
                continue
            }

            switch item.kind {
            case .healthSteps:
                guard let steps = item.steps, steps >= 0 else {
                    status = "Apple Health step sync paused: the queued measured value is unavailable. The original queue item was retained."
                    continue
                }
                await syncSteps(date: date, steps: steps, pendingItem: item)

            case .activeEnergy:
                guard let kilocalories = item.activeEnergyKcal, kilocalories >= 0 else {
                    status = "Active-energy sync paused: the queued measured value is unavailable. The original queue item was retained."
                    continue
                }
                await syncActiveEnergy(date: date, kilocalories: kilocalories,
                                       retryAfterRefresh: true, pendingItem: item)

            case .motionSteps:
                guard let steps = item.steps, steps >= 0 else {
                    status = "iPhone motion sync paused: the queued measured value is unavailable. The original queue item was retained."
                    continue
                }
                _ = await syncMotionDailySteps(date: date, steps: steps,
                                               distanceMeters: item.distanceMeters,
                                               retryAfterRefresh: true, pendingItem: item)
            }
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

    func syncActivitySession(id: UUID, activity: String, startedAt: Date, finishedAt: Date, steps: Int, retryAfterRefresh: Bool = true) async -> Bool {
        guard steps >= 0, finishedAt >= startedAt else { return false }
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
                return await syncActivitySession(id: id, activity: activity, startedAt: startedAt, finishedAt: finishedAt, steps: steps, retryAfterRefresh: false)
            }
            guard (200..<300).contains(http.statusCode) else { throw Self.serverError(data) }
            status = "Activity session synced to your GATIVX account."
            return true
        } catch {
            status = "Activity saved on this iPhone; cloud sync pending: " + error.localizedDescription
            return false
        }
    }
    func syncActivitySessionRoute(id: UUID, startedAt: Date, finishedAt: Date, steps: Int?, points: [GATIVXRoutePoint], retryAfterRefresh: Bool = true) async -> Bool {
        guard !points.isEmpty else { return false }
        guard steps == nil || (steps! >= 0 && steps! <= 200_000) else {
            status = "GPS route saved on this iPhone; cloud sync is pending because the session step count is invalid."
            return false
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
                return await syncActivitySessionRoute(id: id, startedAt: startedAt, finishedAt: finishedAt, steps: steps, points: points, retryAfterRefresh: false)
            }
            guard (200..<300).contains(walkHTTP.statusCode) else { throw Self.serverError(walkData) }
            status = "GPS route synced to GATIVX walking history."
            return true
        } catch {
            status = "GPS route saved on this iPhone; cloud sync pending: " + error.localizedDescription
            return false
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
        pendingHealthSyncCount = 0
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
