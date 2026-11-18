import SwiftUI
import CoreMotion

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var health = HealthKitManager()
    @StateObject private var cloud = SupabaseRESTClient()
    @StateObject private var routeRecorder = GPSRouteRecorder()
    private let activityStore = ActivitySessionStore()
    @State private var email = ""
    @State private var password = ""
    @State private var pedometer = CMPedometer()
    @State private var livePedometer = CMPedometer()
    @State private var selectedActivity = "Walking"
    @State private var sessionSteps: Int?
    @State private var sessionMotionDistanceMeters: Double?
    @State private var activityHistory: [ActivitySessionRecord] = []
    @State private var historyStatus = ""
    @State private var sessionStarted: Date?
    @State private var isFinishingSession = false
    @State private var activeSessionID: UUID?
    @State private var sessionStatus = "Start a session to count steps."
    @State private var liveMotionSteps: Int?
    @State private var liveMotionDistanceMeters: Double?
    @State private var motionStatus = "Checking iPhone pedometer…"
    @State private var lastMotionCloudSyncAt: Date?
    @State private var lastMotionCloudSteps: Int = -1

    /// Foreground live sensor feed. This is shown separately from HealthKit's
    /// deduplicated all-source daily total; never add the two together.
    private func startLiveMotionMonitor() {
        guard CMPedometer.isStepCountingAvailable() else {
            motionStatus = "This iPhone does not report step counting through Core Motion."
            return
        }
        switch CMPedometer.authorizationStatus() {
        case .denied:
            motionStatus = "Motion & Fitness access is denied. Enable it for GATIVX in iPhone Settings."
        case .restricted:
            motionStatus = "Motion & Fitness access is restricted on this iPhone."
        default:
            motionStatus = "Requesting iPhone pedometer readings…"
        }
        let start = Calendar.current.startOfDay(for: Date())
        livePedometer.stopUpdates()
        livePedometer.startUpdates(from: start) { data, error in
            DispatchQueue.main.async {
                if let error {
                    self.motionStatus = "iPhone pedometer error: " + error.localizedDescription
                    return
                }
                guard let data else {
                    self.motionStatus = "Waiting for the iPhone pedometer to return today's steps."
                    return
                }
                let steps = data.numberOfSteps.intValue
                let distance = data.distance?.doubleValue
                self.liveMotionSteps = steps
                self.liveMotionDistanceMeters = distance
                self.motionStatus = "iPhone pedometer · updated " + Date().formatted(date: .omitted, time: .shortened)
                let now = Date()
                let enoughTime = self.lastMotionCloudSyncAt.map { now.timeIntervalSince($0) >= 60 } ?? true
                let meaningfulChange = self.lastMotionCloudSteps < 0 || steps - self.lastMotionCloudSteps >= 100
                if self.cloud.isSignedIn && (enoughTime || meaningfulChange) {
                    Task {
                        let synced = await self.cloud.syncMotionDailySteps(date: now, steps: steps, distanceMeters: distance)
                        if synced {
                            self.lastMotionCloudSyncAt = now
                            self.lastMotionCloudSteps = steps
                        } else {
                            // Leave the last-success markers unchanged so the next
                            // sensor update retries instead of treating a failed
                            // upload as completed.
                            self.lastMotionCloudSyncAt = nil
                            self.lastMotionCloudSteps = -1
                        }
                    }
                }
            }
        }
    }
    private var visibleActivityHistory: [ActivitySessionRecord] {
        if cloud.isSignedIn {
            guard let ownerID = cloud.authenticatedUserID else { return [] }
            return activityHistory.filter { $0.ownerID == ownerID }
        }
        // Guest/local-only activities are visible only while no cloud account is active.
        return activityHistory.filter { $0.ownerID == nil }
    }

    private func loadActivityHistory() {
        do {
            activityHistory = try activityStore.load()
            let visibleCount = visibleActivityHistory.count
            historyStatus = visibleCount == 0
                ? "No completed activities saved for this account yet."
                : "Loaded \\(visibleCount) account-matched activities from this iPhone."
        } catch {
            historyStatus = "Saved activity history could not be read. Existing data has been left untouched."
        }
    }

    private func syncCurrentMotionSnapshotToCloud() {
        guard cloud.isSignedIn, let steps = liveMotionSteps else { return }
        let snapshotDate = Date()
        let distance = liveMotionDistanceMeters
        Task {
            let synced = await cloud.syncMotionDailySteps(
                date: snapshotDate,
                steps: steps,
                distanceMeters: distance
            )
            if synced {
                lastMotionCloudSyncAt = snapshotDate
                lastMotionCloudSteps = steps
            } else {
                lastMotionCloudSyncAt = nil
                lastMotionCloudSteps = -1
            }
        }
    }

    private func syncSavedActivitySessions() {
        guard cloud.isSignedIn, let ownerID = cloud.authenticatedUserID else { return }

        let history: [ActivitySessionRecord]
        do {
            history = try activityStore.load()
        } catch {
            // Corrupt local history must never masquerade as an empty history.
            historyStatus = "Cloud sync paused: saved activity history could not be read. Existing data was not changed."
            return
        }

        // Only backfill records explicitly bound to this authenticated account.
        // Legacy and guest records remain local until their ownership can be verified.
        for record in history where record.ownerID == ownerID {
            cloud.enqueueActivitySession(record)
        }
        Task { await cloud.retryPendingActivitySessions() }
    }
    private func startActivitySession() {
        guard sessionStarted == nil, !isFinishingSession else { return }
        let start = Date()
        sessionStarted = start
        activeSessionID = UUID()
        sessionSteps = nil
        sessionMotionDistanceMeters = nil
        // GPS recording is independent of the motion sensor. A device without
        // CMPedometer must still be able to record and save a complete route.
        routeRecorder.start(activity: selectedActivity, ownerID: cloud.authenticatedUserID)
        guard CMPedometer.isStepCountingAvailable() else {
            sessionStatus = "Recording GPS route for " + selectedActivity.lowercased() + " · step counter unavailable."
            return
        }
        // Keep the count unknown until Core Motion returns a measured value.
        // Starting a session must never manufacture a zero-step activity record.
        sessionStatus = "Waiting for iPhone step readings and recording GPS for " + selectedActivity.lowercased() + "…"
        pedometer.startUpdates(from: start) { data, error in
            DispatchQueue.main.async {
                if let error { self.sessionStatus = "GPS is recording; motion step count unavailable: " + error.localizedDescription; return }
                self.sessionSteps = data?.numberOfSteps.intValue
                self.sessionMotionDistanceMeters = data?.distance?.doubleValue
            }
        }
    }
    private func finishActivitySession() {
        guard !isFinishingSession, let start = sessionStarted else { return }
        isFinishingSession = true
        let recordID = activeSessionID ?? UUID()
        activeSessionID = recordID
        sessionStatus = "Finishing activity and saving your route…"
        let finishedAt = Date()
        let activity = selectedActivity
        pedometer.stopUpdates()
        routeRecorder.stop()
        let routePoints = routeRecorder.points
        // Keep route persistence independent of the optional pedometer result.
        let saveRecord: (Int?, Double?) -> Void = { queriedSteps, queriedDistance in
            DispatchQueue.main.async {
                guard self.isFinishingSession, self.sessionStarted == start else { return }
                let finalSteps = queriedSteps ?? self.sessionSteps
                guard finalSteps != nil || !routePoints.isEmpty else {
                    // Do not discard an activity just because both sensors failed
                    // to return data. Keep the active session identity and durable
                    // route draft so the member can retry or recover it.
                    self.sessionSteps = nil
                    self.sessionStatus = "No verified step count or GPS points were received. Nothing was saved or counted. Your session remains available; retry after checking Motion and Location permissions."
                    self.isFinishingSession = false
                    return
                }
                let finalDistance = queriedDistance ?? self.sessionMotionDistanceMeters
                let record = ActivitySessionRecord(
                    id: recordID,
                    activity: activity,
                    startedAt: start,
                    finishedAt: finishedAt,
                    steps: finalSteps,
                    routePoints: routePoints,
                    motionDistanceMeters: finalDistance,
                    ownerID: self.routeRecorder.activityOwnerID
                )
                var history: [ActivitySessionRecord]
                do {
                    history = try self.activityStore.load()
                } catch {
                    // Never replace an unreadable history with an empty array.
                    self.sessionStatus = "Could not read existing activity history. Your current route draft is preserved; no saved history was replaced. You can retry saving."
                    self.isFinishingSession = false
                    return
                }
                if !history.contains(where: { $0.id == recordID }) {
                    history.insert(record, at: 0)
                }
                do {
                    // Atomic file replacement plus a read-back check protects the route draft.
                    try self.activityStore.save(history)
                    let persistedHistory = try self.activityStore.load()
                    guard persistedHistory.contains(where: { $0.id == recordID }) else {
                        throw NSError(domain: "GATIVXActivityStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "The saved activity could not be read back and verified. Your GPS draft remains preserved."])
                    }
                    self.activityHistory = persistedHistory
                    self.historyStatus = "Saved on this iPhone · \(persistedHistory.count) activities"
                    // Clear the durable GPS draft only after read-back verification
                    // confirms the completed session is safely stored.
                    self.routeRecorder.clearDraft()
                    self.sessionSteps = finalSteps
                    let stepSummary = finalSteps.map { $0.formatted() + " steps" } ?? "step count unavailable"
                    let routeSummary = routePoints.isEmpty ? "GPS route unavailable (0 points)" : "GPS route saved · " + String(format: "%.2f km", record.gpsDistanceMeters / 1000)
                    self.sessionStatus = activity + " saved · " + stepSummary + " · " + routeSummary
                    self.sessionStarted = nil
                    self.activeSessionID = nil
                    self.isFinishingSession = false
                    self.syncSavedActivitySessions()
                    self.health.saveActivityWorkout(
                        id: record.id,
                        activity: record.activity,
                        startedAt: record.startedAt,
                        finishedAt: record.finishedAt,
                        steps: record.steps,
                        distanceMeters: record.gpsDistanceMeters > 0 ? record.gpsDistanceMeters : record.motionDistanceMeters
                    ) { result in
                        switch result {
                        case .success:
                            self.sessionStatus = activity + " saved on this iPhone and exported to Apple Health · " + stepSummary + " · " + routeSummary
                            self.health.refreshOnForeground()
                        case .failure(let error):
                            self.sessionStatus = activity + " saved on this iPhone; Apple Health export needs attention: " + error.localizedDescription
                        }
                    }
                } catch {
                    self.sessionStatus = "Could not save this activity on this iPhone: " + error.localizedDescription + ". Your GPS draft remains preserved; tap Finish & save activity to retry."
                    self.sessionStarted = start
                    self.isFinishingSession = false
                }
            }
        }
        // Query the complete interval after stopping live updates so the final
        // motion samples are included even if the last callback was delayed.
        if CMPedometer.isStepCountingAvailable() {
            pedometer.queryPedometerData(from: start, to: finishedAt) { data, _ in
                saveRecord(data?.numberOfSteps.intValue, data?.distance?.doubleValue)
            }
        } else {
            saveRecord(nil, nil)
        }
    }

    /// Prefer HealthKit's all-source aggregate as the only displayed daily total.
    /// CoreMotion remains a separate iPhone-only live preview and is never
    /// presented as a substitute for the member's complete daily total.
    private var displayedDailySteps: Int? { health.todaySteps ?? liveMotionSteps }

    private var displayedStepSource: String {
        if health.todaySteps != nil { return "Apple Health · combined available sources" }
        if let liveMotionSteps { return "iPhone pedometer · since midnight · " + liveMotionSteps.formatted() + " steps" }
        return motionStatus
    }

    private var stepProgress: Double {
        guard let steps = displayedDailySteps else { return 0 }
        return min(Double(steps) / Double(max(dailyStepGoal, 1)), 1)
    }

    @AppStorage("gativx.appearance") private var appearanceMode = "system"
    @AppStorage("gativx.localModeEntered") private var localModeEntered = false
    @AppStorage("gativx.activeEnergyGoalKcal") private var activeEnergyGoalKcal = 500
    @AppStorage("gativx.heartPointsGoal") private var heartPointsGoal = 30
    @AppStorage("gativx.dailyStepGoal") private var dailyStepGoal = 10_000
    @State private var selectedTab = 0
    @State private var isGuruPresented = false
    @AppStorage("gativx.guru.goal") private var guruGoal = ""
    @AppStorage("gativx.guru.purpose") private var guruPurpose = ""
    @AppStorage("gativx.guru.emotion") private var guruEmotion = ""
    @AppStorage("gativx.guru.nextAction") private var guruNextAction = ""

    private var dashboardColorScheme: ColorScheme? {
        switch appearanceMode {
        case "day": return .light
        case "night": return .dark
        default: return nil
        }
    }

    private let neon = Color(red: 0.68, green: 0.98, blue: 0.12)
    private var pageBackground: Color { Color(uiColor: .systemGroupedBackground) }
    private var cardBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
    }

    private func metricCard(_ title: String, value: String, unit: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(neon)
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title2.weight(.bold).monospacedDigit())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var stepRing: some View {
        ZStack {
            Circle().stroke(neon.opacity(0.15), lineWidth: 15)
            Circle().trim(from: 0, to: stepProgress).stroke(neon, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: neon.opacity(0.35), radius: 9)
            VStack(spacing: 5) {
                Image(systemName: "figure.walk").font(.title2).foregroundStyle(neon)
                Text(displayedDailySteps?.formatted() ?? "—").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                Text("OF \(max(dailyStepGoal, 1).formatted()) STEPS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(displayedDailySteps.map { "\(Int(min(Double($0) / Double(max(dailyStepGoal, 1)), 1) * 100))% complete" } ?? "Waiting for data").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 190, height: 190)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's steps")
        .accessibilityValue(displayedDailySteps.map { "\($0) of \(max(dailyStepGoal, 1))" } ?? "No reading")
    }

    private var homeDashboard: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // GATIVX visual system: mountain hero, neon progress ring and
                // functional cards. Live values continue to come from HealthKit.
                ZStack(alignment: .top) {
                    GATIVXMountainBackdrop(isNight: appearanceMode == "night" || (appearanceMode == "system" && UITraitCollection.current.userInterfaceStyle == .dark))
                        .frame(height: 315)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 9) {
                            Image(systemName: "figure.hiking")
                                .font(.system(size: 27, weight: .black))
                                .foregroundStyle(neon)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("GATIVX®").font(.system(size: 27, weight: .black, design: .rounded)).tracking(-0.7)
                                Text("YOUR GOAL. YOUR PURPOSE. YOUR GATI.")
                                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.45)
                            }
                            Spacer()
                            Image(systemName: "bell.badge").font(.title2)
                            Image(systemName: "person.crop.circle.fill").font(.system(size: 34))
                                .padding(2).overlay(Circle().stroke(neon, lineWidth: 2))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting + "!").font(.system(size: 25, weight: .bold, design: .rounded))
                            Text(greeting == "Good morning" ? "Make today count." : "Stay on track.")
                                .font(.headline.weight(.medium))
                        }
                        HStack(alignment: .center, spacing: 12) {
                            stepRing
                                .frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 9) {
                                Image(systemName: "gift.fill").font(.title2).foregroundStyle(neon)
                                Text("Today's Mission").font(.subheadline.weight(.semibold))
                                Text("\(max(dailyStepGoal, 1).formatted()) steps").font(.title3.weight(.bold))
                                Image(systemName: "chevron.right.circle.fill").font(.title2).foregroundStyle(neon)
                            }
                            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.22), lineWidth: 1))
                        }
                    }
                    .padding(16)
                }
                HStack(spacing: 7) {
                    compactMetric("Distance", value: health.todayWalkingRunningDistanceKm.map { String(format: "%.1f", $0) } ?? "—", unit: "km", icon: "mappin.and.ellipse", tint: .green)
                    compactMetric("Active Time", value: health.todayExerciseMinutes.map(String.init) ?? "—", unit: "min", icon: "stopwatch", tint: .green)
                    compactMetric("Calories", value: health.todayActiveEnergyKcal.map(String.init) ?? "—", unit: "", icon: "flame.fill", tint: .orange)
                    compactMetric("Avg. Heart Rate", value: health.todayAverageHeartRateBPM.map(String.init) ?? "—", unit: "bpm", icon: "heart", tint: .pink)
                }
                wellnessMeters
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk").font(.system(size: 29, weight: .bold)).foregroundStyle(neon)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Activity Tracker").font(.headline)
                        Text("Track your walk, route, pace and progress.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                    Button { selectedTab = 1 } label: {
                        Label("START WALK", systemImage: "play.fill")
                            .font(.caption.weight(.black)).foregroundStyle(.black)
                            .padding(.horizontal, 13).padding(.vertical, 12)
                            .background(neon, in: Capsule())
                    }
                }
                .padding(15)
                .background(LinearGradient(colors: [neon.opacity(0.18), cardBackground], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(neon.opacity(0.45), lineWidth: 1))
                dashboardFeature(icon: "leaf", title: "Gati Guru", headline: "Remember why you started.", detail: "Small, consistent actions create extraordinary results.", action: { isGuruPresented = true })
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("My Journey", systemImage: "calendar").font(.headline)
                        Spacer()
                        Text("Your progress").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text("\(activityHistory.count) activities saved").font(.subheadline.weight(.semibold))
                    ProgressView(value: min(Double(visibleActivityHistory.count) / 90.0, 1.0))
                        .tint(neon)
                    Text(historyStatus.isEmpty ? "Your completed activities will appear here." : historyStatus)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
                dashboardFeature(icon: "person.3", title: "Community Gati", headline: "Grow together.", detail: "Challenges, inspiration and shared progress.", action: { selectedTab = 3 })
                VStack(alignment: .leading, spacing: 5) {
                    Text(displayedStepSource).font(.caption2).foregroundStyle(.secondary)
                    Text(health.statusMessage).font(.caption2).foregroundStyle(.secondary)
                    Text(motionStatus).font(.caption2).foregroundStyle(.secondary)
                    if !health.hasRequestedAccess {
                        Button { health.requestReadAccessAndStart() } label: {
                            Label("Connect Apple Health", systemImage: "heart.text.square")
                                .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }.buttonStyle(.borderedProminent).tint(.green)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 22)
        }
        .background(pageBackground.ignoresSafeArea())
        .accessibilityIdentifier("gativx-home-dashboard")
    }

    private func compactMetric(_ title: String, value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(tint)
            Text(value + (unit.isEmpty ? "" : " " + unit))
                .font(.system(size: 15, weight: .bold, design: .rounded)).minimumScaleFactor(0.65).lineLimit(1)
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 75)
        .padding(.vertical, 8)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.35), lineWidth: 0.7))
    }

    private func dashboardFeature(icon: String, title: String, headline: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 27, weight: .semibold)).foregroundStyle(neon).frame(width: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(headline).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right.circle.fill").font(.title2).foregroundStyle(neon)
            }
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(neon.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var activityScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity").font(.largeTitle.weight(.bold))
                Text("Record your movement. Your route and activity are saved locally before any cloud or Apple Health export.")
                    .font(.subheadline).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 13) {
                    Text("ACTIVITY TRACKER").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Picker("Activity", selection: $selectedActivity) {
                        ForEach(["Walking", "Running", "Hiking", "Other"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented)
                    HStack(alignment: .firstTextBaseline) {
                        Text(sessionSteps?.formatted() ?? "—").font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("session steps").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("GPS distance · " + String(format: "%.2f", routeRecorder.routeDistanceMeters / 1000) + " km")
                        .font(.subheadline.weight(.semibold))
                    Text("\(routeRecorder.points.count) GPS points · " + sessionStatus).font(.caption).foregroundStyle(.secondary)
                    if routeRecorder.authorization == .authorizedWhenInUse {
                        Button("Enable background GPS (Always location)") { routeRecorder.requestBackgroundLocationAccess() }.font(.caption)
                    }
                    if sessionStarted == nil {
                        if let recoveredStart = routeRecorder.recoveredStartedAt {
                            Text("Recovered activity from \(recoveredStart.formatted(date: .abbreviated, time: .shortened)).")
                                .font(.caption).foregroundStyle(.orange)
                            Button("Resume recovered activity") {
                                selectedActivity = routeRecorder.recoveredActivity ?? "Walking"
                                sessionStarted = recoveredStart
                                sessionSteps = nil
                                routeRecorder.resumeRecovered()
                                pedometer.startUpdates(from: recoveredStart) { data, error in
                                    DispatchQueue.main.async {
                                        if let error {
                                            self.sessionStatus = "Recovered GPS route is retained. Pedometer issue: \(error.localizedDescription)"
                                        } else {
                                            self.sessionSteps = data?.numberOfSteps.intValue
                                        }
                                    }
                                }
                                sessionStatus = routeRecorder.status
                            }.buttonStyle(.bordered)
                            Button("Save recovered route now") {
                                selectedActivity = routeRecorder.recoveredActivity ?? "Walking"
                                sessionStarted = recoveredStart
                                sessionSteps = nil
                                finishActivitySession()
                            }.buttonStyle(.bordered)
                        }
                        Button { startActivitySession() } label: {
                            Label("Start \(selectedActivity == "Walking" ? "Walk" : selectedActivity)", systemImage: "figure.walk")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        }.buttonStyle(.borderedProminent).tint(neon).foregroundStyle(.black)
                    } else {
                        Button(isFinishingSession ? "Saving activity…" : "Finish & save activity", role: .destructive) { finishActivitySession() }
                            .buttonStyle(.borderedProminent).disabled(isFinishingSession)
                    }
                    Text("GPS route recording is separate from step counting. Keep location permission enabled for route tracking.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
                Text("RECENT ACTIVITIES").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                if visibleActivityHistory.isEmpty {
                    Text(historyStatus.isEmpty ? "No completed activities saved yet." : historyStatus).foregroundStyle(.secondary)
                } else {
                    ForEach(visibleActivityHistory.prefix(20)) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(item.activity).font(.headline); Spacer(); Text(item.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                            HStack(spacing: 12) {
                                Label(item.steps.map { $0.formatted() } ?? "—", systemImage: "figure.walk")
                                Label(String(format: "%.2f km", item.gpsDistanceMeters / 1000), systemImage: "location")
                                Label(item.durationText, systemImage: "clock")
                            }.font(.caption).foregroundStyle(.secondary)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }.padding(16)
        }.background(pageBackground.ignoresSafeArea())
    }

    private var missionsScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Missions").font(.largeTitle.weight(.bold))
                VStack(alignment: .leading, spacing: 10) {
                    Text("TODAY · CONSISTENCY").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text("A little progress, every day.").font(.title2.weight(.bold))
                    Text("Walk at a comfortable pace, notice how you feel, and celebrate showing up.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Begin walking mission") { selectedTab = 1 }.buttonStyle(.borderedProminent).tint(neon).foregroundStyle(.black)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
                Text("Your goal progress").font(.headline)
                ProgressView(value: stepProgress).tint(neon)
                Text(displayedDailySteps.map { "\($0.formatted()) of \(max(dailyStepGoal, 1).formatted()) steps" } ?? "Waiting for a step reading").font(.caption).foregroundStyle(.secondary)
                Button("Open Gati Guru") { isGuruPresented = true }.buttonStyle(.bordered)
            }.padding(16)
        }.background(pageBackground.ignoresSafeArea())
    }

    private var guruScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("GATI GURU", systemImage: "leaf.fill")
                        .font(.caption.weight(.black)).foregroundStyle(neon)
                    Text("Reconnect with your why.")
                        .font(.largeTitle.weight(.bold))
                    Text("When motivation gets low, return to the purpose behind your goal. Guru keeps your reason visible and helps you choose one manageable next step.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR GOAL").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    TextField("What do you want to achieve?", text: $guruGoal, axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    Text("YOUR PURPOSE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    TextField("Why does this matter to you?", text: $guruPurpose, axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    Text("THE EMOTION BEHIND IT").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    TextField("How will achieving it make you feel?", text: $guruEmotion, axis: .vertical)
                        .lineLimit(2...3).textFieldStyle(.roundedBorder)
                    Text("ONE SMALL NEXT ACTION").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    TextField("What is one action you can do today?", text: $guruNextAction, axis: .vertical)
                        .lineLimit(2...3).textFieldStyle(.roundedBorder)
                    Text("Your answers are saved on this iPhone.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 10) {
                    Label("WHEN YOUR GATI SLOWS", systemImage: "heart.text.square.fill")
                        .font(.headline).foregroundStyle(neon)
                    Text(guruPurpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "Your purpose will appear here when you add it above."
                         : guruPurpose)
                        .font(.body.weight(.medium))
                    if !guruEmotion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Remember the feeling you are moving towards: " + guruEmotion)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(guruNextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "Choose one small action. Keep it realistic enough to begin today."
                         : "Your next step: " + guruNextAction)
                        .font(.subheadline.weight(.semibold))
                    Button {
                        selectedTab = 1
                    } label: {
                        Label("Go to Activity", systemImage: "figure.walk")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent).tint(neon).foregroundStyle(.black)
                }
                .padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
            }
            .padding(16)
        }
        .background(pageBackground.ignoresSafeArea())
    }

    private var communityScreen: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Community Gati").font(.largeTitle.weight(.bold))
            Text("Your journey can encourage someone else's first step.")
                .font(.title3.weight(.semibold))
            Text("Community feed and shared missions will be introduced here. No member activity or social data is fabricated.")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(pageBackground.ignoresSafeArea())
    }

    private var profileScreen: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    Text("Automatic").tag("system")
                    Text("Day").tag("day")
                    Text("Night").tag("night")
                }.pickerStyle(.segmented)
                Text("Automatic follows your iPhone appearance setting.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Apple Health") {
                Label(health.hasRequestedAccess ? "Connection requested" : "Not connected", systemImage: "heart.text.square")
                Text(health.statusMessage).font(.caption).foregroundStyle(.secondary)
                if !health.isWorkoutOutboxReadable {
                    Text("Apple Health workout export queue unreadable. Pending export count is unknown; local activity history remains saved.")
                        .font(.caption).foregroundStyle(.red)
                } else if health.pendingWorkoutExportCount > 0 {
                    Text("\(health.pendingWorkoutExportCount) workout export(s) waiting for Apple Health retry.")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Retry Apple Health exports") { health.retryPendingWorkoutExports() }
                }
                if !health.hasRequestedAccess {
                    Button("Connect Apple Health") { health.requestReadAccessAndStart() }.disabled(!health.isAvailable || health.isRefreshing)
                }
            }
            Section("Account") {
                if !cloud.isSignedIn {
                    TextField("Email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                    Button("Sign in and sync") { Task { await cloud.signIn(email: email, password: password) } }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                } else {
                    Label("Cloud account connected", systemImage: "checkmark.icloud")
                    Button("Sign out", role: .destructive) { cloud.signOut() }
                }
                Text(cloud.status).font(.caption).foregroundStyle(.secondary)
                if !cloud.isHealthOutboxReadable {
                    Text("Sensor sync queue unreadable. Pending count is unknown; original on-device data has been preserved.").font(.caption).foregroundStyle(.red)
                } else if cloud.pendingHealthSyncCount > 0 {
                    Text("\(cloud.pendingHealthSyncCount) sensor update(s) queued for retry.").font(.caption).foregroundStyle(.orange)
                }
            }
            Section("About GATIVX") {
                Text("From Goals to Xcellence")
                Text("Fitness guidance, not medical diagnosis or treatment.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func progressMeterCard(title: String, value: Int?, goal: Int, unit: String, symbol: String, tint: Color, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.bold))
                Spacer()
            }
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(tint.opacity(0.16), lineWidth: 9)
                    Circle().trim(from: 0, to: min(Double(value ?? 0) / Double(max(goal, 1)), 1))
                        .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: symbol).font(.title3.weight(.bold)).foregroundStyle(tint)
                }.frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value.map(String.init) ?? "—").font(.title2.weight(.bold).monospacedDigit())
                        Text(unit).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Goal: \(goal) \(unit)").font(.caption2).foregroundStyle(.secondary)
                    Text(value == nil ? "Waiting for measured data" : "\(Int(min(Double(value ?? 0) / Double(max(goal, 1)), 1) * 100))% of goal")
                        .font(.caption2.weight(.semibold)).foregroundStyle(tint)
                }
            }
            Text(explanation).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private var wellnessMeters: some View {
        HStack(alignment: .top, spacing: 10) {
            progressMeterCard(title: "Active Calories", value: health.todayActiveEnergyKcal,
                goal: max(activeEnergyGoalKcal, 1), unit: "kcal", symbol: "flame.fill", tint: .orange,
                explanation: "Measured active energy from Apple Health, not food calories.")
            progressMeterCard(title: "Heart Points", value: health.todayExerciseMinutes,
                goal: max(heartPointsGoal, 1), unit: "pts", symbol: "heart.fill", tint: .pink,
                explanation: "GATIVX exercise points: 1 point per Apple Exercise minute. Not Google's intensity-weighted score.")
        }
    }

    private var welcomeScreen: some View {
        ZStack {
            GATIVXMountainBackdrop(isNight: appearanceMode == "night").ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.walk").font(.system(size: 32, weight: .black)).foregroundStyle(neon)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("GATIVX").font(.system(size: 30, weight: .black, design: .rounded))
                            Text("FROM GOALS TO XCELLENCE").font(.caption2.weight(.heavy)).tracking(1.1)
                        }
                    }.padding(.top, 42)
                    Spacer(minLength: 20)
                    Text("Your health journey starts here.").font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Track movement, understand your progress and build healthier habits with a community that keeps you moving.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SIGN IN TO GATIVX").font(.caption.weight(.heavy)).tracking(1)
                        TextField("Email address", text: $email).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                            .padding(14).background(cardBackground, in: RoundedRectangle(cornerRadius: 13))
                        SecureField("Password", text: $password).textContentType(.password)
                            .padding(14).background(cardBackground, in: RoundedRectangle(cornerRadius: 13))
                        Button {
                            Task {
                                await cloud.signIn(email: email, password: password)
                                if cloud.isSignedIn { localModeEntered = true }
                            }
                        } label: {
                            HStack { Spacer(); Text("Sign in & sync").fontWeight(.bold); Spacer() }
                                .padding(15).foregroundStyle(.black).background(neon, in: Capsule())
                        }.disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                        HStack(spacing: 14) {
                            Button("Create account") {
                                Task { await cloud.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
                            }
                            .font(.subheadline.weight(.semibold))
                            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.count < 8)
                            Spacer(minLength: 4)
                            Button("Forgot password?") {
                                Task { await cloud.sendPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            }
                            .font(.subheadline.weight(.semibold))
                            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("Use at least 8 characters for a new password. Email verification may be required.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(cloud.status).font(.caption).foregroundStyle(.secondary)
                    }.padding(17).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    Button { localModeEntered = true } label: {
                        HStack { Spacer(); Text("Continue without account").fontWeight(.semibold); Spacer() }
                            .padding(14).background(cardBackground.opacity(0.88), in: Capsule())
                    }
                    Button { health.requestReadAccessAndStart() } label: {
                        Label("Connect Apple Health", systemImage: "heart.text.square")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(12)
                    }.buttonStyle(.bordered).tint(neon)
                    Text("You control your health permissions. Connect Apple Health now or later in Profile. Local-only use does not require an account.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 24)
                }.padding(.horizontal, 22)
            }
        }.preferredColorScheme(dashboardColorScheme)
    }

    var body: some View {
        Group {
            if cloud.isSignedIn || localModeEntered {
                TabView(selection: $selectedTab) {
            NavigationStack { homeDashboard.navigationTitle("").toolbar(.hidden, for: .navigationBar) }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            NavigationStack { activityScreen.navigationTitle("Activity") }
                .tabItem { Label("Activity", systemImage: "figure.walk") }.tag(1)
            NavigationStack { missionsScreen.navigationTitle("Missions") }
                .tabItem { Label("Missions", systemImage: "target") }.tag(2)
            NavigationStack { communityScreen.navigationTitle("Community") }
                .tabItem { Label("Community", systemImage: "person.3") }.tag(3)
            NavigationStack { profileScreen.navigationTitle("Profile") }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(4)
        }
                .sheet(isPresented: $isGuruPresented) {
                    NavigationStack {
                        guruScreen
                            .navigationTitle("Gati Guru")
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { isGuruPresented = false }
                                }
                            }
                    }
                }
                .tint(neon)
            } else {
                welcomeScreen
            }
        }
        .preferredColorScheme(dashboardColorScheme)
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
            health.retryPendingWorkoutExports()
            health.refreshOnForeground()
            startLiveMotionMonitor()
            loadActivityHistory()
            if cloud.isSignedIn {
                Task {
                    await cloud.retryPendingHealthSyncs()
                    await cloud.retryPendingActivitySessions()
                }
                syncSavedActivitySessions()
            }
            if let recoveredStart = routeRecorder.recoveredStartedAt {
                selectedActivity = routeRecorder.recoveredActivity ?? "Walking"
                sessionStatus = "Unfinished activity recovered from \(recoveredStart.formatted(date: .abbreviated, time: .shortened))."
            }
        }
        .onChange(of: cloud.isSignedIn) { _, signedIn in
            if signedIn {
                health.onDailyTotal = { day, total in Task { await cloud.syncSteps(date: day, steps: total) } }
                health.onActiveEnergy = { day, total in Task { await cloud.syncActiveEnergy(date: day, kilocalories: total) } }
                Task {
                    await cloud.retryPendingHealthSyncs()
                    await cloud.retryPendingActivitySessions()
                }
                health.refreshRecentDays()
                health.refreshTodayEnergy()
                syncCurrentMotionSnapshotToCloud()
                syncSavedActivitySessions()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                health.retryPendingWorkoutExports()
                health.refreshOnForeground()
                startLiveMotionMonitor()
                if cloud.isSignedIn {
                    Task {
                    await cloud.retryPendingHealthSyncs()
                    await cloud.retryPendingActivitySessions()
                }
                    syncCurrentMotionSnapshotToCloud()
                    syncSavedActivitySessions()
                }
            } else if sessionStarted == nil && !routeRecorder.isRecording {
                livePedometer.stopUpdates()
            }
        }
    }
}
