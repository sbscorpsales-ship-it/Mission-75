import SwiftUI
import CoreMotion
import CoreLocation

private struct ActivitySessionRecord: Codable, Identifiable { let id: UUID; let activity: String; let startedAt: Date; let finishedAt: Date; let steps: Int?; let routePoints: [GATIVXRoutePoint]?; let motionDistanceMeters: Double?; var gpsDistanceMeters: Double { guard let routePoints, routePoints.count > 1 else { return 0 }; return zip(routePoints, routePoints.dropFirst()).reduce(0.0) { total, pair in guard !pair.1.breakBefore else { return total }; let a = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude); let b = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude); return total + b.distance(from: a) } }; var durationText: String { let seconds = max(0, Int(finishedAt.timeIntervalSince(startedAt))); return String(format: "%d:%02d", seconds / 60, seconds % 60) } }

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
    private func loadActivityHistory() {
        let key = "gativx.activitySessions.v1"
        guard let data = UserDefaults.standard.data(forKey: key) else { historyStatus = "No completed activities saved yet."; return }
        do { activityHistory = try JSONDecoder().decode([ActivitySessionRecord].self, from: data); historyStatus = "Loaded saved activities from this iPhone." }
        catch { historyStatus = "Saved activity history could not be read. Existing data has been left untouched." }
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
        guard sessionStarted == nil, !isFinishingSession else { return }
        let start = Date()
        sessionStarted = start
        activeSessionID = UUID()
        sessionSteps = nil
        sessionMotionDistanceMeters = nil
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
                    self.routeRecorder.clearDraft()
                    self.sessionSteps = nil
                    self.sessionStatus = "No step count or GPS route points were recorded."
                    self.sessionStarted = nil
                    self.activeSessionID = nil
                    self.isFinishingSession = false
                    return
                }
                let finalDistance = queriedDistance ?? self.sessionMotionDistanceMeters
                let record = ActivitySessionRecord(id: recordID, activity: activity, startedAt: start, finishedAt: finishedAt, steps: finalSteps, routePoints: routePoints, motionDistanceMeters: finalDistance)
                let storageKey = "gativx.activitySessions.v1"
                let existingData = UserDefaults.standard.data(forKey: storageKey)
                var history: [ActivitySessionRecord]
                do {
                    history = try existingData.map { try JSONDecoder().decode([ActivitySessionRecord].self, from: $0) } ?? []
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
                    let encodedHistory = try JSONEncoder().encode(history)
                    UserDefaults.standard.set(encodedHistory, forKey: storageKey)
                    self.activityHistory = history
                    self.historyStatus = "Saved on this iPhone · \(history.count) activities"
                    guard UserDefaults.standard.data(forKey: storageKey) != nil else {
                        throw NSError(domain: "GATIVXActivityStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local activity history could not be verified after saving."])
                    }
                    // Clear the durable GPS draft only after the completed session
                    // has been encoded and stored successfully.
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
        return min(Double(steps) / 10_000, 1)
    }

    @AppStorage("gativx.appearance") private var appearanceMode = "system"
    @State private var selectedTab = 0

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
                Text("OF 10,000 STEPS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(displayedDailySteps.map { "\(Int(min(Double($0) / 10000, 1) * 100))% complete" } ?? "Waiting for data").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 190, height: 190)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's steps")
        .accessibilityValue(displayedDailySteps.map { "\($0) of 10000" } ?? "No reading")
    }

    private var homeDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("GATIVX").font(.system(size: 27, weight: .black, design: .rounded)).tracking(1.1)
                        Text("FROM GOALS TO XCELLENCE").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.6).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "bell.badge").font(.title3).padding(11).background(cardBackground, in: Circle())
                    Image(systemName: "person.crop.circle.fill").font(.title).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(greeting).font(.title2.weight(.bold))
                    Text("Every step moves you closer to your purpose.").font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(spacing: 14) {
                    HStack {
                        Label("TODAY'S JOURNEY", systemImage: "sun.max.fill").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                        Spacer()
                        Text(Date().formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                    stepRing
                    Text(displayedStepSource).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("Active energy  ·  " + (health.todayActiveEnergyKcal.map { "\($0) kcal" } ?? "—"))
                        .font(.subheadline.weight(.semibold))
                    if !health.hasRequestedAccess {
                        Button { health.requestReadAccessAndStart() } label: {
                            Label("Connect Apple Health", systemImage: "heart.text.square")
                                .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                        }.buttonStyle(.borderedProminent).tint(.primary).disabled(!health.isAvailable || health.isRefreshing)
                    }
                }
                .padding(18)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("TODAY'S MISSION").font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "sparkles").foregroundStyle(neon)
                    }
                    Text("Move with purpose").font(.title3.weight(.bold))
                    Text("Complete a mindful walk today. Start small, stay consistent, and reconnect with why you began.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button { selectedTab = 1 } label: {
                        HStack { Text("Start your mission"); Spacer(); Image(systemName: "arrow.up.right") }
                            .font(.subheadline.weight(.bold)).foregroundStyle(.black).padding(14)
                            .background(neon, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(17).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
                HStack(spacing: 12) {
                    metricCard("Live steps", value: liveMotionSteps?.formatted() ?? "—", unit: "steps", symbol: "figure.walk")
                    metricCard("Active energy", value: health.todayActiveEnergyKcal.map { String(Int($0)) } ?? "—", unit: "kcal", symbol: "flame")
                }
                HStack(spacing: 12) {
                    metricCard("Distance", value: liveMotionDistanceMeters.map { String(format: "%.2f", $0 / 1000) } ?? "—", unit: "km", symbol: "location")
                    metricCard("Heart rate", value: "—", unit: "bpm", symbol: "heart")
                }
                Text("Heart rate appears only when a supported real reading is available. GATIVX never invents health measurements.")
                    .font(.caption2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Label("GATI GURU", systemImage: "sparkles").font(.caption.weight(.bold)).foregroundStyle(neon)
                    Text("When motivation slows, remember your why.").font(.headline)
                    Text("One small action today is enough to regain your Gati.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 8) {
                    Label("MY JOURNEY", systemImage: "chart.line.uptrend.xyaxis").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text("\(activityHistory.count) activities saved").font(.headline)
                    Text(historyStatus.isEmpty ? "Your completed activities will be kept here." : historyStatus).font(.caption).foregroundStyle(.secondary)
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 8) {
                    Label("COMMUNITY GATI", systemImage: "person.3.fill").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text("Your consistency can inspire someone else.").font(.headline)
                    Text("Community experiences will appear here as this space grows.").font(.caption).foregroundStyle(.secondary)
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
                Text(health.statusMessage).font(.caption).foregroundStyle(.secondary)
                Text(motionStatus).font(.caption2).foregroundStyle(.secondary)
                Text("Fitness guidance, not medical diagnosis or treatment.").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
        }
        .background(pageBackground.ignoresSafeArea())
        .accessibilityIdentifier("gativx-home-dashboard")
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
                                    DispatchQueue.main.async { if error == nil { self.sessionSteps = data?.numberOfSteps.intValue } }
                                }
                                sessionStatus = "Recovered activity resumed. Finish to save the route."
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
                if activityHistory.isEmpty {
                    Text(historyStatus.isEmpty ? "No completed activities saved yet." : historyStatus).foregroundStyle(.secondary)
                } else {
                    ForEach(activityHistory.prefix(20)) { item in
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
                Text(displayedDailySteps.map { "\($0.formatted()) of 10,000 steps" } ?? "Waiting for a step reading").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.background(pageBackground.ignoresSafeArea())
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
                if cloud.pendingHealthSyncCount > 0 {
                    Text("\(cloud.pendingHealthSyncCount) sensor update(s) queued for retry.").font(.caption).foregroundStyle(.orange)
                }
            }
            Section("About GATIVX") {
                Text("From Goals to Xcellence")
                Text("Fitness guidance, not medical diagnosis or treatment.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
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
        .tint(neon)
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
            health.refreshOnForeground()
            startLiveMotionMonitor()
            loadActivityHistory()
            if cloud.isSignedIn {
                Task { await cloud.retryPendingHealthSyncs() }
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
                Task { await cloud.retryPendingHealthSyncs() }
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
                    Task { await cloud.retryPendingHealthSyncs() }
                    syncCurrentMotionSnapshotToCloud()
                    syncSavedActivitySessions()
                }
            } else if sessionStarted == nil && !routeRecorder.isRecording {
                livePedometer.stopUpdates()
            }
        }
    }
}
}
