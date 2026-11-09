import Foundation
import CoreLocation
import Combine

struct GATIVXRoutePoint: Codable {
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

private struct GATIVXActiveRouteDraft: Codable {
    let startedAt: Date
    let activity: String
    var points: [GATIVXRoutePoint]
}

@MainActor
final class GPSRouteRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var points: [GATIVXRoutePoint] = []
    @Published private(set) var status = "GPS ready."
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var recoveredStartedAt: Date?
    @Published private(set) var recoveredActivity: String?

    private let manager = CLLocationManager()
    private let draftKey = "gativx.activeRouteDraft.v1"
    private var draftURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent("GATIVX", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
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

    override init() {
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
        guard let data = UserDefaults.standard.data(forKey: draftKey),
              let draft = try? JSONDecoder().decode(GATIVXActiveRouteDraft.self, from: data) else { return }
        points = draft.points
        recoveredStartedAt = draft.startedAt
        recoveredActivity = draft.activity
        activeStartedAt = draft.startedAt
        activeActivity = draft.activity
        status = "Recovered unfinished activity · \(points.count) GPS points. Resume or finish to save it."
    }

    private func persistDraft() {
        guard let startedAt = activeStartedAt else { return }
        let draft = GATIVXActiveRouteDraft(startedAt: startedAt, activity: activeActivity, points: points)
        guard let data = try? JSONEncoder().encode(draft) else {
            status = "Could not persist the active route safely."
            return
        }
        UserDefaults.standard.set(data, forKey: draftKey)
    }

    func start(activity: String) {
        guard !isRecording else { return }
        points.removeAll()
        needsSegmentBreak = true
        activeStartedAt = Date()
        activeActivity = activity
        recoveredStartedAt = nil
        recoveredActivity = nil
        persistDraft()
        requestAndBegin()
    }

    func resumeRecovered() {
        guard activeStartedAt != nil else { return }
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
        persistDraft()
        status = points.isEmpty ? "No GPS points recorded. Check location permission and signal." : "Route paused and safely stored on this iPhone."
    }

    func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
        if let url = draftURL { try? FileManager.default.removeItem(at: url) }
        points.removeAll()
        activeStartedAt = nil
        activeActivity = "Walking"
        recoveredStartedAt = nil
        recoveredActivity = nil
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
            persistDraft()
            status = "Recording GPS route · \(points.count) points · " +
                String(format: "%.2f km", routeDistanceMeters / 1000)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS issue: \(error.localizedDescription)"
    }
}
