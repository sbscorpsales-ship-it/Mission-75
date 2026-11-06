import SwiftUI
import CoreMotion

private struct ActivitySessionRecord: Codable { let id: UUID; let activity: String; let startedAt: Date; let finishedAt: Date; let steps: Int?; let routePoints: [GATIVXRoutePoint]? }

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var health = HealthKitManager()
    @StateObject private var cloud = SupabaseRESTClient()\n    @StateObject private var routeRecorder = GPSRouteRecorder()
    @State private var email = ""
    @State private var password = ""
    @State private var pedometer = CMPedometer()
    @State private var selectedActivity = "Walking"
    @State private var sessionSteps: Int?
    @State private var sessionStarted: Date?
    @State private var sessionStatus = "Start a session to count steps."

    private func syncSavedActivitySessions() {
        guard cloud.isSignedIn else { return }
        let history = (try? JSONDecoder().decode([ActivitySessionRecord].self, from: UserDefaults.standard.data(forKey: "gativx.activitySessions.v1") ?? Data())) ?? []
        Task {
            for record in history {
                guard let steps = record.steps else { continue }
                await cloud.syncActivitySession(id: record.id, activity: record.activity, startedAt: record.startedAt, finishedAt: record.finishedAt, steps: steps)\n                if let points = record.routePoints, !points.isEmpty { await cloud.syncActivitySessionRoute(id: record.id, points: points) }
            }
        }
    }
    private func startActivitySession() {
        guard CMPedometer.isStepCountingAvailable() else { sessionStatus = "Step counting is unavailable."; return }
        let start = Date(); sessionStarted = start; sessionSteps = 0\n        routeRecorder.start()
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
        // Query the complete interval after stopping live updates so the final
        // motion samples are included even if the last callback was delayed.
        pedometer.queryPedometerData(from: start, to: finishedAt) { data, _ in
            DispatchQueue.main.async {
                let finalSteps = data?.numberOfSteps.intValue ?? self.sessionSteps
                let record = ActivitySessionRecord(id: UUID(), activity: activity, startedAt: start, finishedAt: finishedAt, steps: finalSteps, routePoints: routePoints)
                var history = (try? JSONDecoder().decode([ActivitySessionRecord].self, from: UserDefaults.standard.data(forKey: "gativx.activitySessions.v1") ?? Data())) ?? []
                history.insert(record, at: 0)
                UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "gativx.activitySessions.v1")
                self.sessionSteps = finalSteps
                self.sessionStatus = activity + " saved · " + (finalSteps?.formatted() ?? "step count unavailable") + " steps"
                self.sessionStarted = nil
                self.syncSavedActivitySessions()
            }
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
                    Text("TODAY'S STEPS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(health.todaySteps?.formatted() ?? "—")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text(health.todaySteps == nil ? "Waiting for Apple Health data" : "Goal: 10,000")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: stepProgress).tint(.yellow)
                    Text("Active energy: " + (health.todayActiveEnergyKcal.map { "\($0) kcal" } ?? "—") + " · Apple Health measured active calories, not total calories.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Steps are read from Apple Health, which can combine supported iPhone and wearable sources.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                    Text(sessionStatus).font(.caption).foregroundStyle(.secondary)\n                    Text(routeRecorder.status + " · " + routeRecorder.points.count.formatted() + " GPS points").font(.caption2).foregroundStyle(.secondary)
                    if sessionStarted == nil {
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
                // A Keychain-restored session is already signed in before onChange fires.
                if cloud.isSignedIn { syncSavedActivitySessions() }
            }
            .onChange(of: cloud.isSignedIn) { _, signedIn in
                if signedIn {
                    health.onDailyTotal = { day, total in
                        Task { await cloud.syncSteps(date: day, steps: total) }
                    }
                    health.refreshRecentDays()
                    syncSavedActivitySessions()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    health.refreshOnForeground()
                }
            }
        }
    }
}
