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
                        steps: record.steps,
                        points: points
                    )
                }
            }
        }
    }
    private func startActivitySession() {
        let start = Date()
        sessionStarted = start
        sessionSteps = nil
        // GPS recording is independent of the motion sensor. A device without
        // CMPedometer must still be able to record and save a complete route.
        routeRecorder.start(activity: selectedActivity)
        guard CMPedometer.isStepCountingAvailable() else {
            sessionStatus = "Recording GPS route for " + selectedActivity.lowercased() + " · step counter unavailable."
            return
        }
        sessionSteps = 0
        sessionStatus = "Counting steps and recording GPS for " + selectedActivity.lowercased() + "…"
        pedometer.startUpdates(from: start) { data, error in
            DispatchQueue.main.async {
                if let error { self.sessionStatus = "GPS is recording; motion step count unavailable: " + error.localizedDescription; return }
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
        // Keep route persistence independent of the optional pedometer result.
        let saveRecord: (Int?) -> Void = { queriedSteps in
            DispatchQueue.main.async {
                let finalSteps = queriedSteps ?? self.sessionSteps
                guard finalSteps != nil || !routePoints.isEmpty else {
                    self.routeRecorder.clearDraft()
                    self.sessionSteps = nil
                    self.sessionStatus = "No step count or GPS route points were recorded."
                    self.sessionStarted = nil
                    return
                }
                let record = ActivitySessionRecord(id: UUID(), activity: activity, startedAt: start, finishedAt: finishedAt, steps: finalSteps, routePoints: routePoints)
                let storageKey = "gativx.activitySessions.v1"
                let existingData = UserDefaults.standard.data(forKey: storageKey)
                var history: [ActivitySessionRecord]
                do {
                    history = try existingData.map { try JSONDecoder().decode([ActivitySessionRecord].self, from: $0) } ?? []
                } catch {
                    // Never replace an unreadable history with an empty array.
                    self.sessionStatus = "Could not read existing activity history. Your current route draft is preserved; no saved history was replaced."
                    self.sessionStarted = nil
                    return
                }
                history.insert(record, at: 0)
                do {
                    let encodedHistory = try JSONEncoder().encode(history)
                    UserDefaults.standard.set(encodedHistory, forKey: storageKey)
                    guard UserDefaults.standard.data(forKey: storageKey) != nil else {
                        throw NSError(domain: "GATIVXActivityStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local activity history could not be verified after saving."])
                    }
                    // Clear the durable GPS draft only after the completed session
                    // has been encoded and stored successfully.
                    self.routeRecorder.clearDraft()
                    self.sessionSteps = finalSteps
                    let stepSummary = finalSteps.map { $0.formatted() + " steps" } ?? "step count unavailable"
                    let routeSummary = routePoints.isEmpty ? "no GPS route points" : "GPS route saved"
                    self.sessionStatus = activity + " saved · " + stepSummary + " · " + routeSummary
                    self.sessionStarted = nil
                    self.syncSavedActivitySessions()
                } catch {
                    self.sessionStatus = "Could not save this activity on this iPhone: " + error.localizedDescription + ". Your GPS draft remains preserved; do not clear app data."
                    self.sessionStarted = nil
                }
            }
        }
        // Query the complete interval after stopping live updates so the final
        // motion samples are included even if the last callback was delayed.
        if CMPedometer.isStepCountingAvailable() {
            pedometer.queryPedometerData(from: start, to: finishedAt) { data, _ in
                saveRecord(data?.numberOfSteps.intValue)
            }
        } else {
            saveRecord(nil)
        }
    }

    /// Prefer HealthKit's all-source aggregate as the only displayed daily total.
    /// CoreMotion remains a separate iPhone-only live preview and is never
    /// presented as a substitute for the member's complete daily total.
    private var displayedDailySteps: Int? {
        health.todaySteps
    }

    private var displayedStepSource: String {
        if health.todaySteps != nil { return "Apple Health · combined available sources" }
        if !health.isAvailable { return "Apple Health is unavailable on this iPhone" }
        return "Connect Apple Health to show your measured daily total"
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
                    Text("The daily total comes only from Apple Health. The iPhone motion reading below is a separate live preview and is not substituted for the all-source daily total.")
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
                    Text("GPS route distance · " + String(format: "%.2f", routeRecorder.routeDistanceMeters / 1000) + " km · " + routeRecorder.points.count.formatted() + " GPS points").font(.caption2).foregroundStyle(.secondary)
                    if routeRecorder.authorization == .authorizedWhenInUse {
                        Button("Enable background GPS (Always location)") {
                            routeRecorder.requestBackgroundLocationAccess()
                        }
                        .font(.caption)
                    }
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
                        Button(selectedActivity == "Walking" ? "Start WalkOn" : "Start activity") { startActivitySession() }.buttonStyle(.borderedProminent).tint(.green)
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

                Button("Refresh Apple Health now") {
                    health.refreshRecentDays()
                    health.refreshTodayEnergy()
                }
                .buttonStyle(.bordered)
                .disabled(!health.isAvailable || health.isRefreshing)

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
                health.onActiveEnergy = { day, total in
                    guard cloud.isSignedIn else { return }
                    Task { await cloud.syncActiveEnergy(date: day, kilocalories: total) }
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
                    health.onActiveEnergy = { day, total in
                        Task { await cloud.syncActiveEnergy(date: day, kilocalories: total) }
                    }
                    health.refreshRecentDays()
                    health.refreshTodayEnergy()
                    syncCurrentMotionSnapshotToCloud()
                    syncSavedActivitySessions()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    health.refreshOnForeground()
                    startLiveMotionMonitor()
                    if cloud.isSignedIn {
                        syncCurrentMotionSnapshotToCloud()
                        syncSavedActivitySessions()
                    }
                } else if sessionStarted == nil && !routeRecorder.isRecording {
                    // Keep the session pedometer alive while an explicitly started
                    // activity is running in the background/with the screen locked.
                    livePedometer.stopUpdates()
                }
            }
        }
    }
}
