import Foundation
import CoreLocation
import Combine

struct GATIVXRoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double

    var cloudValue: [String: Any] {
        ["latitude": latitude, "longitude": longitude,
         "timestamp": Int64(timestamp.timeIntervalSince1970 * 1000),
         "accuracy": horizontalAccuracy]
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
    private(set) var isRecording = false
    private var pendingStartAfterAuthorization = false
    private var activeStartedAt: Date?
    private var activeActivity = "Walking"

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
        activeStartedAt = Date()
        activeActivity = activity
        recoveredStartedAt = nil
        recoveredActivity = nil
        persistDraft()
        requestAndBegin()
    }

    func resumeRecovered() {
        guard activeStartedAt != nil else { return }
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
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            if pendingStartAfterAuthorization {
                beginUpdates(allowsBackground: manager.authorizationStatus == .authorizedAlways)
            } else {
                status = "Location permission granted. Tap Start activity to record GPS."
            }
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            pendingStartAfterAuthorization = false
            status = "Location permission denied. Enable it in iPhone Settings."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var changed = false
        for location in locations {
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= 50,
                  abs(location.timestamp.timeIntervalSinceNow) < 30 else { continue }
            if let last = points.last, location.timestamp <= last.timestamp { continue }
            points.append(GATIVXRoutePoint(latitude: location.coordinate.latitude,
                                           longitude: location.coordinate.longitude,
                                           timestamp: location.timestamp,
                                           horizontalAccuracy: location.horizontalAccuracy))
            changed = true
        }
        if changed {
            // Persist each accepted batch, not just when the user presses Finish.
            // This allows recovery after app termination or a device restart.
            persistDraft()
            status = "Recording GPS route · \(points.count) points"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS issue: \(error.localizedDescription)"
    }
}
