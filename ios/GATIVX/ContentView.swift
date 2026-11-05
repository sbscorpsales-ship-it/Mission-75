import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var health = HealthKitManager()
    @StateObject private var cloud = SupabaseRESTClient()
    @State private var email = ""
    @State private var password = ""

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
