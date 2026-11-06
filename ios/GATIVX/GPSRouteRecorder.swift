import Foundation
import CoreLocation
import Combine

struct GATIVXRoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double

    var cloudValue: [String: Any] {
        [
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": Int64(timestamp.timeIntervalSince1970 * 1000),
            "accuracy": horizontalAccuracy
        ]
    }
}

@MainActor
final class GPSRouteRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var points: [GATIVXRoutePoint] = []
    @Published private(set) var status = "GPS ready."
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private(set) var isRecording = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Location Services are turned off. Enable them in iPhone Settings."
            return
        }
        points.removeAll()
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            status = "Allow location access, then tap Start activity again."
        case .denied, .restricted:
            status = "Location access is blocked. Enable it in Settings > Privacy & Security > Location Services."
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        @unknown default:
            status = "Location permission could not be determined."
        }
    }

    private func beginUpdates() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        isRecording = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        status = "GPS route recording."
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        isRecording = false
        status = points.isEmpty ? "No GPS points recorded. Check location permission and signal." : "GPS route saved locally."
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            status = "Location permission granted. Tap Start activity to record GPS."
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            status = "Location permission denied."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= 50,
                  abs(location.timestamp.timeIntervalSinceNow) < 30 else { continue }
            if let last = points.last, location.timestamp <= last.timestamp { continue }
            let point = GATIVXRoutePoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: location.timestamp,
                horizontalAccuracy: location.horizontalAccuracy
            )
            points.append(point)
        }
        if !points.isEmpty { status = "Recording GPS route · \(points.count) points" }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS issue: \(error.localizedDescription)"
    }
}
