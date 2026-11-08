import SwiftUI

struct DashboardView: View {
    @StateObject private var health = HealthSteps()
    @StateObject private var tracker = WalkTracker()
    @StateObject private var store = ActivityStore()
    private let goal = 8000
    @State private var pendingSession: WalkSession?
    @State private var showSaveError = false

    var body: some View {
        TabView {
            today.tabItem { Label("Today", systemImage: "sun.max.fill") }
            activity.tabItem { Label("Activity", systemImage: "figure.walk") }
            history.tabItem { Label("History", systemImage: "chart.bar.fill") }
        }
        .tint(Color(red: 0.72, green: 1.0, blue: 0.22))
        .onAppear { health.requestAccessAndRefresh() }
        .alert("Walk not saved yet", isPresented: $showSaveError) {
            Button("Retry Save") {
                if let pendingSession, store.save(pendingSession) { self.pendingSession = nil }
                else { showSaveError = true }
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("WALKON could not confirm a local save. Keep this screen open and retry. Your walk has not been marked as saved.")
        }
    }

    private var today: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("WALKON").font(.system(size: 15, weight: .black, design: .rounded)).tracking(3).foregroundStyle(.mint)
                            Text("Move with purpose.").font(.title2.bold())
                        }
                        Spacer()
                        Image(systemName: "figure.walk").font(.title).foregroundStyle(.black).padding(14).background(Color.mint, in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TODAY'S STEPS").font(.caption.bold()).tracking(1.6).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(health.steps.formatted()).font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("/ \(goal.formatted())").foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(Double(health.steps) / Double(goal), 1))
                            .tint(.mint).scaleEffect(x: 1, y: 1.7, anchor: .center)
                        HStack {
                            Label(health.status, systemImage: "heart.text.square")
                            Spacer()
                            Text("\(max(goal - health.steps, 0).formatted()) to go")
                        }.font(.caption).foregroundStyle(.secondary)
                        Button { health.refresh() } label: {
                            Label("Refresh Apple Health", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                        }.buttonStyle(.bordered).tint(.mint)
                    }
                    .padding(20).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
                    HStack(spacing: 12) {
                        metric("WALKS", value: "\(store.sessions.count)", icon: "figure.walk")
                        metric("DISTANCE", value: String(format: "%.2f km", store.sessions.reduce(0) { $0 + $1.distanceMeters } / 1000), icon: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your next step").font(.headline)
                        Text("Start a walk to record live steps, distance and your GPS route. Only activities started in WALKON are saved.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
                }.padding(20)
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.07))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var activity: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "figure.walk.motion").font(.system(size: 64)).foregroundStyle(.mint)
                Text(tracker.isTracking ? "Walk in progress" : "Ready when you are")
                    .font(.title2.bold())
                HStack(spacing: 28) {
                    metric("STEPS", value: tracker.liveSteps.formatted(), icon: "shoe")
                    metric("DISTANCE", value: String(format: "%.2f km", tracker.distanceMeters / 1000), icon: "location")
                }
                Button {
                    if tracker.isTracking {
                        if let session = tracker.stop(), !store.save(session) {
                            pendingSession = session
                            showSaveError = true
                        }
                    } else { tracker.start() }
                } label: {
                    Text(tracker.isTracking ? "Finish walk" : "Start walking")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(tracker.isTracking ? Color.orange : Color.mint, in: Capsule())
                        .foregroundStyle(.black)
                }
                Text(tracker.locationStatus).font(.caption).foregroundStyle(.secondary)
                Text(store.storageStatus).font(.caption2).foregroundStyle(.secondary)
                Text("Keep WALKON active in the background and allow location access to record your route while walking.")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.035, green: 0.055, blue: 0.07))
                .navigationTitle("Activity")
        }
    }

    private var history: some View {
        NavigationStack {
            List(store.sessions) { session in
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                    Text("\(session.steps.formatted()) steps  ·  \(String(format: "%.2f km", session.distanceMeters / 1000))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
                .listRowBackground(Color.white.opacity(0.06))
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.035, green: 0.055, blue: 0.07))
            .navigationTitle("Your walks")
            .overlay {
                if store.sessions.isEmpty {
                    ContentUnavailableView("No walks yet", systemImage: "figure.walk", description: Text("Your new activity history starts with your first walk."))
                }
            }
        }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}
