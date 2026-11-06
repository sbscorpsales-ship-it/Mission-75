import SwiftUI
import CoreMotion

private struct ActivitySessionRecord: Codable { let id: UUID; let activity: String; let startedAt: Date; let finishedAt: Date; let steps: Int? }

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var health = HealthKitManager()
    @StateObject private var cloud = SupabaseRESTClient()
    @State private var email = ""
    @State private var password = ""
    @State private var pedometer = CMPedometer()
    @State private var selectedActivity = "Walking"
    @State private var sessionSteps: Int?
    @State private var sessionStarted: Date?
    @State private var sessionStatus = "Start a session to count steps."

    private func startActivitySession() {
        guard CMPedometer.isStepCountingAvailable() else { sessionStatus = "Step counting is unavailable."; return }
        let start = Date(); sessionStarted = start; sessionSteps = 0
        sessionStatus = "Counting steps for " + selectedActivity.lowercased() + "…"
        pedometer.startUpdates(from: start) { data, error in
            DispatchQueue.main.async {
                if let error { self.sessionStatus = "Motion step count unavailable: " + error.localizedDescription; return }
                self.sessionSteps = data?.numberOfSteps.intValue
            }
        }
    }
    private func finishActivitySession() {
        pedometer.stopUpdates()
        guard let start = sessionStarted else { return }
        let record = ActivitySessionRecord(id: UUID(), activity: selectedActivity, startedAt: start, finishedAt: Date(), steps: sessionSteps)
        var history = (try? JSONDecoder().decode([ActivitySessionRecord].self, from: UserDefaults.standard.data(forKey: "gativx.activitySessions.v1") ?? Data())) ?? []
        history.insert(record, at: 0)
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "gativx.activitySessions.v1")
        sessionStatus = selectedActivity + " saved · " + (sessionSteps?.formatted() ?? "step count unavailable") + " steps"
        sessionStarted = nil
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
                    Text(sessionStatus).font(.caption).foregroundStyle(.secondary)
                    if sessionStarted == nil {
                        Button("Start activity") { startActivitySession() }.buttonStyle(.borderedProminent).tint(.green)
                            .disabled(!CMPedometer.isStepCountingAvailable())
                    } else {
                        Button("Finish & save activity", role: .destructive) { finishActivitySession() }.buttonStyle(.bordered)
                    }
                    Text("Live session steps use iPhone motion data. Today total above comes from Apple Health.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                 .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                Button("Connect Apple Health") {
                    health.requestReadAccessAndStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)
                .foregroundStyle(.yellow)

                Button("Refresh steps now") {
                    health.refreshRecentDays()
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
                health.resumeIfPreviouslyConnected()
                health.refreshOnForeground()
            }
            .onChange(of: cloud.isSignedIn) { _, signedIn in
                if signedIn {
                    health.onDailyTotal = { day, total in
                        Task { await cloud.syncSteps(date: day, steps: total) }
                    }
                    health.refreshRecentDays()
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
