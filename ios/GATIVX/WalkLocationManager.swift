import Foundation
import CoreLocation
import Combine

struct GATIVXRoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: Date
}

@MainActor
final class WalkLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var points: [GATIVXRoutePoint] = []
    @Published private(set) var status = "GPS not started"
    private let manager = CLLocationManager()
    private var isTracking = false
    private var requestedAlwaysAuthorization = false
    private var wantsTracking = false

    override init() {
        super.init()
        manager.delegate = self
        if let data = UserDefaults.standard.data(forKey: "gativx.activeRoute.v1"),
           let saved = try? JSONDecoder().decode([GATIVXRoutePoint].self, from: data) {
            points = saved
        }
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false
    }

    func begin() {
        wantsTracking = true
        points.removeAll()
        UserDefaults.standard.removeObject(forKey: "gativx.activeRoute.v1")
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            status = "Allow location access to record your route"
        case .authorizedAlways, .authorizedWhenInUse:
            start()
        case .denied, .restricted:
            status = "Location access is disabled in iPhone Settings"
        @unknown default:
            status = "Location permission unavailable"
        }
    }

    private func start() {
        guard !isTracking else { return }
        isTracking = true
        manager.startUpdatingLocation()
        status = "Recording GPS route"
    }

    func finish() -> [GATIVXRoutePoint] {
        wantsTracking = false
        manager.stopUpdatingLocation()
        UserDefaults.standard.removeObject(forKey: "gativx.activeRoute.v1")
        isTracking = false
        status = points.isEmpty ? "No GPS points recorded" : "Route captured · \(points.count) points"
        return points
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            if wantsTracking && !isTracking { start() }
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            manager.allowsBackgroundLocationUpdates = false
            if !requestedAlwaysAuthorization {
                requestedAlwaysAuthorization = true
                manager.requestAlwaysAuthorization()
            }
            if !isTracking { start() }
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            status = "Location permission denied"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50 {
            if let last = points.last,
               location.timestamp.timeIntervalSince(last.timestamp) < 1 { continue }
            points.append(GATIVXRoutePoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                timestamp: location.timestamp
            ))
        }
        status = "Recording GPS route · \(points.count) points"
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS error: \(error.localizedDescription)"
    }
}
