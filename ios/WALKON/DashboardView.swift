import SwiftUI

struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var health = HealthSteps()
    @StateObject private var tracker = WalkTracker()
    @StateObject private var store = ActivityStore()
    @StateObject private var cloud = CloudSyncStore()
    private let goal = 8000
    private let background = Color(red: 0.035, green: 0.055, blue: 0.07)

    var body: some View {
        Group {
            if !cloud.hasResolvedAuth {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Restoring your secure account session")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background)
            } else if !cloud.isSignedIn && !cloud.isOfflineMode {
                SignInView(cloud: cloud)
            } else {
                mainTabs
            }
        }
        .onChange(of: health.steps) { _, steps in
            guard let steps else { return }
            Task { await cloud.syncHealthKitSteps(steps, measuredAt: health.lastUpdated ?? Date()) }
        }
        .onChange(of: cloud.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task {
                await cloud.syncPendingWalks(from: store)
                if let steps = health.steps {
                    await cloud.syncHealthKitSteps(steps, measuredAt: health.lastUpdated ?? Date())
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard cloud.isSignedIn else { return }
            if phase == .active {
                health.refresh()
                Task {
                    await cloud.syncPendingWalks(from: store)
                    if let steps = health.steps {
                        await cloud.syncHealthKitSteps(steps, measuredAt: health.lastUpdated ?? Date())
                    }
                }
            }
            if phase == .background, tracker.isTracking { tracker.checkpointNow() }
        }
    }

    private var mainTabs: some View {
        TabView {
            today.tabItem { Label("Today", systemImage: "sun.max.fill") }
            activity.tabItem { Label("Walk", systemImage: "figure.walk") }
            history.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .tint(Color(red: 0.72, green: 1.0, blue: 0.22))
        .onAppear {
            health.requestAccessAndRefresh()
            tracker.onCheckpoint = { started, steps, distance, route in
                store.checkpoint(startedAt: started, steps: steps, distanceMeters: distance, route: route)
            }
            if let interrupted = store.recoverActiveWalk() { tracker.restore(interrupted) }
            Task { await cloud.syncPendingWalks(from: store) }
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
                        Image(systemName: "figure.walk").font(.title).foregroundStyle(.black)
                            .padding(14).background(Color.mint, in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TODAY'S STEPS").font(.caption.bold()).tracking(1.6).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(health.steps?.formatted() ?? "—")
                                .font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("/ \(goal.formatted())").foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(Double(health.steps ?? 0) / Double(goal), 1))
                            .tint(.mint).scaleEffect(x: 1, y: 1.7, anchor: .center)
                        HStack {
                            Label(health.status, systemImage: "heart.text.square")
                            Spacer()
                            Text("\(max(goal - (health.steps ?? 0), 0).formatted()) to go")
                        }.font(.caption).foregroundStyle(.secondary)
                        Button { health.refresh() } label: {
                            Label("Refresh Apple Health", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                        }.buttonStyle(.bordered).tint(.mint)
                        if let updated = health.lastUpdated {
                            Text("Last checked \(updated.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(20).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
                    HStack(spacing: 12) {
                        metric("WALKS", value: "\(store.sessions.count)", icon: "figure.walk")
                        metric("DISTANCE", value: String(format: "%.2f km", store.sessions.reduce(0) { $0 + $1.distanceMeters } / 1000), icon: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(cloud.status, systemImage: "icloud")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if cloud.isSignedIn {
                                Button("Sign out") {
                                    Task {
                                        do { try await cloud.signOut() }
                                        catch { }
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .tint(.secondary)
                            } else {
                                Button("Connect account") { cloud.connectAccount() }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .tint(.mint)
                            }
                        }
                        Text(store.storageStatus).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your next step").font(.headline)
                        Text("Start a walk to record live steps, distance and your GPS route. Walks are saved on this iPhone and backed up when cloud sync is available.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
                }.padding(20)
            }
            .background(background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var activity: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "figure.walk.motion").font(.system(size: 64)).foregroundStyle(.mint)
                Text(tracker.isTracking ? "Walk in progress" : "Ready when you are").font(.title2.bold())
                HStack(spacing: 28) {
                    metric("SESSION STEPS", value: tracker.liveSteps.formatted(), icon: "figure.walk")
                    metric("DISTANCE", value: String(format: "%.2f km", tracker.distanceMeters / 1000), icon: "location")
                }
                if let accuracy = tracker.gpsAccuracy {
                    Label("GPS accuracy about \(Int(accuracy)) m", systemImage: "location.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    if tracker.isTracking {
                        tracker.finish { session in
                            if let session, store.save(session) {
                                store.clearActiveWalkCheckpoint()
                                Task { await cloud.syncPendingWalks(from: store) }
                            }
                        }
                    } else {
                        tracker.start()
                    }
                } label: {
                    Text(tracker.isTracking ? "Finish walk" : "Start walking")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(tracker.isTracking ? Color.orange : Color.mint, in: Capsule())
                        .foregroundStyle(.black)
                }
                .accessibilityHint(tracker.isTracking ? "Stops recording and saves this walk" : "Starts recording steps and GPS route")
                Text(tracker.locationStatus).font(.caption).foregroundStyle(.secondary)
                Text("Keep location access enabled for route recording. Allow Always access to continue while the screen is locked.")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .navigationTitle("Walk")
        }
    }

    private var history: some View {
        NavigationStack {
            List(store.sessions) { session in
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                    Text("\(session.steps.formatted()) steps  ·  \(String(format: "%.2f km", session.distanceMeters / 1000))  ·  \(Int(session.duration / 60)) min")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(session.route.count) GPS points").font(.caption).foregroundStyle(.tertiary)
                }.padding(.vertical, 5)
                .listRowBackground(Color.white.opacity(0.06))
            }
            .scrollContentBackground(.hidden)
            .background(background)
            .navigationTitle("Your walks")
            .overlay {
                if store.sessions.isEmpty {
                    ContentUnavailableView("No walks yet", systemImage: "figure.walk", description: Text("Your activity history starts with your first walk."))
                }
            }
        }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}
