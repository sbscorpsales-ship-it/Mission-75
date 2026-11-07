import Foundation
import Combine
@preconcurrency import Supabase

@MainActor
final class CloudSyncStore: ObservableObject {
    @Published private(set) var hasResolvedAuth = false
    @Published private(set) var isSignedIn = false
    @Published private(set) var isOfflineMode = UserDefaults.standard.bool(forKey: "walkon.offline-mode")
    @Published private(set) var email: String?
    @Published private(set) var status = "Checking secure cloud session"

    #if targetEnvironment(simulator)
    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://crarbbsvcczwmtvxyrxo.supabase.co")!,
        supabaseKey: "sb_publishable_XAGRFtrWrFqJ-SfXh2WbRQ_jCcPnr-6",
        options: SupabaseClientOptions(
            auth: .init(storage: SimulatorAuthStorage())
        )
    )
    #else
    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://crarbbsvcczwmtvxyrxo.supabase.co")!,
        supabaseKey: "sb_publishable_XAGRFtrWrFqJ-SfXh2WbRQ_jCcPnr-6"
    )
    #endif
    private var authEventsTask: Task<Void, Never>?
    private var isSyncingWalks = false

    init() {
        authEventsTask = Task { [weak self] in
            guard let self else { return }
            let events = self.client.auth.authStateChanges
            for await (_, session) in events {
                self.hasResolvedAuth = true
                self.isSignedIn = session != nil
                if session != nil {
                    self.isOfflineMode = false
                    UserDefaults.standard.set(false, forKey: "walkon.offline-mode")
                }
                self.email = session?.user.email
                if session != nil {
                    self.status = "Cloud account connected"
                } else if self.isOfflineMode {
                    self.status = "Offline mode — walks stay on this iPhone"
                } else {
                    self.status = "Sign in to back up steps and walks"
                }
            }
        }
    }

    deinit {
        authEventsTask?.cancel()
    }

    func sendSignInCode(to address: String) async throws {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), normalized.contains(".") else {
            throw CloudSyncError.invalidEmail
        }
        try await client.auth.signInWithOTP(
            email: normalized,
            shouldCreateUser: false
        )
        status = "A sign-in code was sent to \(normalized)"
    }

    func verifySignInCode(email address: String, code: String) async throws {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count == 6, token.allSatisfy(\.isNumber) else {
            throw CloudSyncError.invalidCode
        }
        let response = try await client.auth.verifyOTP(
            email: normalized,
            token: token,
            type: .email
        )
        isSignedIn = true
        isOfflineMode = false
        UserDefaults.standard.set(false, forKey: "walkon.offline-mode")
        hasResolvedAuth = true
        email = response.user.email
        status = "Signed in — cloud backup is ready"
    }

    func continueOffline() {
        hasResolvedAuth = true
        isOfflineMode = true
        UserDefaults.standard.set(true, forKey: "walkon.offline-mode")
        status = "Offline mode — walks stay on this iPhone"
    }

    func connectAccount() {
        isOfflineMode = false
        UserDefaults.standard.set(false, forKey: "walkon.offline-mode")
        status = "Sign in to enable cloud backup"
    }

    func signOut() async throws {
        try await client.auth.signOut()
        isSignedIn = false
        isOfflineMode = true
        UserDefaults.standard.set(true, forKey: "walkon.offline-mode")
        email = nil
        status = "Signed out — local-only mode is active"
    }

    func syncHealthKitSteps(_ steps: Int, measuredAt: Date = Date()) async {
        guard isSignedIn else { return }
        guard (0...200_000).contains(steps) else {
            status = "Apple Health step total is outside the supported range; not uploaded"
            return
        }
        let params = HealthKitStepSyncParams(
            p_log_date: localDateString(measuredAt),
            p_steps: steps,
            p_updated_at: iso8601String(measuredAt)
        )
        do {
            try await client.rpc("sync_healthkit_daily_steps", params: params).execute()
            status = "Apple Health steps backed up to your account"
        } catch {
            status = "Steps remain on this iPhone; cloud retry pending"
        }
    }

    func syncPendingWalks(from store: ActivityStore) async {
        guard isSignedIn, !isSyncingWalks else { return }
        isSyncingWalks = true
        defer { isSyncingWalks = false }
        let pending = store.sessions.filter { $0.cloudSyncedAt == nil }
        guard !pending.isEmpty else { return }
        var syncedCount = 0
        for session in pending {
            do {
                let route = session.route.map {
                    CloudRoutePoint(
                        latitude: $0.latitude,
                        longitude: $0.longitude,
                        timestamp: iso8601String($0.timestamp),
                        horizontal_accuracy: $0.horizontalAccuracy
                    )
                }
                let params = WalkSessionSyncParams(
                    p_session_id: session.id.uuidString,
                    p_started_at: iso8601String(session.startedAt),
                    p_finished_at: iso8601String(session.endedAt),
                    p_duration_seconds: Int(session.duration.rounded()),
                    p_distance_m: session.distanceMeters,
                    p_route_points: route
                )
                try await client.rpc("sync_walk_session_route", params: params).execute()
                store.markCloudSynced(session.id)
                syncedCount += 1
            } catch {
                status = "Walk saved locally; cloud upload will retry"
                return
            }
        }
        status = syncedCount == 1
            ? "Walk backed up to your account"
            : "\(syncedCount) walks backed up to your account"
    }

    private func localDateString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct HealthKitStepSyncParams: Encodable, Sendable {
    let p_log_date: String
    let p_steps: Int
    let p_updated_at: String
}

private struct CloudRoutePoint: Encodable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: String
    let horizontal_accuracy: Double
}

private struct WalkSessionSyncParams: Encodable, Sendable {
    let p_session_id: String
    let p_started_at: String
    let p_finished_at: String
    let p_duration_seconds: Int
    let p_distance_m: Double
    let p_route_points: [CloudRoutePoint]
}

enum CloudSyncError: LocalizedError {
    case invalidEmail
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Enter a valid email address."
        case .invalidCode:
            return "Enter the six-digit code from your email."
        }
    }
}


#if targetEnvironment(simulator)
private final class SimulatorAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
#endif
