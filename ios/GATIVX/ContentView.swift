import SwiftUI
import CoreMotion

private struct ActivitySessionRecord: Codable { let id: UUID; let activity: String; let startedAt: Date; let finishedAt: Date; let steps: Int?; let route: [GATIVXRoutePoint]? }

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var health = HealthKitManager()
    @StateObject private var cloud = SupabaseRESTClient()
    @StateObject private var location = WalkLocationManager()
    @State private var email = ""
    @State private var password = ""
    @State private var pedometer = CMPedometer()
    @State private var dailyPedometer = CMPedometer()
    @State private var motionTodaySteps: Int?
    @State private var motionRefreshID = UUID()
    @State private var selectedActivity = "Walking"
    @State private var sessionActivity = "Walking"
    @State private var sessionSteps: Int?
    @State private var sessionStarted: Date?
    @State private var isFinishingSession = false
    @State private var sessionStatus = "Start a session to count steps."

    /// Route HealthKit's daily aggregate directly into the signed-in cloud account.
    /// HealthKit is the daily source of truth; Core Motion remains session-only.
    private func connectHealthKitToCloud() {
        health.onDailyTotal = { day, total in
            guard cloud.isSignedIn else { return }
            Task { await cloud.syncMotionDailySteps(date: day, steps: total) }
        }
    }

    private func refreshDirectMotionSteps() {
        guard CMPedometer.isStepCountingAvailable() else {
            sessionStatus = "iPhone motion step counting is unavailable."
            return
        }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        // Give each refresh a generation ID so a slow, older query or stream
        // cannot overwrite the newest total after foreground/scene transitions.
        let refreshID = UUID()
        motionRefreshID = refreshID
        dailyPedometer.stopUpdates()
        let queryTime = Date()
        dailyPedometer.queryPedometerData(from: startOfDay, to: queryTime) { data, error in
            DispatchQueue.main.async {
                guard self.motionRefreshID == refreshID else { return }
                if let error {
                    self.sessionStatus = "Could not read today's iPhone motion total: " + error.localizedDescription
                    return
                }
                let total = data?.numberOfSteps.intValue ?? 0
                self.motionTodaySteps = total
                // Core Motion reports the cumulative count since startOfDay.
                // Sync each changed total so cloud data does not wait for the next launch.
                self.dailyPedometer.startUpdates(from: startOfDay) { liveData, liveError in
                    DispatchQueue.main.async {
                        guard self.motionRefreshID == refreshID else { return }
                        if let liveError {
                            self.sessionStatus = "Live iPhone motion updates paused: " + liveError.localizedDescription
                            return
                        }
                        guard let liveTotal = liveData?.numberOfSteps.intValue,
                              liveTotal != self.motionTodaySteps else { return }
                        self.motionTodaySteps = liveTotal
                    }
                }
            }
        }
    }

    private func startActivitySession() {
        guard CMPedometer.isStepCountingAvailable() else { sessionStatus = "Step counting is unavailable."; return }
        guard sessionStarted == nil, !isFinishingSession else { return }
        let start = Date()
        sessionStarted = start
        sessionActivity = selectedActivity
        sessionSteps = 0
        UserDefaults.standard.set(start, forKey: "gativx.activeSession.startedAt.v1")
        UserDefaults.standard.set(sessionActivity, forKey: "gativx.activeSession.activity.v1")
        location.begin()
        sessionStatus = "Counting steps for " + sessionActivity.lowercased() + "…"
        pedometer.startUpdates(from: start) { data, error in
            DispatchQueue.main.async {
                if let error {
                    self.sessionStatus = "Motion step count unavailable: " + error.localizedDescription
                    return
                }
                self.sessionSteps = data?.numberOfSteps.intValue
            }
        }
    }

    private func finishActivitySession() {
        guard let start = sessionStarted, !isFinishingSession else { return }
        isFinishingSession = true
        let finish = Date()
        let capturedRoute = location.finish()
        pedometer.stopUpdates()

        // Ask Core Motion for the complete interval at Finish, rather than
        // relying only on the most recent asynchronous live-update callback.
        pedometer.queryPedometerData(from: start, to: finish) { data, error in
            DispatchQueue.main.async {
                let finalSteps = data?.numberOfSteps.intValue ?? self.sessionSteps
                if let error {
                    self.sessionStatus = "Final motion query unavailable; saving last live reading. " + error.localizedDescription
                }
                self.persistFinishedSession(startedAt: start, finishedAt: finish, steps: finalSteps, route: capturedRoute)
            }
        }
    }

    private func persistFinishedSession(startedAt: Date, finishedAt: Date, steps: Int?, route: [GATIVXRoutePoint]) {
        let record = ActivitySessionRecord(
            id: UUID(), activity: sessionActivity,
            startedAt: startedAt, finishedAt: finishedAt, steps: steps, route: route
        )
        var history = (try? JSONDecoder().decode(
            [ActivitySessionRecord].self,
            from: UserDefaults.standard.data(forKey: "gativx.activitySessions.v1") ?? Data()
        )) ?? []
        history.insert(record, at: 0)
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "gativx.activitySessions.v1")

        sessionSteps = steps
        sessionStatus = sessionActivity + " saved · " + (steps?.formatted() ?? "step count unavailable") + " steps"
        sessionStarted = nil
        UserDefaults.standard.removeObject(forKey: "gativx.activeSession.startedAt.v1")
        UserDefaults.standard.removeObject(forKey: "gativx.activeSession.activity.v1")
        isFinishingSession = false

        if cloud.isSignedIn, let steps {
            Task {
                await cloud.syncActivitySession(
                    id: record.id, activity: record.activity,
                    startedAt: record.startedAt, finishedAt: record.finishedAt, steps: steps
                )
                await cloud.syncActivitySessionRoute(id: record.id, route: record.route ?? [])
            }
        } else {
            sessionStatus += " · saved on this iPhone; sign in to sync"
        }
    }

    private func recoverInterruptedSessionIfNeeded() {
        guard sessionStarted == nil,
              let startedAt = UserDefaults.standard.object(forKey: "gativx.activeSession.startedAt.v1") as? Date,
              startedAt < Date(),
              Date().timeIntervalSince(startedAt) < 24 * 60 * 60 else { return }
        sessionStarted = startedAt
        sessionActivity = UserDefaults.standard.string(forKey: "gativx.activeSession.activity.v1") ?? "Walking"
        selectedActivity = sessionActivity
        sessionSteps = 0
        sessionStatus = "Recovered interrupted activity · checking its complete step count"
        location.resume()
        pedometer.startUpdates(from: startedAt) { data, error in
            DispatchQueue.main.async {
                if let error {
                    self.sessionStatus = "Recovered session; final step query will be used: " + error.localizedDescription
                } else {
                    self.sessionSteps = data?.numberOfSteps.intValue
                }
            }
        }
    }

    @MainActor
    private func syncSavedActivitySessions() async {
        let history = (try? JSONDecoder().decode(
            [ActivitySessionRecord].self,
            from: UserDefaults.standard.data(forKey: "gativx.activitySessions.v1") ?? Data()
        )) ?? []

        // Await each upload so token refreshes and status updates are serialized.
        // Session UUIDs make the server upsert idempotent if a retry is needed.
        for record in history {
            guard let steps = record.steps else { continue }
            await cloud.syncActivitySession(
                id: record.id, activity: record.activity,
                startedAt: record.startedAt, finishedAt: record.finishedAt, steps: steps
            )
            await cloud.syncActivitySessionRoute(id: record.id, route: record.route ?? [])
        }
    }

    private var stepProgress: Double {
        guard let steps = health.todaySteps else { return 0 }
        return min(Double(steps) / 10_000, 1)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("GATIVX").font(.system(size: 34, weight: .black, design: .rounded))
                Text("From Goals to Xcellence").font(.subheadline).foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("TODAY'S APPLE HEALTH STEPS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(health.todaySteps?.formatted() ?? "—")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text(health.todaySteps == nil ? "Waiting for Apple Health step data" : "Goal: 10,000 · Apple Health")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: stepProgress).tint(.yellow)
                    Text("Daily total comes directly from Apple Health. Live walk steps use the iPhone motion sensor.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding().frame(maxWidth: .infinity)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 12) {
                    Text("LIVE ACTIVITY SESSION").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Picker("Activity", selection: $selectedActivity) {
                        ForEach(["Walking", "Running", "Hiking", "Other"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented)
                    .disabled(sessionStarted != nil || isFinishingSession)
                    HStack(alignment: .firstTextBaseline) {
                        Text(sessionSteps?.formatted() ?? "—").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("steps this session").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(sessionStatus).font(.caption).foregroundStyle(.secondary)
                    Text(location.status).font(.caption2).foregroundStyle(.secondary)
                    if sessionStarted == nil {
                        Button("Start activity") { startActivitySession() }.buttonStyle(.borderedProminent).tint(.green)
                            .disabled(!CMPedometer.isStepCountingAvailable() || isFinishingSession)
                    } else {
                        Button(isFinishingSession ? "Finishing…" : "Finish & save activity", role: .destructive) {
                            finishActivitySession()
                        }.buttonStyle(.bordered).disabled(isFinishingSession)
                    }
                    Text("Daily total is from Apple Health. Session steps are measured separately by Core Motion.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                 .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                Button("Connect Apple Health") {
                    health.requestReadAccessAndStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)
                .foregroundStyle(.yellow)

                Button {
                    refreshDirectMotionSteps()
                } label: {
                    Label("Refresh iPhone steps", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

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
                // Install the HealthKit-to-cloud callback before starting any queries.
                connectHealthKitToCloud()
                health.resumeIfPreviouslyConnected()
                health.refreshOnForeground()
                refreshDirectMotionSteps()
                recoverInterruptedSessionIfNeeded()
                if cloud.isSignedIn { Task { await syncSavedActivitySessions() } }
            }
            .onChange(of: cloud.isSignedIn) { _, signedIn in
                if signedIn {
                    connectHealthKitToCloud()
                    health.refreshRecentDays()
                    refreshDirectMotionSteps()
                    Task { await syncSavedActivitySessions() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    health.refreshOnForeground()
                    refreshDirectMotionSteps()
                    if cloud.isSignedIn {
                        Task { await syncSavedActivitySessions() }
                    }
                }
            }
        }
    }
}
