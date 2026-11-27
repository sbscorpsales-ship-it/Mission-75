import Foundation
@preconcurrency import CoreLocation
import Combine

struct GATIVXRoutePoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double
    /// Starts a new route segment; distance must never bridge this point to the previous fix.
    let breakBefore: Bool

    init(latitude: Double, longitude: Double, timestamp: Date, horizontalAccuracy: Double, breakBefore: Bool = false) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.breakBefore = breakBefore
    }

    private enum CodingKeys: String, CodingKey {
        case latitude, longitude, timestamp, horizontalAccuracy, breakBefore
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        timestamp = try values.decode(Date.self, forKey: .timestamp)
        horizontalAccuracy = try values.decode(Double.self, forKey: .horizontalAccuracy)
        // Drafts saved by earlier app versions have no segment marker.
        breakBefore = try values.decodeIfPresent(Bool.self, forKey: .breakBefore) ?? false
    }

    var cloudValue: [String: Any] {
        ["latitude": latitude, "longitude": longitude,
         "timestamp": Int64(timestamp.timeIntervalSince1970 * 1000),
         "accuracy": horizontalAccuracy, "breakBefore": breakBefore]
    }
}

struct GATIVXActiveRouteDraft: Codable {
    let startedAt: Date
    let activity: String
    let sessionID: UUID?
    let ownerID: String?
    var points: [GATIVXRoutePoint]

    init(
        startedAt: Date,
        activity: String,
        points: [GATIVXRoutePoint],
        sessionID: UUID,
        ownerID: String? = nil
    ) {
        self.startedAt = startedAt
        self.activity = activity
        self.sessionID = sessionID
        self.ownerID = ownerID
        self.points = points
    }
}


/// Atomic GPS draft writer. A route is only reported as safely persisted after
/// the exact bytes are read back and decoded successfully.
enum GPSRouteDraftPersistence {
    static func write(_ draft: GATIVXActiveRouteDraft, to url: URL) throws {
        let data = try JSONEncoder().encode(draft)
        try data.write(to: url, options: .atomic)

        let savedData = try Data(contentsOf: url)
        guard savedData == data else {
            throw NSError(
                domain: "GATIVXGPSDraft",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The GPS draft did not match the data written to disk."]
            )
        }
        let restored = try JSONDecoder().decode(GATIVXActiveRouteDraft.self, from: savedData)
        guard restored.sessionID == draft.sessionID,
              restored.ownerID == draft.ownerID,
              restored.startedAt == draft.startedAt,
              restored.activity == draft.activity,
              restored.points.count == draft.points.count else {
            throw NSError(
                domain: "GATIVXGPSDraft",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The GPS draft could not be read back and verified."]
            )
        }
    }
}

/// Core Location delivers delegate callbacks on the manager's creation run loop.
/// This recorder is created on the main actor and keeps its location manager and UI state there.
@MainActor
final class GPSRouteRecorder: NSObject, ObservableObject {
    @Published private(set) var points: [GATIVXRoutePoint] = []
    @Published private(set) var status = "GPS ready."
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var recoveredStartedAt: Date?
    @Published private(set) var recoveredActivity: String?
    @Published private(set) var hasUnreadableDraft = false
    private(set) var activitySessionID: UUID?
    private(set) var activityOwnerID: String?

