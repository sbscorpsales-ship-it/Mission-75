import SwiftUI
import MapKit
import CoreMotion
import UniformTypeIdentifiers
import PhotosUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var health = HealthKitManager()
    @StateObject private var cloud = SupabaseRESTClient()
    @StateObject private var routeRecorder = GPSRouteRecorder()
    @State private var routeMapCameraPosition: MapCameraPosition = .automatic
    @State private var showLiveRouteMap = false
    private let activityStore = ActivitySessionStore()
    private let runJeetDailyStepsArchiveStore = RunJeetDailyStepsArchiveStore()
    private let memberProfilePhotoStore = MemberProfilePhotoStore()
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = true
    @AppStorage("gativx.motion.dailyTrackingEnabled") private var motionMonitoringEnabled = false
    @State private var pedometer = CMPedometer()
    @State private var livePedometer = CMPedometer()
    @State private var selectedActivity = "Walking"
    @State private var sessionSteps: Int?
    @State private var sessionMotionDistanceMeters: Double?
    @State private var activityHistory: [ActivitySessionRecord] = []
    @State private var historyStatus = ""
    @State private var isImportingRunJeetBackup = false
    @State private var pendingRunJeetImport: RunJeetBackupImport?
    @State private var pendingRunJeetImportName = ""
    @State private var showingRunJeetImportPreview = false
    @State private var runJeetImportAlert: String?
    @State private var runJeetDailyStepsArchive: [String: Int] = [:]
    @State private var runJeetArchiveStatus = "No RunJeet daily totals imported."
    @State private var sessionStarted: Date?
    @State private var isFinishingSession = false
    // Distinguishes an explicitly resumed recovered session from one saved as-is.
    @State private var recoveredSessionWasResumed = false
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
        guard motionMonitoringEnabled else {
            livePedometer.stopUpdates()
            motionStatus = "Daily iPhone step tracking is off. Enable Motion & Fitness in Profile to show live steps."
            return
        }
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
    private func updateMotionMonitoringPreference(_ enabled: Bool) {
        if enabled {
            motionMonitoringEnabled = true
            startLiveMotionMonitor()
        } else {
            motionMonitoringEnabled = false
            livePedometer.stopUpdates()
            liveMotionSteps = nil
            liveMotionDistanceMeters = nil
            motionStatus = "Daily iPhone step tracking is off. Your saved activities are unchanged."
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
                : "Loaded \(visibleCount) account-matched activities from this iPhone."
        } catch {
            historyStatus = "Saved activity history could not be read. Existing data has been left untouched."
        }
    }

    private func loadMemberProfilePhoto() {
        do {
            profilePhotoData = try memberProfilePhotoStore.load()
            if profilePhotoData != nil {
                profilePhotoStatus = "Member photo saved on this iPhone only."
            }
        } catch {
            // Keep an unreadable original file in place for recovery.
            profilePhotoStatus = "Saved member photo could not be read. The original file was preserved."
        }
    }

    @MainActor
    private func saveMemberProfilePhoto(_ item: PhotosPickerItem) async {
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self),
                  let sourceImage = UIImage(data: sourceData) else {
                profilePhotoStatus = "The selected photo could not be opened. Your current photo was not changed."
                return
            }

            let longestSide = max(sourceImage.size.width, sourceImage.size.height)
            guard longestSide > 0 else {
                profilePhotoStatus = "The selected photo has invalid dimensions. Your current photo was not changed."
                return
            }
            let scale = min(1, 512 / longestSide)
            let targetSize = CGSize(
                width: max(1, (sourceImage.size.width * scale).rounded(.down)),
                height: max(1, (sourceImage.size.height * scale).rounded(.down))
            )
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let resizedImage = renderer.image { _ in
                sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            guard let jpegData = resizedImage.jpegData(compressionQuality: 0.82) else {
                profilePhotoStatus = "The selected photo could not be prepared. Your current photo was not changed."
                return
            }

            try memberProfilePhotoStore.save(jpegData)
            profilePhotoData = jpegData
            profilePhotoStatus = "Member photo saved and verified on this iPhone. It is not uploaded."
        } catch {
            profilePhotoStatus = "Member photo was not changed: " + error.localizedDescription
        }
    }

    private func removeMemberProfilePhoto() {
        do {
            try memberProfilePhotoStore.delete()
            profilePhotoData = nil
            selectedProfilePhoto = nil
            profilePhotoStatus = "Member photo removed from this iPhone."
        } catch {
            profilePhotoStatus = "Member photo could not be removed: " + error.localizedDescription
        }
    }

    private func handleRunJeetBackupSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            runJeetImportAlert = "Could not open the selected backup: " + error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let backup = try RunJeetBackupImporter().decode(data)
                pendingRunJeetImport = backup
                pendingRunJeetImportName = url.lastPathComponent
                showingRunJeetImportPreview = true
            } catch {
                runJeetImportAlert = "The selected file was not imported: " + error.localizedDescription
            }
        }
    }

    private func commitRunJeetImport(assignToCurrentAccount: Bool) {
        guard let pendingRunJeetImport else { return }

        let ownerID: String?
        if assignToCurrentAccount {
            guard cloud.isSignedIn, let authenticatedUserID = cloud.authenticatedUserID else {
                runJeetImportAlert = "Sign in to the intended GATIVX account before choosing account sync. No data was changed."
                return
            }
            ownerID = authenticatedUserID
        } else {
            ownerID = nil
        }

        let importer = RunJeetBackupImporter()
        let importedRecords = importer.assigningOwnerID(ownerID, to: pendingRunJeetImport.activities)
        do {
            let archiveResult: RunJeetDailyStepsArchiveStore.MergeResult?
            if pendingRunJeetImport.dailyStepsByDay.isEmpty {
                archiveResult = nil
            } else {
                archiveResult = try runJeetDailyStepsArchiveStore.merge(pendingRunJeetImport.dailyStepsByDay)
                runJeetDailyStepsArchive = try runJeetDailyStepsArchiveStore.load()
                runJeetArchiveStatus = "\(runJeetDailyStepsArchive.count) historical day(s) archived locally; separate from Apple Health."
            }

            let existing = try activityStore.load()
            let existingIDs = Set(existing.map(\.id))
            let merged = importer.merging(importedRecords, into: existing)
            let newIDs = Set(importedRecords.map(\.id)).subtracting(existingIDs)

            try activityStore.save(merged)
            let verified = try activityStore.load()
            let verifiedIDs = Set(verified.map(\.id))
            guard newIDs.isSubset(of: verifiedIDs) else {
                throw NSError(
                    domain: "GATIVXRunJeetImport",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The imported activity history did not pass read-back verification."]
                )
            }

            activityHistory = verified
            historyStatus = "Saved activity history verified · \(visibleActivityHistory.count) activities visible for this account"
            if assignToCurrentAccount {
                syncSavedActivitySessions()
            }

            let destination = assignToCurrentAccount
                ? "this iPhone, linked to your signed-in GATIVX account"
                : "this iPhone only"
            let duplicateCount = importedRecords.count - newIDs.count
            let visibilityNote = (!assignToCurrentAccount && cloud.isSignedIn)
                ? " Local-only imports remain separate from the signed-in account and are hidden until you switch to guest mode."
                : ""
            let dailySummary: String
            if let archiveResult {
                dailySummary = " \(archiveResult.addedDays) historical daily total(s) archived on this iPhone; \(archiveResult.preservedExistingDays) existing date(s) kept unchanged. These totals are not merged into Apple Health or cloud step totals."
            } else {
                dailySummary = " No historical daily totals were present in this backup."
            }
            runJeetImportAlert = "Import verified: \(newIDs.count) new activity session(s) saved to \(destination); \(duplicateCount) duplicate session(s) were left unchanged." + dailySummary + visibilityNote
        } catch {
            runJeetImportAlert = "Import could not be fully verified: " + error.localizedDescription + ". Any daily totals already archived remain safe; re-import the same backup to retry without duplicating sessions. Keep the original backup."
        }
        self.pendingRunJeetImport = nil
    }

    private func loadRunJeetDailyStepsArchive() {
        // Imported history can contain many dates. Never decode and validate the
        // archive synchronously while SwiftUI is presenting the Profile tab.
        let store = runJeetDailyStepsArchiveStore
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try store.load() }
            DispatchQueue.main.async {
                switch result {
                case .success(let archive):
                    runJeetDailyStepsArchive = archive
                    runJeetArchiveStatus = archive.isEmpty
                        ? "No RunJeet daily totals imported."
                        : "\(archive.count) historical day(s) archived locally; separate from Apple Health."
                case .failure:
                    // An unreadable archive is never treated as an empty archive;
                    // the store leaves the original file untouched.
                    runJeetArchiveStatus = "Imported daily-step archive could not be read. Original data was preserved."
                }
            }
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
        // Metadata-only imported sessions have no deliverable step or route payload:
        // keep them in account-linked local history instead of creating a stuck cloud retry.
        let accountRecords = history.filter { $0.ownerID == ownerID }
        for record in accountRecords where record.hasCloudSyncPayload {
            cloud.enqueueActivitySession(record)
        }
        let localOnlyCount = accountRecords.filter { !$0.hasCloudSyncPayload }.count
        if localOnlyCount > 0 {
            historyStatus = "Account-linked history saved on this iPhone; \(localOnlyCount) session(s) have no measured steps or GPS route and were not queued for cloud sync."
        }
        Task { await cloud.retryPendingActivitySessions() }
    }
    private func startActivitySession() {
        guard sessionStarted == nil,
              !isFinishingSession,
              routeRecorder.recoveredStartedAt == nil,
              !routeRecorder.hasUnreadableDraft else { return }
        let start = Date()
        sessionStarted = start
        activeSessionID = UUID()
        recoveredSessionWasResumed = false
        sessionSteps = nil
        sessionMotionDistanceMeters = nil
        // GPS recording is independent of the motion sensor. A device without
        // CMPedometer must still be able to record and save a complete route.
        routeRecorder.start(activity: selectedActivity, ownerID: cloud.authenticatedUserID)
        activeSessionID = routeRecorder.activitySessionID
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
        let recordID = routeRecorder.activitySessionID ?? activeSessionID ?? UUID()
        activeSessionID = recordID
        sessionStatus = "Finishing activity and saving your route…"
        // A recovered draft saved without resuming GPS ends at its last GPS fix;
        // app-termination time is not counted as active workout duration.
        let recoveredWithoutResume = routeRecorder.recoveredStartedAt != nil && !recoveredSessionWasResumed
        let finishedAt = ActivitySessionFinishPolicy.effectiveFinishDate(
            now: Date(),
            startedAt: start,
            lastRoutePointAt: routeRecorder.points.last?.timestamp,
            recoveredWithoutResume: recoveredWithoutResume
        )
        let activity = selectedActivity
        pedometer.stopUpdates()
        routeRecorder.stop()
        let routePoints = routeRecorder.points
        // Keep route persistence independent of the optional pedometer result.
        let saveRecord: (Int?, Double?) -> Void = { queriedSteps, queriedDistance in
            DispatchQueue.main.async {
                guard self.isFinishingSession, self.sessionStarted == start else { return }
                // A HealthKit/pedometer re-query can legitimately return zero or lag the live stream.
                // Never let that lower a verified in-session count; retain the highest non-negative reading.
                let finalSteps = ActivitySessionFinishPolicy.highestMeasuredSteps(queried: queriedSteps, live: self.sessionSteps)
                guard finalSteps != nil || !routePoints.isEmpty else {
                    // Do not discard an activity just because both sensors failed
                    // to return data. Keep the active session identity and durable
                    // route draft so the member can retry or recover it.
                    self.sessionSteps = nil
                    // Keep the original session ID and draft, and resume GPS so
                    // the member can continue recording after a sensor/permission failure.
                    self.recoveredSessionWasResumed = true
                    self.routeRecorder.resumeRecovered()
                    self.sessionStatus = "No verified step count or GPS points were received. Nothing was saved or counted. Your session remains available. " + self.routeRecorder.status + " Check Motion & Location permissions, then retry Finish & Save."
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
                // Reconcile a crash-recovered copy with the already-written session.
                // Do not clear the GPS draft until this merged record is verified on disk.
                history = self.activityStore.upserting(record, into: history)
                do {
                    // Atomic file replacement plus a read-back check protects the route draft.
                    try self.activityStore.save(history)
                    let persistedHistory = try self.activityStore.load()
                    guard persistedHistory.contains(where: { $0.id == recordID }) else {
                        throw NSError(domain: "GATIVXActivityStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "The saved activity could not be read back and verified. Your GPS draft remains preserved."])
                    }
                    self.activityHistory = persistedHistory
                    self.historyStatus = "Saved on this iPhone · \(self.visibleActivityHistory.count) activities for this account"
                    self.sessionSteps = finalSteps
                    let stepSummary = finalSteps.map { $0.formatted() + " steps" } ?? "step count unavailable"
                    let routeSummary = routePoints.isEmpty ? "GPS route unavailable (0 points)" : "GPS route saved · " + String(format: "%.2f km", record.gpsDistanceMeters / 1000)
                    self.sessionStatus = activity + " saved · " + stepSummary + " · " + routeSummary
                    self.sessionStarted = nil
                    self.activeSessionID = nil
                    self.isFinishingSession = false
                    self.syncSavedActivitySessions()
                    let healthExportQueued = self.health.saveActivityWorkout(
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
                    if healthExportQueued {
                        // The export outbox accepted and read back this stable session ID.
                        // A later HealthKit permission/export failure remains retryable there.
                        self.routeRecorder.clearDraft()
                        self.recoveredSessionWasResumed = false
                    } else {
                        // Local history is verified, but the export queue could not be
                        // written/read back. Keep the GPS draft and the same session ID
                        // active so Finish & Save can retry queue creation without duplicating history.
                        self.sessionStarted = start
                        self.activeSessionID = recordID
                        self.isFinishingSession = false
                        self.sessionStatus = activity + " saved on this iPhone; Apple Health export could not be queued. Your GPS draft remains preserved. Tap Finish & save activity to retry."
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
    @State private var isProfilePhotoPickerPresented = false
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var profilePhotoData: Data?
    @State private var profilePhotoStatus = "No member photo selected."
    @State private var isGuruPresented = false
    private enum GuruField: Hashable { case goal, purpose, emotion, nextAction, mealNote }
    @FocusState private var focusedGuruField: GuruField?
    @State private var isNotificationsPresented = false
    @AppStorage("gativx.guru.goal") private var guruGoal = ""
    @AppStorage("gativx.guru.purpose") private var guruPurpose = ""
    @AppStorage("gativx.guru.emotion") private var guruEmotion = ""
    @AppStorage("gativx.guru.nextAction") private var guruNextAction = ""
    @AppStorage("gativx.guru.walkingDoneDate") private var guruWalkingDoneDate = ""
    @AppStorage("gativx.guru.nutritionDoneDate") private var guruNutritionDoneDate = ""
    @AppStorage("gativx.guru.recoveryCheckInDate") private var guruRecoveryCheckInDate = ""
    @AppStorage("gativx.guru.recoveryFeeling") private var guruRecoveryFeeling = "Not checked in"
    @AppStorage("gativx.guru.mealNote") private var guruMealNote = ""
    @AppStorage("gativx.journey.durationDays") private var guruJourneyDurationDays = 90
    @AppStorage("gativx.journey.activeDurationDays") private var guruActiveJourneyDurationDays = 0
    @AppStorage("gativx.journey.startedAt") private var guruJourneyStartedAt = 0.0
    @AppStorage("gativx.journey.goal") private var guruJourneyGoal = ""

    private var activeGuruJourney: GATIVXGoalJourney? {
        guard guruJourneyStartedAt > 0 else { return nil }
        return GATIVXGoalJourney(
            durationDays: guruActiveJourneyDurationDays > 0 ? guruActiveJourneyDurationDays : guruJourneyDurationDays,
            startedAt: Date(timeIntervalSince1970: guruJourneyStartedAt),
            now: Date()
        )
    }

    private var guruSuggestedNextAction: String {
        GATIVXGuruCoach.suggestedNextAction(
            goal: guruGoal,
            purpose: guruPurpose,
            emotion: guruEmotion,
            dailySteps: displayedDailySteps,
            dailyStepGoal: dailyStepGoal
        )
    }

    private var guruPurposeAnchor: String {
        GATIVXGuruCoach.purposeAnchor(goal: guruGoal, purpose: guruPurpose, emotion: guruEmotion)
    }

    /// Use SwiftUI's focus binding as the single source of truth for Guru input.
    /// Every Guru text field shares this binding, so the keyboard toolbar and
    /// sheet dismissal do not need a second UIKit responder-resign path.
    private func dismissGuruKeyboard() {
        focusedGuruField = nil
    }

    private var guruTodayKey: String {
        let date = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(date.year ?? 0)-\(date.month ?? 0)-\(date.day ?? 0)"
    }

    private var guruWalkingDoneToday: Bool { guruWalkingDoneDate == guruTodayKey }
    private var guruNutritionDoneToday: Bool { guruNutritionDoneDate == guruTodayKey }
    private var guruRecoveryCheckedToday: Bool { guruRecoveryCheckInDate == guruTodayKey }

    private var guruWalkingGuidance: String {
        guard let steps = displayedDailySteps else {
            return "No verified step reading is available yet. Connect Apple Health or enable iPhone Motion & Fitness tracking. Until then, choose a comfortable walk and let GATIVX record it."
        }
        let remaining = max(0, dailyStepGoal - steps)
        if remaining == 0 {
            return "You have reached your step target. You do not need to chase extra steps. Notice how you feel and keep tomorrow achievable."
        }
        if remaining <= 500 {
            return "Only \(remaining.formatted()) measured steps remain. If you feel comfortable, a relaxed 3–5 minute walk may help you finish."
        }
        if remaining <= 2_000 {
            return "You have \(remaining.formatted()) measured steps remaining. Consider one comfortable 10-minute walk, then review your progress."
        }
        return "Your target is a guide, not a test. Start with 10 comfortable minutes. If that feels manageable, add another short walk later."
    }

    private var guruNutritionGuidance: String {
        "For your next meal, aim for variety: vegetables and fruit, a sensible whole-grain portion, and a satisfying protein source such as dal, beans, curd, paneer, tofu or nuts. Drink water regularly. Your needs are individual; Guru does not prescribe a medical diet."
    }

    private var guruRecoveryGuidance: String {
        switch guruRecoveryFeeling {
        case "Tired":
            return "Choose recovery over pressure today. Consider an easier walk, gentle mobility or rest. If you feel unwell, dizzy or have unusual pain, stop exercising and seek appropriate medical advice."
        case "Rested":
            return "Good to hear you feel rested. Build gradually and keep the effort comfortable. Recovery is part of progress, not time lost."
        case "Okay":
            return "Keep today's plan steady and comfortable. Notice energy, soreness and mood; reduce intensity if your body asks for it."
        default:
            return "Check in honestly before choosing your effort. Guru will not guess your sleep or recovery from missing data."
        }
    }

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's steps")
        .accessibilityValue(displayedDailySteps.map { "\($0) of \(max(dailyStepGoal, 1))" } ?? "No reading")
    }

    private var dashboardIsNight: Bool {
        appearanceMode == "night" ||
        (appearanceMode == "system" && colorScheme == .dark)
    }

    private var homeDashboard: some View {
        GeometryReader { geometry in
            homeDashboardContent(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityIdentifier("gativx-home-dashboard")
    }

    private func homeDashboardContent(width: CGFloat, height: CGFloat) -> some View {
        let horizontalInset = min(max(width * 0.035, 12), 18)
        let contentWidth = max(width - horizontalInset * 2, 0)
        let titleWidth = max(contentWidth - 34 - 34 - 32 - 36 - 24, 88)
        let heroHeight = min(max(width * 0.49, 178), 204)
        let spacing: CGFloat = height < 780 ? 12 : 15

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: spacing) {
                dashboardHeader(width: width, titleWidth: titleWidth, heroHeight: heroHeight)
                dailyStepCounterCard(width: width)
                wellnessMeters
                todayMissionCard
                todayActivityCard
                activityTrackerCard
                guruEntryCard
                myJourneyCard
                communityGatiCard
            }
            .padding(.horizontal, horizontalInset)
            .padding(.top, 10)
            .padding(.bottom, 28)
            .frame(width: width, alignment: .leading)
        }
        
        .background(pageBackground.ignoresSafeArea())
        .accessibilityIdentifier("gativx-home-dashboard")
    }

    private func dashboardHeader(width: CGFloat, titleWidth: CGFloat, heroHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            GATIVXMountainBackdrop(isNight: dashboardIsNight)
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(neon).frame(width: 34, height: 34)
                        Image(systemName: "figure.run").font(.system(size: 19, weight: .black)).foregroundStyle(.black)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("GATIVX")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .tracking(-0.7)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text("YOUR GOAL. YOUR PURPOSE. YOUR GATI.")
                            .font(.system(size: 6.5, weight: .heavy))
                            .tracking(0.45)
                            .lineLimit(1)
                            .minimumScaleFactor(0.45)
                    }
                    .frame(width: titleWidth, alignment: .leading)
                    .clipped()
                    Button { isNotificationsPresented = true } label: {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Notifications")
                    .accessibilityIdentifier("gativx-header-notifications")
                    Button { selectedTab = 4 } label: {
                        Group {
                            if let data = profilePhotoData, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().padding(3)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                        .padding(2)
                        .overlay(Circle().stroke(neon, lineWidth: 1.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open member profile")
                    .accessibilityIdentifier("gativx-header-profile")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text(greeting + " 👋")
                        .font(.system(size: min(max(width * 0.062, 22), 26), weight: .bold, design: .rounded))
                    Text("Every step moves you closer to your purpose.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(cloud.isSignedIn
                         ? "LOGIN ID · " + (cloud.authenticatedUserEmail ?? "SIGNED-IN MEMBER")
                         : "LOCAL-ONLY MEMBER")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(.white.opacity(0.86))
                        .accessibilityIdentifier("gativx-dashboard-member-identity")
                }
            }
            .foregroundStyle(.white)
            .padding(17)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gativx-dashboard-header")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dailyStepDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TODAY'S STEPS").font(.caption.weight(.heavy)).tracking(0.9).foregroundStyle(.secondary)
            Text("Daily movement").font(.title3.weight(.bold))
            Text(max(dailyStepGoal, 1).formatted() + " step goal")
                .font(.subheadline.weight(.semibold))
            Text(displayedDailySteps.map {
                $0 >= dailyStepGoal
                    ? "Goal achieved. Brilliant work!"
                    : "\((max(dailyStepGoal - $0, 0)).formatted()) steps to go"
            } ?? "Connect Apple Health or enable iPhone step tracking.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func dailyStepCounterLayout(width: CGFloat, ringDiameter: CGFloat) -> some View {
        if width < 430 {
            VStack(spacing: 12) {
                stepRing.frame(width: ringDiameter, height: ringDiameter)
                dailyStepDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 14) {
                stepRing.frame(width: ringDiameter, height: ringDiameter)
                dailyStepDetails
            }
        }
    }

    private func dailyStepCounterCard(width: CGFloat) -> some View {
        let ringDiameter = min(max(width * 0.34, 128), 148)
        return dailyStepCounterLayout(width: width, ringDiameter: ringDiameter)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(neon.opacity(0.5), lineWidth: 1))
            .accessibilityIdentifier("gativx-daily-step-counter")
    }

    private var todayMissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("TODAY'S MISSION", systemImage: "flag.checkered")
                    .font(.caption.weight(.heavy)).tracking(0.8)
                Spacer()
                Text("01 / DAILY").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
            Text("Move with purpose.").font(.title2.weight(.bold))
            Text("Reach your daily movement goal one step at a time. Consistency matters more than perfection.")
                .font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: stepProgress).tint(neon)
            HStack {
                Text(displayedDailySteps.map { "\($0.formatted()) steps completed" } ?? "Waiting for step data")
                Spacer()
                Text("\(Int(stepProgress * 100))%").fontWeight(.bold)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gativx-todays-mission")
    }

    private var todayActivityCard: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY'S ACTIVITY").font(.caption.weight(.heavy)).tracking(0.9).foregroundStyle(.secondary)
                Spacer()
                Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                wellnessSnapshotCard(
                    "Distance",
                    value: health.todayWalkingRunningDistanceKm.map { String(format: "%.2f", $0) } ?? "—",
                    unit: "km", symbol: "figure.walk", tint: .green
                )
                wellnessSnapshotCard(
                    "Active time",
                    value: health.todayExerciseMinutes.map(String.init) ?? "—",
                    unit: "min", symbol: "stopwatch.fill", tint: .orange
                )
                wellnessSnapshotCard(
                    "Calories",
                    value: health.todayActiveEnergyKcal.map(String.init) ?? "—",
                    unit: "kcal", symbol: "flame.fill", tint: .pink
                )
                wellnessSnapshotCard(
                    "Avg. heart rate",
                    value: health.todayAverageHeartRateBPM.map(String.init) ?? "—",
                    unit: "bpm", symbol: "heart.fill", tint: .red
                )
            }
            Text("Measured values from Apple Health. Unavailable readings are not estimated.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var activityTrackerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ACTIVITY TRACKER", systemImage: "figure.walk")
                .font(.caption.weight(.heavy)).tracking(0.9).foregroundStyle(.secondary)
            Text(routeRecorder.hasUnreadableDraft
                 ? "Your previous route needs recovery."
                 : "Ready for your next walk?")
                .font(.headline)
            Button {
                // Home is navigation only. GPS and pedometer recording begin
                // only after the member explicitly starts an activity on Activity.
                selectedTab = 1
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk").font(.headline.weight(.black))
                    Text(sessionStarted != nil
                         ? "CONTINUE WALK"
                         : routeRecorder.hasUnreadableDraft
                            ? "RECOVERY NEEDED"
                            : routeRecorder.recoveredStartedAt != nil
                                ? "RECOVER WALK"
                                : "START WALK")
                        .font(.headline.weight(.black)).tracking(0.6)
                    Spacer()
                    Image(systemName: "arrow.right").font(.headline.weight(.bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(neon, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gativx-start-walk")
            Text("Track steps, active time and your GPS route.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var guruEntryCard: some View {
        Button { isGuruPresented = true } label: {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "sparkles").font(.system(size: 27, weight: .bold)).foregroundStyle(neon).frame(width: 38)
                VStack(alignment: .leading, spacing: 5) {
                    Text("GATI GURU").font(.caption.weight(.heavy)).tracking(1).foregroundStyle(.secondary)
                    Text("Reconnect with your why.").font(.headline)
                    Text(guruPurpose.isEmpty
                         ? "Your purpose, your emotion and one small next action."
                         : guruPurpose)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("gativx-guru-entry")
    }

    private var myJourneyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("MY JOURNEY", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.heavy)).tracking(0.8)
                Spacer()
                Button("View all") { selectedTab = 1 }.font(.caption.weight(.bold))
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(visibleActivityHistory.count)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                Text("activities saved")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            if let latest = visibleActivityHistory.first {
                HStack {
                    Image(systemName: "figure.walk.circle.fill").font(.title2).foregroundStyle(neon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(latest.activity).font(.subheadline.weight(.bold))
                        Text(latest.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(latest.durationText).font(.caption.weight(.semibold))
                }
                .padding(11).background(pageBackground, in: RoundedRectangle(cornerRadius: 14))
            } else {
                Text("Your completed walks will appear here after you save your first activity.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text(historyStatus).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var communityGatiCard: some View {
        Button { selectedTab = 3 } label: {
            HStack(spacing: 13) {
                Image(systemName: "person.3.fill").font(.system(size: 25, weight: .semibold)).foregroundStyle(neon).frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMMUNITY GATI").font(.caption.weight(.heavy)).tracking(0.9).foregroundStyle(.secondary)
                    Text("Move forward, together.").font(.headline)
                    Text("Community feed is not active yet. Your personal activity remains private.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func wellnessSnapshotCard(_ title: String, value: String, unit: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 38, height: 38).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value) \(unit)")
        .accessibilityIdentifier("gativx-metric-\(title == "Distance" ? "distance" : title == "Active time" ? "active-time" : title == "Calories" ? "calories" : "average-heart-rate")")
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

    private var routeCoordinateSegments: [[CLLocationCoordinate2D]] {
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        for point in routeRecorder.points {
            if point.breakBefore && !current.isEmpty { segments.append(current); current = [] }
            current.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    private var routeMapRegion: MKCoordinateRegion {
        let points = routeRecorder.points
        guard !points.isEmpty else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20.5937, longitude: 78.9629), span: MKCoordinateSpan(latitudeDelta: 18, longitudeDelta: 18))
        }
        let lats = points.map(\.latitude); let lons = points.map(\.longitude)
        let minLat = lats.min() ?? 0; let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0; let maxLon = lons.max() ?? 0
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2), span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.8, 0.002), longitudeDelta: max((maxLon - minLon) * 1.8, 0.002)))
    }

    private var liveRouteMap: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $routeMapCameraPosition) {
                ForEach(Array(routeCoordinateSegments.enumerated()), id: \.offset) { _, segment in
                    if segment.count > 1 { MapPolyline(coordinates: segment).stroke(neon, lineWidth: 5) }
                }
                if let first = routeRecorder.points.first {
                    Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)) {
                        Image(systemName: "flag.fill").font(.caption).foregroundStyle(.white).padding(7).background(Color.green, in: Circle())
                    }
                }
                if let last = routeRecorder.points.last {
                    Annotation("You", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                        Circle().fill(neon).frame(width: 16, height: 16).overlay(Circle().stroke(.black, lineWidth: 2))
                    }
                }
            }
            .mapControls { MapCompass() }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear {
                if !routeRecorder.points.isEmpty {
                    routeMapCameraPosition = .region(routeMapRegion)
                }
            }
            .onChange(of: routeRecorder.points.count) { _, newCount in
                guard newCount > 0 else { return }
                routeMapCameraPosition = .region(routeMapRegion)
            }
            if routeRecorder.points.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "location.slash").font(.title2)
                    Text(routeRecorder.isRecording ? "Waiting for GPS signal…" : "Your walking route will appear here").font(.caption.weight(.semibold))
                    Text("Allow Location access and move outdoors for a clear GPS fix.").font(.caption2)
                }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Label("\(routeRecorder.points.count) GPS fixes · " + String(format: "%.2f km", routeRecorder.routeDistanceMeters / 1000), systemImage: "location.fill")
                .font(.caption.weight(.bold)).padding(9).background(.regularMaterial, in: Capsule()).padding(10)
        }.frame(height: 250).accessibilityLabel("Live GPS route map")
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
                    if showLiveRouteMap || routeRecorder.isRecording || !routeRecorder.points.isEmpty {
                        liveRouteMap
                    } else {
                        Button {
                            showLiveRouteMap = true
                        } label: {
                            Label("Show live GPS map", systemImage: "map")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(neon)
                        .accessibilityIdentifier("gativx-show-live-route-map")
                    }
                    Text(routeRecorder.hasUnreadableDraft ? routeRecorder.status : sessionStatus).font(.caption).foregroundStyle(.secondary)
                    if routeRecorder.isRecording { Label("Live route recording", systemImage: "record.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.green) }
                    if routeRecorder.authorization == .authorizedWhenInUse {
                        Button("Enable background GPS (Always location)") { routeRecorder.requestBackgroundLocationAccess() }.font(.caption)
                    }
                    if sessionStarted == nil {
                        if routeRecorder.hasUnreadableDraft {
                            Text("The original GPS draft is preserved. New walks are disabled until this draft can be recovered.")
                                .font(.caption).foregroundStyle(.orange)
                        } else if let recoveredStart = routeRecorder.recoveredStartedAt {
                            Text("Recovered activity from \(recoveredStart.formatted(date: .abbreviated, time: .shortened)).")
                                .font(.caption).foregroundStyle(.orange)
                            Button("Resume recovered activity") {
                                selectedActivity = routeRecorder.recoveredActivity ?? "Walking"
                                sessionStarted = recoveredStart
                                sessionSteps = nil
                                recoveredSessionWasResumed = true
                                routeRecorder.resumeRecovered()
                                activeSessionID = routeRecorder.activitySessionID
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
                                activeSessionID = routeRecorder.activitySessionID
                                sessionSteps = nil
                                finishActivitySession()
                            }.buttonStyle(.bordered)
                        } else {
                            Button { startActivitySession() } label: {
                                Label("Start \(selectedActivity == "Walking" ? "Walk" : selectedActivity)", systemImage: "figure.walk")
                                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                            }.buttonStyle(.borderedProminent).tint(neon).foregroundStyle(.black)
                        }
                    } else {
                        Button(isFinishingSession ? "Saving activity…" : "Finish & save activity", role: .destructive) { finishActivitySession() }
                            .buttonStyle(.borderedProminent).disabled(isFinishingSession)
                    }
                    Text("GPS route recording is separate from step counting. Keep location permission enabled for route tracking.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
                HStack {
                    Text("RECENT ACTIVITIES").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        isImportingRunJeetBackup = true
                    } label: {
                        Label("Import backup", systemImage: "square.and.arrow.down")
                            .font(.caption.weight(.semibold))
                    }
                }
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(pageBackground.ignoresSafeArea())
        .accessibilityIdentifier("gativx-activity-screen")
        .fileImporter(
            isPresented: $isImportingRunJeetBackup,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleRunJeetBackupSelection
        )
        .confirmationDialog(
            "Import \(pendingRunJeetImportName)?",
            isPresented: $showingRunJeetImportPreview,
            titleVisibility: .visible
        ) {
            Button("Import to this iPhone") {
                commitRunJeetImport(assignToCurrentAccount: false)
            }
            if cloud.isSignedIn {
                Button("Import & sync to this account") {
                    commitRunJeetImport(assignToCurrentAccount: true)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingRunJeetImport = nil
            }
        } message: {
            Text("Found \(pendingRunJeetImport?.activities.count ?? 0) activity session(s) and \(pendingRunJeetImport?.dailyStepsByDay.count ?? 0) historical daily total(s). Daily totals are archived separately on this iPhone and are not merged into Apple Health. Existing session IDs and archived dates are preserved. Choose account sync only if this backup belongs to the account currently signed in.")
        }
        .alert("RunJeet backup", isPresented: Binding(
            get: { runJeetImportAlert != nil },
            set: { if !$0 { runJeetImportAlert = nil } }
        )) {
            Button("OK", role: .cancel) { runJeetImportAlert = nil }
        } message: {
            Text(runJeetImportAlert ?? "")
        }
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
                Button("Open GATIVX Guru") { isGuruPresented = true }.buttonStyle(.bordered)
            }.padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(pageBackground.ignoresSafeArea())
        .accessibilityIdentifier("gativx-missions-screen")
    }

    private func guruMetricCard(title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).font(.title3.weight(.bold)).foregroundStyle(neon)
            Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(13)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var guruHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: "sparkles").font(.system(size: 27, weight: .black)).foregroundStyle(neon)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GATIVX GURU").font(.caption.weight(.black)).tracking(1.3).foregroundStyle(neon)
                    Text("NURUN · YOUR PERSONAL GUIDE").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                }
                Spacer()
                Text("GATIVX").font(.caption.weight(.heavy)).tracking(1)
            }
            Text("Your goal. Your reason. Your next step.")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("gativx-guru-heading")
            Text("Guru connects your walking, everyday food habits and recovery with the goal you chose. When your Gati slows, it brings you back to your WHY and helps you take one achievable action.")
                .font(.subheadline).foregroundStyle(.secondary)
            if !guruPurpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("“\(guruPurpose)”")
                    .font(.body.weight(.semibold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(neon.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var guruTodaySignalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("TODAY'S SIGNALS", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.heavy)).tracking(0.8).foregroundStyle(neon)
                Spacer()
                Text(health.hasRequestedAccess ? "APPLE HEALTH" : "ON-DEVICE DATA")
                    .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                guruMetricCard(title: "Steps", value: displayedDailySteps.map { $0.formatted() } ?? "—",
                    detail: displayedDailySteps == nil ? "Waiting for a verified reading" : "Goal · \(dailyStepGoal.formatted())",
                    symbol: "figure.walk")
                guruMetricCard(title: "Distance", value: health.todayWalkingRunningDistanceKm.map { String(format: "%.2f km", $0) } ?? "—",
                    detail: health.todayWalkingRunningDistanceKm == nil ? "No measured total available" : "Walking + running",
                    symbol: "point.topleft.down.curvedto.point.bottomright.up")
                guruMetricCard(title: "Active energy", value: health.todayActiveEnergyKcal.map { "\($0) kcal" } ?? "—",
                    detail: "Measured active energy", symbol: "flame.fill")
                guruMetricCard(title: "Exercise", value: health.todayExerciseMinutes.map { "\($0) min" } ?? "—",
                    detail: "Apple Exercise minutes", symbol: "heart.fill")
            }
            Text("Only connected, measured values are shown. A dash means data is unavailable; Guru never fills gaps with invented numbers.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("gativx-guru-today-signals")
    }

    private var guruGoalSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("YOUR NORTH STAR", systemImage: "scope")
                .font(.headline).foregroundStyle(neon)
            Text("Tell Guru what you are moving towards and why it matters. Your own words become the anchor when motivation dips.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("YOUR GOAL").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            TextField("What do you want to achieve?", text: $guruGoal)
                .focused($focusedGuruField, equals: .goal).submitLabel(.done)
                .onSubmit { dismissGuruKeyboard() }
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("gativx-guru-goal")
            Text("YOUR PURPOSE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            TextField("Why does this matter to you?", text: $guruPurpose, axis: .vertical)
                .focused($focusedGuruField, equals: .purpose).lineLimit(2...4).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("gativx-guru-purpose")
            Text("THE EMOTION YOU WANT TO FEEL").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            TextField("How will achieving it make you feel?", text: $guruEmotion, axis: .vertical)
                .focused($focusedGuruField, equals: .emotion).lineLimit(2...3).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("gativx-guru-emotion")
            Text("ONE SMALL NEXT ACTION").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            TextField("What is one action you can do today?", text: $guruNextAction, axis: .vertical)
                .focused($focusedGuruField, equals: .nextAction).lineLimit(2...3).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("gativx-guru-next-action")
            Text("Saved on this iPhone. Cloud sync is not implied.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
    }

    private var guruWalkingCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("1 · WALKING & MOVEMENT", systemImage: "figure.walk")
                .font(.headline).foregroundStyle(neon)
            Text(guruWalkingGuidance).font(.subheadline)
            ProgressView(value: stepProgress).tint(neon)
            Text(displayedDailySteps.map { "\($0.formatted()) of \(dailyStepGoal.formatted()) measured steps" } ?? "Step progress appears when a verified source is connected.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                guruWalkingDoneDate = guruTodayKey
            } label: {
                Label(guruWalkingDoneToday ? "Today's movement action checked" : "Mark today's movement action done",
                      systemImage: guruWalkingDoneToday ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("gativx-guru-walking-checkin")
            .disabled(guruWalkingDoneToday)
            Button {
                dismissGuruKeyboard()
                isGuruPresented = false
                selectedTab = 1
            } label: {
                Label("Open walking tracker", systemImage: "location.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).tint(neon).foregroundStyle(.black)
            .accessibilityIdentifier("gativx-guru-start-walk")
        }
        .padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("gativx-guru-walking")
    }

    private var guruNutritionCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("2 · FOOD & HYDRATION HABITS", systemImage: "leaf")
                .font(.headline).foregroundStyle(neon)
            Text(guruNutritionGuidance).font(.subheadline)
            Text("A QUICK MEAL NOTE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            TextField("What did you eat, or what is your next meal plan?", text: $guruMealNote, axis: .vertical)
                .focused($focusedGuruField, equals: .mealNote)
                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("gativx-guru-meal-note")
            Text("This is your own note, not an analysed food diary or calorie estimate.")
                .font(.caption2).foregroundStyle(.secondary)
            Button {
                guruNutritionDoneDate = guruTodayKey
            } label: {
                Label(guruNutritionDoneToday ? "Today's food habit checked" : "Mark today's food habit checked",
                      systemImage: guruNutritionDoneToday ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("gativx-guru-nutrition-checkin")
            .disabled(guruNutritionDoneToday)
        }
        .padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("gativx-guru-nutrition")
    }

    private var guruRecoveryCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("3 · RECOVERY & READINESS", systemImage: "moon.stars")
                .font(.headline).foregroundStyle(neon)
            Text("How are you feeling today? Guru uses your check-in, not a guessed sleep or recovery score.")
                .font(.subheadline).foregroundStyle(.secondary)
            Picker("How are you feeling?", selection: $guruRecoveryFeeling) {
                Text("Rested").tag("Rested")
                Text("Okay").tag("Okay")
                Text("Tired").tag("Tired")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("gativx-guru-recovery-feeling")
            Text(guruRecoveryGuidance).font(.subheadline)
            Button {
                guruRecoveryCheckInDate = guruTodayKey
            } label: {
                Label(guruRecoveryCheckedToday ? "Today's recovery check-in saved" : "Save today's recovery check-in",
                      systemImage: guruRecoveryCheckedToday ? "checkmark.circle.fill" : "heart.text.square")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("gativx-guru-recovery-save")
            .disabled(guruRecoveryCheckedToday)
        }
        .padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("gativx-guru-recovery")
    }

    private var guruJourneyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("YOUR GOAL JOURNEY", systemImage: "calendar.badge.clock")
                .font(.headline).foregroundStyle(neon)
            Text("Choose a pace you can sustain. Progress is based on your selected start date, not on assumed daily achievements.")
                .font(.subheadline).foregroundStyle(.secondary)
            Picker("Journey duration", selection: $guruJourneyDurationDays) {
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("180 days").tag(180)
                Text("365 days").tag(365)
            }
            .pickerStyle(.segmented).accessibilityIdentifier("gativx-journey-duration")
            if let journey = activeGuruJourney {
                Text(guruJourneyGoal.isEmpty ? guruGoal : guruJourneyGoal).font(.headline)
                HStack {
                    Text("DAY \(min(journey.elapsedDays + 1, journey.durationDays)) OF \(journey.durationDays)")
                        .font(.caption.weight(.heavy)).tracking(0.5)
                    Spacer()
                    Text(journey.isComplete ? "COMPLETE" : "\(journey.daysRemaining) DAYS LEFT")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                ProgressView(value: journey.progress).tint(neon)
                    .accessibilityIdentifier("gativx-journey-progress")
                Text(journey.checkpointMessage).font(.subheadline).foregroundStyle(.secondary)
                if journey.isComplete {
                    Button("Start another cycle") {
                        guruJourneyGoal = guruGoal.trimmingCharacters(in: .whitespacesAndNewlines)
                        guruActiveJourneyDurationDays = guruJourneyDurationDays
                        guruJourneyStartedAt = Date().timeIntervalSince1970
                    }.buttonStyle(.borderedProminent).tint(neon).foregroundStyle(.black)
                }
            } else {
                Text("Start with your current goal: \(guruGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "add a goal above" : guruGoal)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Start my \(guruJourneyDurationDays)-day journey") {
                    guruJourneyGoal = guruGoal.trimmingCharacters(in: .whitespacesAndNewlines)
                    guruActiveJourneyDurationDays = guruJourneyDurationDays
                    guruJourneyStartedAt = Date().timeIntervalSince1970
                }
                .buttonStyle(.borderedProminent).tint(neon).foregroundStyle(.black)
                .disabled(guruGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("gativx-start-journey")
            }
        }
        .padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
    }

    private var guruPurposeAndActionCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("WHEN YOUR GATI SLOWS", systemImage: "heart.text.square.fill")
                .font(.headline).foregroundStyle(neon)
            Text(guruPurposeAnchor).font(.body.weight(.medium))
            Text("ONE PRACTICAL NEXT ACTION").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
            Text(guruSuggestedNextAction).font(.subheadline.weight(.semibold))
            Button("Save this as my next action") { guruNextAction = guruSuggestedNextAction }
                .buttonStyle(.bordered)
            if !guruNextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Your chosen action: " + guruNextAction).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
    }

    private var guruLearningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("LEARN WITH GURU", systemImage: "play.rectangle.on.rectangle")
                .font(.headline).foregroundStyle(neon)
            Text("Short, trusted guides to help you understand movement and everyday food choices. These links open the source publisher; they are not medical prescriptions.")
                .font(.subheadline).foregroundStyle(.secondary)
            Link(destination: URL(string: "https://www.who.int/health-topics/noncommunicable-diseases/physical-activity")!) {
                HStack {
                    Image(systemName: "figure.walk.circle.fill").font(.title2).foregroundStyle(neon)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WHO · Physical activity guide").font(.subheadline.weight(.semibold))
                        Text("Movement, weekly activity and starting gradually").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                }
                .padding(12).background(pageBackground, in: RoundedRectangle(cornerRadius: 14))
            }
            Link(destination: URL(string: "https://nutritionsource.hsph.harvard.edu/healthy-eating-plate/")!) {
                HStack {
                    Image(systemName: "leaf.circle.fill").font(.title2).foregroundStyle(neon)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Harvard · Healthy Eating Plate").font(.subheadline.weight(.semibold))
                        Text("A visual guide to balanced everyday meals").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                }
                .padding(12).background(pageBackground, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("More video lessons can be added after content review and usage rights are confirmed.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("gativx-guru-learning")
    }

    private var guruScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 15) {
                guruHeroCard
                guruTodaySignalsCard
                guruGoalSetupCard
                guruWalkingCard
                guruNutritionCard
                guruRecoveryCard
                guruJourneyCard
                guruPurposeAndActionCard
                guruLearningCard
                Text("NURUN Guru supports healthy habits and goal planning. It does not diagnose, treat or replace advice from a qualified health professional.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("gativx-guru-fullscreen")
    }

    private var communityScreen: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Community Gati")
                .font(.largeTitle.weight(.bold))
                .accessibilityIdentifier("gativx-community-screen")
            Text("Your journey can encourage someone else's first step.")
                .font(.title3.weight(.semibold))
            Label("NOT ACTIVE IN THIS BUILD", systemImage: "lock.fill")
                .font(.caption.weight(.heavy)).foregroundStyle(.secondary)
            Text("Community feed and shared missions are not available yet. Your personal activity remains private and is not shared with other members.")
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("gativx-community-gated")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(pageBackground.ignoresSafeArea())
    }

    private var profilePhotoPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Choose a member photo")
                    .font(.headline)
                    .accessibilityIdentifier("gativx-profile-photo-picker-sheet")
                PhotosPicker(
                    selection: $selectedProfilePhoto,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Open photo library", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("gativx-profile-photo-picker")
                Text("Your selected photo stays on this iPhone and is not uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") {
                    isProfilePhotoPickerPresented = false
                }
                .accessibilityIdentifier("gativx-profile-photo-picker-cancel")
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Member photo")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var profileScreen: some View {
        Form {
            Section("Member account") {
                if cloud.isSignedIn {
                    Label("Signed in to GATIVX", systemImage: "checkmark.icloud")
                    Text("LOGIN ID")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(cloud.authenticatedUserEmail ?? "Signed-in member")
                        .font(.body.weight(.semibold))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("gativx-member-login-id")
                } else {
                    Label("Local-only access", systemImage: "iphone")
                        .accessibilityIdentifier("gativx-member-login-id")
                    Text("Sign in from the welcome screen or choose account sync when ready. Your local activity history remains on this iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Member profile") {
                HStack(spacing: 12) {
                    Group {
                        if let data = profilePhotoData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable().scaledToFit().padding(7)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 62, height: 62)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(neon.opacity(0.7), lineWidth: 1.5))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profilePhotoData == nil ? "Add your member photo" : "Member photo saved")
                            .font(.subheadline.weight(.semibold))
                        Text("Stored securely on this iPhone only. Not uploaded.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    isProfilePhotoPickerPresented = true
                } label: {
                    Label(profilePhotoData == nil ? "Choose member photo" : "Change member photo", systemImage: "photo")
                }
                .accessibilityIdentifier("gativx-profile-photo-picker-open")
                if profilePhotoData != nil {
                    Button("Remove member photo", role: .destructive) {
                        removeMemberProfilePhoto()
                    }
                }
                Text(profilePhotoStatus).font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    Text("Automatic").tag("system")
                    Text("Day").tag("day")
                    Text("Night").tag("night")
                }.pickerStyle(.segmented)
                Text("Automatic follows your iPhone appearance setting.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Motion & Fitness") {
                Toggle("Daily iPhone step tracking", isOn: $motionMonitoringEnabled)
                    .onChange(of: motionMonitoringEnabled) { _, enabled in
                        if enabled { startLiveMotionMonitor() }
                        else { updateMotionMonitoringPreference(false) }
                    }
                Text(motionStatus).font(.caption).foregroundStyle(.secondary)
                Text("GATIVX requests Motion & Fitness access only when you enable daily step tracking or start a walk.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Location") {
                Text("GATIVX requests location when you start a walk. While Using is enough for an open-app route; Always is optional for supported background GPS while your screen is locked.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(routeRecorder.status).font(.caption2).foregroundStyle(.secondary)
            }
            Section("Contacts") {
                Text("Contacts access is not required for step counting, GPS, Apple Health or account sync. GATIVX does not request it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Imported RunJeet daily totals") {
                Text(runJeetArchiveStatus).font(.caption).foregroundStyle(.secondary)
                ForEach(runJeetDailyStepsArchive.keys.sorted(by: >).prefix(10), id: \.self) { day in
                    HStack {
                        Text(day)
                        Spacer()
                        Text("\(runJeetDailyStepsArchive[day, default: 0].formatted()) steps")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
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
                    Button(isCreatingAccount ? "Create account & sync" : "Sign in and sync") {
                        Task {
                            let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            if isCreatingAccount {
                                await cloud.signUp(email: cleanEmail, password: password)
                            } else {
                                await cloud.signIn(email: cleanEmail, password: password)
                            }
                            if isCreatingAccount && cloud.status.localizedCaseInsensitiveContains("check your email") {
                                isCreatingAccount = false
                            }
                        }
                    }
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (isCreatingAccount ? password.count < 8 : password.isEmpty))
                    Button(isCreatingAccount ? "Already registered? Sign in" : "New to GATIVX? Create account") {
                        isCreatingAccount.toggle()
                        password = ""
                    }
                    .font(.caption.weight(.semibold))
                } else {
                    Label("Cloud account connected", systemImage: "checkmark.icloud")
                    Button("Sign out", role: .destructive) { cloud.signOut() }
                }
                Text("An account is optional. Your dashboard, step tracking and local activity history are available without signing in.")
                    .font(.caption).foregroundStyle(.secondary)
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
        .onAppear { loadRunJeetDailyStepsArchive() }
        .accessibilityIdentifier("gativx-profile-screen")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) progress")
        .accessibilityValue(value.map { "\($0) of \(goal) \(unit)" } ?? "Waiting for measured data")
        .accessibilityIdentifier(title == "Active Calories" ? "gativx-ring-active-calories" : "gativx-ring-heart-points")
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gativx-wellness-rings")
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
                        Text(isCreatingAccount ? "CREATE YOUR GATIVX ACCOUNT" : "WELCOME BACK TO GATIVX")
                            .font(.caption.weight(.heavy)).tracking(1)
                        TextField("Email address", text: $email).textContentType(.emailAddress)
                            .accessibilityIdentifier("gativx-email-field")
                            .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                            .padding(14).background(cardBackground, in: RoundedRectangle(cornerRadius: 13))
                        SecureField(isCreatingAccount ? "Create password (8+ characters)" : "Password", text: $password)
                            .textContentType(isCreatingAccount ? .newPassword : .password)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("gativx-password-field")
                            .padding(14).background(cardBackground, in: RoundedRectangle(cornerRadius: 13))
                        Button {
                            Task {
                                let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                                if isCreatingAccount {
                                    await cloud.signUp(email: cleanEmail, password: password)
                                } else {
                                    await cloud.signIn(email: cleanEmail, password: password)
                                }
                                if cloud.isSignedIn {
                                    localModeEntered = true
                                } else if isCreatingAccount && cloud.status.localizedCaseInsensitiveContains("check your email") {
                                    isCreatingAccount = false
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(isCreatingAccount ? "Create account & continue" : "Sign in & sync").fontWeight(.bold)
                                Spacer()
                            }
                            .padding(15).foregroundStyle(.black).background(neon, in: Capsule())
                        }
                        .accessibilityIdentifier("gativx-auth-submit")
                        .disabled(
                            email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            (isCreatingAccount ? password.count < 8 : password.isEmpty)
                        )
                        HStack {
                            Text(isCreatingAccount ? "Already have an account?" : "New to GATIVX?")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Button(isCreatingAccount ? "Sign in" : "Create account") {
                                isCreatingAccount.toggle()
                                password = ""
                            }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("gativx-auth-mode-toggle")
                        }
                        if !isCreatingAccount {
                            Button("Forgot password?") {
                                Task { await cloud.sendPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("gativx-forgot-password")
                            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            Text("Use at least 8 characters. Email verification may be required.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(cloud.status).font(.caption).foregroundStyle(.secondary)
                    }.padding(17).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    Button { localModeEntered = true } label: {
                        HStack { Spacer(); Text("Continue without account").fontWeight(.semibold); Spacer() }
                            .padding(14).background(cardBackground.opacity(0.88), in: Capsule())
                    }.accessibilityIdentifier("gativx-continue-guest")
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


    /// Fixed full-width member navigation. The iOS floating system tab bar
    /// was detached from the bottom edge and could overlay scroll content.
    /// This dock preserves the five destinations while reserving real layout space.
    private var memberBottomNavigation: some View {
        HStack(spacing: 0) {
            tabNavigationItem(title: "Home", symbol: "house.fill", tag: 0)
            tabNavigationItem(title: "Activity", symbol: "figure.walk", tag: 1)
            tabNavigationItem(title: "Missions", symbol: "target", tag: 2)
            tabNavigationItem(title: "Community", symbol: "person.3", tag: 3)
            tabNavigationItem(title: "Profile", symbol: "person.crop.circle", tag: 4)
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(pageBackground)
        .overlay(alignment: .top) { Rectangle().fill(neon.opacity(0.22)).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gativx-bottom-navigation")
    }

    private func tabNavigationItem(title: String, symbol: String, tag: Int) -> some View {
        Button { selectedTab = tag } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selectedTab == tag ? neon : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("gativx-tab-\(title.lowercased())")
        .accessibilityAddTraits(selectedTab == tag ? .isSelected : [])
    }

    var body: some View {
        // Registration/sign-in is the first-run entry point. The dashboard is
        // shown only after account authentication or an explicit local-only choice.
        if cloud.isSignedIn || localModeEntered {
        TabView(selection: $selectedTab) {
            NavigationStack { homeDashboard.navigationTitle("").toolbar(.hidden, for: .navigationBar) }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            activityScreen
                .tabItem { Label("Activity", systemImage: "figure.walk").accessibilityIdentifier("gativx-tab-activity") }.tag(1)
            // Missions is a single scroll screen with no navigation destinations.
            // Keep it flat so tab changes do not carry an unnecessary nested stack.
            missionsScreen
                .tabItem { Label("Missions", systemImage: "target").accessibilityIdentifier("gativx-tab-missions") }.tag(2)
            // This screen is a static, gated placeholder with no navigation
            // destinations. Avoid an unnecessary NavigationStack here: the
            // nested stack was stalling XCTest's main-thread idle/accessibility
            // handshake when switching to Community after other tabs.
            communityScreen
                .tabItem { Label("Community", systemImage: "person.3").accessibilityIdentifier("gativx-tab-community") }.tag(3)
            // Profile is a settings form with no navigation destinations. Keep it flat like
            // Activity and Community to avoid a nested stack during tab activation.
            profileScreen
                .tabItem { Label("Profile", systemImage: "person.crop.circle").accessibilityIdentifier("gativx-tab-profile") }.tag(4)
        }
        .sheet(isPresented: $isNotificationsPresented) {
            NavigationStack {
                VStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(neon)
                    Text("Notifications aren't active yet")
                        .font(.title2.weight(.bold))
                    Text("GATIVX notifications are not active in this build yet. Your walking records and health data are unaffected.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("gativx-notifications-gated")
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(pageBackground.ignoresSafeArea())
                .navigationTitle("Notifications")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isNotificationsPresented = false }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isGuruPresented) {
            NavigationStack {
                guruScreen
                    .navigationTitle("GATIVX Guru · NURUN")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(pageBackground, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Close Guru") {
                                dismissGuruKeyboard()
                                isGuruPresented = false
                            }
                            .accessibilityIdentifier("gativx-guru-close")
                        }
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { dismissGuruKeyboard() }
                                .accessibilityIdentifier("gativx-guru-keyboard-done")
                        }
                    }
            }
            .tint(neon)
            .preferredColorScheme(dashboardColorScheme)
        }
        .sheet(isPresented: $isProfilePhotoPickerPresented) {
            profilePhotoPickerSheet
        }
        .onChange(of: selectedProfilePhoto) { _, item in
            guard let item else { return }
            isProfilePhotoPickerPresented = false
            Task { await saveMemberProfilePhoto(item) }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            memberBottomNavigation
                .background(pageBackground.ignoresSafeArea(edges: .bottom))
        }
        .tint(neon)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackground.ignoresSafeArea())
        .preferredColorScheme(dashboardColorScheme)
        .onAppear {
            // Migrate existing journeys once, preserving the duration they were already using.
            if guruJourneyStartedAt > 0 && guruActiveJourneyDurationDays <= 0 {
                guruActiveJourneyDurationDays = guruJourneyDurationDays
            }
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
            if motionMonitoringEnabled { startLiveMotionMonitor() }
            loadMemberProfilePhoto()
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
            localModeEntered = signedIn
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
                if motionMonitoringEnabled { startLiveMotionMonitor() }
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
        } else {
            welcomeScreen
        }
    }
}