import SwiftUI

struct DashboardView: View {
    @StateObject private var health = HealthSteps()
    @StateObject private var tracker: WalkTracker
    @StateObject private var store: ActivityStore
    private let goal = 8000
    @State private var showRecoveryAlert = false

    private let ink = Color(red: 0.035, green: 0.055, blue: 0.07)
    private let panel = Color.white.opacity(0.065)
    private let lime = Color(red: 0.72, green: 1.0, blue: 0.22)

    init() {
        let activityStore = ActivityStore()
        _store = StateObject(wrappedValue: activityStore)
        _tracker = StateObject(wrappedValue: WalkTracker(store: activityStore))
    }

    var body: some View {
        TabView {
            today.tabItem { Label("Today", systemImage: "sun.max.fill") }
            activity.tabItem { Label("Walk", systemImage: "figure.walk") }
            history.tabItem { Label("Journey", systemImage: "chart.bar.fill") }
        }
        .tint(lime)
        .preferredColorScheme(.dark)
        .onAppear {
            health.requestAccessAndRefresh()
            showRecoveryAlert = !store.recoverableDrafts.isEmpty
        }
        .alert("An unfinished walk was found", isPresented: $showRecoveryAlert) {
            Button("Save recovered walk") {
                if let draft = store.recoverableDrafts.first {
                    _ = store.finalizeDraft(draft.id)
                }
            }
            Button("Discard walk", role: .destructive) {
                if let draft = store.recoverableDrafts.first {
                    _ = store.discardDraft(draft.id)
                }
            }
            Button("Decide later", role: .cancel) { }
        } message: {
            if let draft = store.recoverableDrafts.first {
                Text("Your walk from \(draft.startedAt.formatted(date: .abbreviated, time: .shortened)) was interrupted. Save its recorded data or discard it.")
            } else {
                Text("An unfinished activity is available for recovery.")
            }
        }
    }

    private var today: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    stepCard
                    HStack(spacing: 12) {
                        metricCard("WALKS", value: "\(store.sessions.count)", icon: "figure.walk")
                        metricCard("DISTANCE", value: String(format: "%.2f km", store.sessions.reduce(0) { $0 + $1.distanceMeters } / 1000), icon: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Label("SMALL STEPS. REAL PROGRESS.", systemImage: "sparkles")
                            .font(.caption.bold()).tracking(1.1).foregroundStyle(lime)
                        Text("Your next walk starts here.")
                            .font(.title3.bold())
                        Text("Step outside, find your pace and let WALKON keep a record of the journey.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(panel, in: RoundedRectangle(cornerRadius: 22))
                    Button { health.refresh() } label: {
                        Label("Refresh Apple Health data", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                    }
                    .buttonStyle(.bordered).tint(lime)
                }
                .padding(20)
            }
            .background(ink.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("WALKON")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(3.5).foregroundStyle(lime)
                Text("Every step matters.")
                    .font(.title2.bold()).foregroundStyle(.white)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(ink).frame(width: 58, height: 58)
                .background(lime, in: RoundedRectangle(cornerRadius: 19))
                .accessibilityHidden(true)
        }
        .padding(.top, 8)
    }

    private var stepCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("TODAY'S STEPS", systemImage: "shoeprints.fill")
                    .font(.caption.bold()).tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                Text("DAILY GOAL").font(.caption2.bold()).tracking(1).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(health.steps?.formatted() ?? "—")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                Text("/ \(goal.formatted())")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            ProgressView(value: min(Double(health.steps ?? 0) / Double(goal), 1))
                .tint(lime).scaleEffect(x: 1, y: 1.8, anchor: .center)
                .accessibilityLabel("Daily step goal progress")
                .accessibilityValue("\(health.steps ?? 0) of \(goal) steps")
            HStack(alignment: .center) {
                Label(health.status, systemImage: "heart.text.square")
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let steps = health.steps {
                    Text(steps >= goal ? "Goal reached" : "\(max(goal - steps, 0).formatted()) to go")
                        .fontWeight(.semibold).foregroundStyle(lime)
                } else {
                    Text("Awaiting data").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(22)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.105), panel], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26)
        )
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var activity: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: tracker.isTracking ? "figure.walk.motion" : "figure.walk")
                            .font(.system(size: 58, weight: .light)).foregroundStyle(lime)
                            .padding(.bottom, 4)
                        Text(tracker.isTracking ? "You're on your way" : "Ready when you are")
                            .font(.title2.bold())
                        Text(tracker.isTracking ? "Keep moving. Your walk is being recorded." : "Start a walk when you're ready to head out.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                    HStack(spacing: 12) {
                        metricCard("SESSION STEPS", value: tracker.liveSteps.formatted(), icon: "shoeprints.fill")
                        metricCard("DISTANCE", value: String(format: "%.2f km", tracker.distanceMeters / 1000), icon: "location.fill")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label("RECORDING STATUS", systemImage: "location.circle")
                            .font(.caption.bold()).tracking(1.1).foregroundStyle(lime)
                        Text(tracker.locationStatus)
                            .font(.subheadline.weight(.medium))
                        Text(store.storageStatus)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18).background(panel, in: RoundedRectangle(cornerRadius: 20))
                    Button {
                        if tracker.isTracking {
                            _ = tracker.stop()
                        } else {
                            _ = tracker.start()
                        }
                    } label: {
                        Label(tracker.isTracking ? "Finish walk" : "Start walking",
                              systemImage: tracker.isTracking ? "stop.fill" : "play.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(tracker.isTracking ? Color.orange : lime, in: Capsule())
                            .foregroundStyle(ink)
                    }
                    .accessibilityHint(tracker.isTracking ? "Stops recording and saves this walk" : "Begins recording a new walk")
                    Text("Only walks you explicitly start are recorded. Location access is needed for a GPS route.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(22)
            }
            .background(ink.ignoresSafeArea())
            .navigationTitle("Your walk")
        }
    }

    private var history: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView("Your journey begins here",
                        systemImage: "figure.walk",
                        description: Text("Your completed walks will appear here, ready to revisit."))
                } else {
                    List(store.sessions) { session in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(session.startedAt.formatted(date: .complete, time: .shortened))
                                .font(.headline)
                            HStack(spacing: 14) {
                                Label("\(session.steps.formatted()) steps", systemImage: "shoeprints.fill")
                                Label(String(format: "%.2f km", session.distanceMeters / 1000), systemImage: "location")
                            }
                            .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(panel)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ink.ignoresSafeArea())
            .navigationTitle("Your journey")
        }
    }

    private func metricCard(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.caption2.bold()).tracking(0.8).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Text(value).font(.title2.bold()).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.055), lineWidth: 1))
    }
}
