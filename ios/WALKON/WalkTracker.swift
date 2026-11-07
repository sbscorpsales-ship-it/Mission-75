import Foundation
import Combine
import CoreLocation
import CoreMotion

@MainActor
final class WalkTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isTracking = false
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var route: [WalkSession.Coordinate] = []
    @Published private(set) var liveSteps = 0
    @Published private(set) var locationStatus = "Location not started"

    private let location = CLLocationManager()
    private let pedometer = CMPedometer()
    private var startDate: Date?

    override init() {
        super.init()
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 5
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true
        startDate = Date()
        distanceMeters = 0
        route = []
        liveSteps = 0
        location.requestWhenInUseAuthorization()
        location.startUpdatingLocation()
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let count = data?.numberOfSteps.intValue else { return }
                Task { @MainActor in self?.liveSteps = count }
            }
        }
    }

    func stop() -> WalkSession? {
        guard isTracking, let startDate else { return nil }
        isTracking = false
        location.stopUpdatingLocation()
        pedometer.stopUpdates()
        let session = WalkSession(id: UUID(), startedAt: startDate, endedAt: Date(),
                                  steps: liveSteps, distanceMeters: distanceMeters, route: route)
        self.startDate = nil
        return session
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: locationStatus = "Location enabled"
        case .denied, .restricted: locationStatus = "Location permission denied"
        default: locationStatus = "Location permission needed"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for point in locations where point.horizontalAccuracy >= 0 && point.horizontalAccuracy < 40 {
            if let previous = route.last {
                let old = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                let delta = point.distance(from: old)
                if delta > 0 && delta < 100 { distanceMeters += delta }
            }
            route.append(.init(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude))
        }
    }
}
