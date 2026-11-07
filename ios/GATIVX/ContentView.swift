import SwiftUI
import CoreMotion

private struct ActivitySessionRecord: Codable { let id: UUID; let activity: String; let startedAt: Date; let finishedAt: Date; let steps: Int?; let routePoints: [GATIVXRoutePoint]? }

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var health = HealthKitManager()
    @StateObject private var cloud = SupabaseRESTClient()
    @StateObject private var routeRecorder = GPSRouteRecorder()
    @State private var email = ""
    @State private var password = ""
    @State private var pedometer = CMPedometer()
    @State private var livePedometer = CMPedometer()
    @State private var selectedActivity = "Walking"
    @State private var sessionSteps: Int?
    @State private var sessionStarted: Date?
    @State private var sessionStatus = "Start a session to count steps."
    @State private var liveMotionSteps: Int?
    @State private var liveMotionDistanceMeters: Double?
    @State private var lastMotionCloudSyncAt: Date?
    @State private var lastMotionCloudSteps: Int = -1

    /// Foreground live sensor feed. This is shown separately from HealthKit's
    /// deduplicated all-source daily total; never add the two together.
    private func startLiveMotionMonitor() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let start = Calendar.current.startOfDay(for: Date())
        livePedometer.stopUpdates()
        livePedometer.startUpdates(from: start) { data, error in
            DispatchQueue.main.async {
                guard error == nil, let data else { return }
                let steps = data.numberOfSteps.intValue
                let distance = data.distance?.doubleValue
                self.liveMotionSteps = steps
                self.liveMotionDistanceMeters = distance

                // Persist a separate iPhone-only observation. Throttle writes
                // to avoid sending every sensor callback to Supabase.
                let now = Date()
                let enoughTime = self.lastMotionCloudSyncAt.map { now.timeIntervalSince($0) >= 60 } ?? true
                let meaningfulChange = self.lastMotionCloudSteps < 0 || steps - self.lastMotionCloudSteps >= 100
                if self.cloud.isSignedIn && (enoughTime || meaningfulChange) {
                    self.lastMotionCloudSyncAt = now
                    self.lastMotionCloudSteps = steps
                    Task {
                        await self.cloud.syncMotionDailySteps(
                            date: now,
                            steps: steps,
                            distanceMeters: distance
                        )
                    }
                }
            }
        }
    }

    private func syncCurrentMotionSnapshotToCloud() {
        guard cloud.isSignedIn, let steps = liveMotionSteps else { return }
        Task {
            await cloud.syncMotionDailySteps(
                date: Date(),
                steps: steps,
                distanceMeters: liveMotionDistanceMeters
            )
        }
    }

    private func syncSavedActivitySessions() {
        guard cloud.isSignedIn else { return }
        let history = (try? JSONDecoder().decode([ActivitySessionRecord].self, from: UserDefaults.standard.data(forKey: "gativx.activitySessions.v1") ?? Data())) ?? []
        Task {
            for record in history {
                // Step data and GPS route are independent deliverables.
                // Missing pedometer data must never prevent route upload.
                if let steps = record.steps {
                    await cloud.syncActivitySession(
                        id: record.id,
                        activity: record.activity,
                        startedAt: record.startedAt,
                        finishedAt: record.finishedAt,
                        steps: steps
                    )
                }
                if let points = record.routePoints, !points.isEmpty {
                    await cloud.syncActivitySessionRoute(
                        id: record.id,
                        startedAt: record.startedAt,
                        finishedAt: record.finishedAt,
                        points: points
                    )
                }
            }
        }
    }
    private func startActivitySession() {
        guard CMPedometer.isStepCountingAvailable() else { sessionStatus = "Step counting is unavailable."; return }
        let start = Date(); sessionStarted = start; sessionSteps = 0
        routeRecorder.start(activity: selectedActivity)
        sessionStatus = "Counting steps for " + selectedActivity.lowercased() + "…"
        pedometer.startUpdates(from: start) { data, error in
            DispatchQueue.main.async {
                if let error { self.sessionStatus = "Motion step count unavailable: " + error.localizedDescription; return }
                self.sessionSteps = data?.numberOfSteps.intValue
            }
        }
    }
    private func finishActivitySession() {
        guard let start = sessionStarted else { return }
        let finishedAt = Date()
        let activity = selectedActivity
        pedometer.stopUpdates()
        routeRecorder.stop()
        let routePoints = routeRecorder.points
        // Query the complete interval after stopping live updates so the final
        // motion samples are included even if the last callback was delayed.
        pedometer.queryPedometerData(from: start, to: finishedAt) { data, _ in
            DispatchQueue.main.async {
                let finalSteps = data?.numberOfSteps.intValue ?? self.sessionSteps
                let record = ActivitySessionRecord(id: UUID(), activity: activity, startedAt: start, finishedAt: finishedAt, steps: finalSteps, routePoints: routePoints)
                var history = (try? JSONDecoder().decode([ActivitySessionRecord].self, from: UserDefaults.standard.data(forKey: "gativx.activitySessions.v1") ?? Data())) ?? []
                history.insert(record, at: 0)
                UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "gativx.activitySessions.v1")
                self.routeRecorder.clearDraft()
                self.sessionSteps = finalSteps
                self.sessionStatus = activity + " saved · " + (finalSteps?.formatted() ?? "step count unavailable") + " steps"
                self.sessionStarted = nil
                self.syncSavedActivitySessions()
            }
        }
    }

    /// Prefer HealthKit's deduplicated all-source total. Use the iPhone-only
    /// CoreMotion total only when HealthKit has no value; never add the sources.
    private var displayedDailySteps: Int? {
        health.todaySteps ?? liveMotionSteps
    }

    private var displayedStepSource: String {
        if health.todaySteps != nil { return "Apple Health · combined supported sources" }
        if liveMotionSteps != nil { return "iPhone motion · GATIVX fallback" }
        return "Waiting for step data"
    }

    private var stepProgress: Double {
        guard let steps = displayedDailySteps else { return 0 }
        return min(Double(steps) / 10_000, 1)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("GATIVX").font(.system(size: 34, weight: .black, design: .rounded))
                Text("From Goals to Xcellence").font(.subheadline).foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("TODAY'S STEPS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(displayedDailySteps?.formatted() ?? "—")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text(displayedStepSource + (displayedDailySteps == nil ? "" : " · Goal: 10,000"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: stepProgress).tint(.yellow)
                    Text("Active energy: " + (health.todayActiveEnergyKcal.map { "\($0) kcal" } ?? "—") + " · Apple Health measured active calories, not total calories.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("GATIVX shows Apple Health when available; otherwise it shows the separate iPhone motion total. Sources are never added together.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack {
                        Label("Live iPhone motion", systemImage: "figure.walk")
                        Spacer()
                        Text(liveMotionSteps?.formatted() ?? "Waiting…")
                            .monospacedDigit().fontWeight(.semibold)
                    }
                    .font(.caption)
                    if let meters = liveMotionDistanceMeters {
                        Text("Motion distance · \(String(format: "%.2f", meters / 1000)) km")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding().frame(maxWidth: .infinity)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 12) {
                    Text("LIVE ACTIVITY SESSION").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Picker("Activity", selection: $selectedActivity) {
                        ForEach(["Walking", "Running", "Hiking", "Other"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented)
                    HStack(alignment: .firstTextBaseline) {
                        Text(sessionSteps?.formatted() ?? "—").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("steps this session").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(sessionStatus).font(.caption).foregroundStyle(.secondary)
                    Text(routeRecorder.status + " · " + routeRecorder.points.count.formatted() + " GPS points").font(.caption2).foregroundStyle(.secondary)
                    if sessionStarted == nil {
                        if let recoveredStart = routeRecorder.recoveredStartedAt {
                            Text("An unfinished activity from \\(recoveredStart.formatted(date: .abbreviated, time: .shortened)) was recovered. Its GPS points are stored on this iPhone.")
                                .font(.caption).foregroundStyle(.orange)
                            Button("Resume recovered activity") {
                                selectedActivity = routeRecorder.recoveredActivity ?? "Walking"
                                sessionStarted = recoveredStart
                                sessionSteps = nil
                                routeRecorder.resumeRecovered()
                                pedometer.startUpdates(from: recoveredStart) { data, error in
                                    DispatchQueue.main.async {
                                        if error == nil { self.sessionSteps = data?.numberOfSteps.intValue }
                                    }
                                }
                                sessionStatus = "Recovered activity resumed. Finish to save the route."
                            }.buttonStyle(.borderedProminent).tint(.orange)
                            Button("Save recovered route now") {
                                selectedActivity = routeRecorder.recoveredActivity ?? "Walking"
                                sessionStarted = recoveredStart
                                sessionSteps = nil
                                finishActivitySession()
                            }.buttonStyle(.bordered)
                        }
                        Button("Start activity") { startActivitySession() }.buttonStyle(.borderedProminent).tint(.green)
                            .disabled(!CMPedometer.isStepCountingAvailable())
                    } else {
                        Button("Finish & save activity", role: .destructive) { finishActivitySession() }.buttonStyle(.bordered)
                    }
                    Text("Session steps use iPhone motion data. GPS route is recorded separately while an activity is active. Allow location access for route tracking.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                 .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                Button("Connect Apple Health") {
                    health.requestReadAccessAndStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)
                .foregroundStyle(.yellow)

                if !cloud.isSignedIn {
                    VStack(spacing: 10) {
                        Text("Sign in with your existing GATIVX account")
                            .font(.headline)
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                        Button("Sign in and sync") {
                            Task { await cloud.signIn(email: email, password: password) }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Label("Cloud account connected", systemImage: "checkmark.icloud")
                        .foregroundStyle(.green)
                    Button("Sign out", role: .destructive) { cloud.signOut() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(health.statusMessage)
                    Text(cloud.status)
                    if let last = health.lastRefresh {
                        Text("Last Health refresh: \(last.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                Text("Fitness guidance, not medical diagnosis or treatment.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                health.onDailyTotal = { day, total in
                    guard cloud.isSignedIn else { return }
                    Task { await cloud.syncSteps(date: day, steps: total) }
                }
                health.resumeIfPreviouslyConnected()
                health.refreshOnForeground()
                startLiveMotionMonitor()
                // A Keychain-restored session is already signed in before onChange fires.
                if cloud.isSignedIn { syncSavedActivitySessions() }
                if let recoveredStart = routeRecorder.recoveredStartedAt {
                    selectedActivity = routeRecorder.recoveredActivity ?? "Walking"
                    sessionStatus = "Unfinished activity recovered from \\(recoveredStart.formatted(date: .abbreviated, time: .shortened))."
                }
            }
            .onChange(of: cloud.isSignedIn) { _, signedIn in
                if signedIn {
                    health.onDailyTotal = { day, total in
                        Task { await cloud.syncSteps(date: day, steps: total) }
                    }
                    health.refreshRecentDays()
                    syncCurrentMotionSnapshotToCloud()
                    syncSavedActivitySessions()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    health.refreshOnForeground()
                    startLiveMotionMonitor()
                } else {
                    livePedometer.stopUpdates()
                }
            }
        }
    }
}