    private let manager = CLLocationManager()
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let directoryOverride: URL?
    private let draftKey = "gativx.activeRouteDraft.v1"
    private var draftURL: URL? {
        let directory: URL
        if let directoryOverride {
            directory = directoryOverride
        } else {
            guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
            directory = support.appendingPathComponent("GATIVX", isDirectory: true)
        }
        do { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { return nil }
        return directory.appendingPathComponent("active-route-draft.json", isDirectory: false)
    }
    var routeDistanceMeters: Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0.0) { total, pair in
            guard !pair.1.breakBefore else { return total }
            let a = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let b = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return total + b.distance(from: a)
        }
    }

    private(set) var isRecording = false
    private var pendingStartAfterAuthorization = false
    private var activeStartedAt: Date?
    private var activeActivity = "Walking"
    private var needsSegmentBreak = true

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        directoryOverride: URL? = nil
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.directoryOverride = directoryOverride
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        restoreDraft()
    }

    private func restoreDraft() {
        let url = draftURL
        let fileExists = url.map { fileManager.fileExists(atPath: $0.path) } ?? false
        var fileData: Data?
        var fileReadFailed = false
        if fileExists, let url {
            do {
                fileData = try Data(contentsOf: url)
            } catch {
                // A present but unreadable draft is not the same as no draft.
                // Preserve it and block new sessions rather than replacing it.
                fileReadFailed = true
            }
        }
        let legacyData = userDefaults.data(forKey: draftKey)
        guard !fileReadFailed,
              let data = fileData ?? legacyData,
              let draft = try? JSONDecoder().decode(GATIVXActiveRouteDraft.self, from: data) else {
            if fileReadFailed || fileData != nil || legacyData != nil {
                hasUnreadableDraft = true
                status = "An unfinished GPS draft could not be read. Its original data was preserved for recovery."
            }
            return
        }
        points = draft.points
        recoveredStartedAt = draft.startedAt
        recoveredActivity = draft.activity
        activitySessionID = draft.sessionID ?? UUID()
        activityOwnerID = draft.ownerID
        activeStartedAt = draft.startedAt
        activeActivity = draft.activity
        status = "Recovered unfinished activity · \(points.count) GPS points. Resume or finish to save it."

        // Migrate older UserDefaults drafts to an atomic file without deleting
        // the legacy copy until the file write succeeds.
        if fileData == nil, let legacyData, let url {
            do {
                try legacyData.write(to: url, options: .atomic)
                userDefaults.removeObject(forKey: draftKey)
            } catch {
                status = "Recovered legacy GPS draft. File migration is pending; the original draft remains preserved."
            }
        }
        // Upgrade old drafts with a stable idempotency key exactly once.
        if draft.sessionID == nil {
            _ = persistDraft()
        }
    }

    @discardableResult
    private func persistDraft() -> Bool {
        guard !hasUnreadableDraft,
              let startedAt = activeStartedAt,
              let sessionID = activitySessionID else { return false }
        guard let url = draftURL else {
            status = "Could not access the local GPS draft folder. The route remains in memory; do not force-quit GATIVX."
            return false
        }
        let draft = GATIVXActiveRouteDraft(
            startedAt: startedAt,
            activity: activeActivity,
            points: points,
            sessionID: sessionID,
            ownerID: activityOwnerID
        )
        do {
            try GPSRouteDraftPersistence.write(draft, to: url)
            // Remove the legacy copy only after the new file has been read back and verified.
            userDefaults.removeObject(forKey: draftKey)
            return true
        } catch {
            status = "Could not persist the active route safely: \(error.localizedDescription)"
            return false
        }
    }

    func start(activity: String, ownerID: String? = nil) {
        // A restored or paused route owns its original ID, start time and points.
        // Never replace that recoverable draft with a fresh activity.
        guard !isRecording, activeStartedAt == nil, !hasUnreadableDraft else {
            if hasUnreadableDraft {
                status = "An unfinished GPS draft could not be read and remains preserved. Do not start a new walk until it is recovered."
            } else if activeStartedAt != nil {
                status = "An unfinished activity is already stored. Resume or save it before starting another walk."
            }
            return
        }
        points.removeAll()
        needsSegmentBreak = true
        activeStartedAt = Date()
        activeActivity = activity
        activitySessionID = UUID()
        activityOwnerID = ownerID
        recoveredStartedAt = nil
        recoveredActivity = nil
        let draftPersisted = persistDraft()
        requestAndBegin()
        if !draftPersisted && isRecording {
            status = "GPS is recording, but the route draft is not safely stored on this iPhone. Keep GATIVX open and check available storage."
        }
    }

    #if DEBUG
    /// Deterministic GPS fixture for simulator UI tests only. It does not request
    /// location permission or start Core Location updates; Release builds omit it.
    @discardableResult
    func installUITestRoute(
        activity: String,
        startedAt: Date,
        points: [GATIVXRoutePoint],
        sessionID: UUID,
        ownerID: String? = nil
    ) -> Bool {
        guard !hasUnreadableDraft,
              !isRecording,
              (activeStartedAt == nil || activitySessionID == sessionID) else {
            status = "Cannot install the UI-test route while another or unreadable GPS draft is active."
            return false
        }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        pendingStartAfterAuthorization = false
        self.points = points
        activeStartedAt = startedAt
        activeActivity = activity
        activitySessionID = sessionID
        activityOwnerID = ownerID
        recoveredStartedAt = nil
        recoveredActivity = nil
        needsSegmentBreak = false
        guard persistDraft() else { return false }
        status = "DEBUG UI-test GPS route installed · \(points.count) accepted points."
        return true
    }

    /// Clear only the deterministic test session, and only after its local history
    /// record has been read back and verified by Finish & Save.
    func clearUITestRouteAfterVerifiedSave(sessionID: UUID) {
        guard activitySessionID == sessionID else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        isRecording = false
        pendingStartAfterAuthorization = false
        clearDraft()
        status = "DEBUG UI-test GPS route cleared after verified local save."
    }
    #endif

    func resumeRecovered() {
        guard !hasUnreadableDraft, activeStartedAt != nil else { return }
        // A recovered route may have been interrupted while iOS suspended or terminated the app.
        needsSegmentBreak = true
        requestAndBegin()
    }

    func requestBackgroundLocationAccess() {
        guard manager.authorizationStatus == .authorizedWhenInUse else {
            status = "Start a walk and allow While Using first. Then enable Always access in iPhone Settings."
            return
        }
        manager.requestAlwaysAuthorization()
        status = "Requested Always location access. Choose Allow Always if iOS presents the option."
    }

    private func requestAndBegin() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Location Services are turned off. Enable them in iPhone Settings."
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            pendingStartAfterAuthorization = true
            manager.requestWhenInUseAuthorization()
            status = "Waiting for location permission…"
        case .denied, .restricted:
            status = "Location access is blocked. Enable it in Settings > Privacy & Security > Location Services."
        case .authorizedWhenInUse:
            beginUpdates(allowsBackground: false)
        case .authorizedAlways:
            beginUpdates(allowsBackground: true)
        @unknown default:
            status = "Location permission could not be determined."
        }
    }

    private func beginUpdates(allowsBackground: Bool) {
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Location Services are turned off."
            return
        }
        pendingStartAfterAuthorization = false
        manager.allowsBackgroundLocationUpdates = allowsBackground
        manager.showsBackgroundLocationIndicator = allowsBackground
        isRecording = true
        manager.startUpdatingLocation()
        status = allowsBackground
            ? "GPS route recording, including supported background use."
            : "GPS route recording while GATIVX is open. Allow Always location for background recording."
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        isRecording = false
        pendingStartAfterAuthorization = false
        let draftPersisted = persistDraft()
        if draftPersisted {
            status = points.isEmpty ? "No GPS points recorded. Check location permission and signal." : "Route paused and safely stored on this iPhone."
        }
    }

    func clearDraft() {
        userDefaults.removeObject(forKey: draftKey)
        if let url = draftURL { try? fileManager.removeItem(at: url) }
        points.removeAll()
        activeStartedAt = nil
        activeActivity = "Walking"
        activitySessionID = nil
        activityOwnerID = nil
        recoveredStartedAt = nil
        recoveredActivity = nil
        hasUnreadableDraft = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedAlways:
            if pendingStartAfterAuthorization {
                beginUpdates(allowsBackground: true)
            } else if isRecording {
                // The user may grant Always from Settings while a walk is already
                // active. Enable background delivery immediately for that session.
                manager.allowsBackgroundLocationUpdates = true
                manager.showsBackgroundLocationIndicator = true
                manager.startUpdatingLocation()
                status = "GPS route recording, including supported background use."
            } else {
                status = "Always location access granted. Start an activity to record GPS."
            }
        case .authorizedWhenInUse:
            if pendingStartAfterAuthorization {
                beginUpdates(allowsBackground: false)
            } else if isRecording {
                // If access is downgraded mid-session, never claim background GPS.
                manager.allowsBackgroundLocationUpdates = false
                manager.showsBackgroundLocationIndicator = false
                manager.startUpdatingLocation()
                status = "GPS route recording while GATIVX is open. Allow Always location for background recording."
            } else {
                status = "Location permission granted. Tap Start activity to record GPS."
            }
        case .denied, .restricted:
            pendingStartAfterAuthorization = false
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            status = "Location permission denied. Enable it in iPhone Settings."
        case .notDetermined:
            break
        @unknown default:
            status = "Location permission could not be determined."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var changed = false
        for location in locations {
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= 50,
                  abs(location.timestamp.timeIntervalSinceNow) < 30 else {
                // The next accepted fix starts a new segment after a bad/stale fix.
                needsSegmentBreak = true
                continue
            }

            if let last = points.last {
                let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
                guard elapsed > 0 else { continue }
                if elapsed > 30 {
                    // Do not draw or count distance across a long GPS outage.
                    needsSegmentBreak = true
                } else {
                    let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    let delta = location.distance(from: previous)
                    let speed = delta / elapsed
                    if delta > 150 || speed > 8 {
                        // Reject this jump as distance, but keep it as a fresh anchor
                        // so subsequent valid fixes can resume without a giant gap.
                        needsSegmentBreak = true
                    }
                }
            }

            points.append(GATIVXRoutePoint(latitude: location.coordinate.latitude,
                                           longitude: location.coordinate.longitude,
                                           timestamp: location.timestamp,
                                           horizontalAccuracy: location.horizontalAccuracy,
                                           breakBefore: needsSegmentBreak))
            needsSegmentBreak = false
            changed = true
        }
        if changed {
            // Persist each accepted batch, not just when the user presses Finish.
            // This allows recovery after app termination or a device restart.
            if persistDraft() {
                status = "Recording GPS route · \(points.count) points · " +
                    String(format: "%.2f km", routeDistanceMeters / 1000)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS issue: \(error.localizedDescription)"
    }
}

// Core Location invokes delegates on the run loop where CLLocationManager is created.
// The manager is created by this main-actor recorder, so delegate state stays on MainActor.
extension GPSRouteRecorder: @preconcurrency CLLocationManagerDelegate {}
