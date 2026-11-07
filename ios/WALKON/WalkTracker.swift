import Foundation
import Combine
import CoreLocation
import CoreMotion

@MainActor
final class WalkTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isTracking = false
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var route: [WalkSession.RoutePoint] = []
    @Published private(set) var liveSteps = 0
    @Published private(set) var locationStatus = "Location permission needed"
    @Published private(set) var gpsAccuracy: Double?

    private let location = CLLocationManager()
    private let pedometer = CMPedometer()
    private var startDate: Date?
    private var requestedAlways = false

    override init() {
        super.init()
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 5
        location.pausesLocationUpdatesAutomatically = false
        location.showsBackgroundLocationIndicator = true
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true
        let started = Date()
        startDate = started
        distanceMeters = 0
        route = []
        liveSteps = 0
        gpsAccuracy = nil

        switch location.authorizationStatus {
        case .authorizedAlways:
            configureBackgroundLocation()
            location.startUpdatingLocation()
        case .authorizedWhenInUse:
            locationStatus = "Allow Always location for locked-screen route recording"
            location.startUpdatingLocation()
            requestAlwaysIfNeeded()
        case .notDetermined:
            locationStatus = "Waiting for location permission"
            location.requestWhenInUseAuthorization()
        case .denied, .restricted:
            locationStatus = "Location access is off — enable it in iPhone Settings"
        @unknown default:
            locationStatus = "Location permission status is unknown"
        }

        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: started) { [weak self] data, error in
                Task { @MainActor in
                    guard let self, self.isTracking else { return }
                    if let error {
                        self.locationStatus = "Step sensor unavailable: \(error.localizedDescription)"
                        return
                    }
                    if let count = data?.numberOfSteps.intValue {
                        self.liveSteps = max(count, 0)
                    }
                }
            }
        } else {
            locationStatus = "This iPhone does not support live step counting"
        }
    }

    func finish(completion: @escaping (WalkSession?) -> Void) {
        guard isTracking, let started = startDate else {
            completion(nil)
            return
        }
        isTracking = false
        let ended = Date()
        location.stopUpdatingLocation()
        pedometer.stopUpdates()
        let fallbackSteps = liveSteps
        let routeSnapshot = route
        let distanceSnapshot = distanceMeters
        startDate = nil

        guard CMPedometer.isStepCountingAvailable() else {
            completion(makeSession(started: started, ended: ended, steps: fallbackSteps,
                                   distance: distanceSnapshot, route: routeSnapshot))
            return
        }
        pedometer.queryPedometerData(from: started, to: ended) { [weak self] data, _ in
            let finalSteps = max(data?.numberOfSteps.intValue ?? fallbackSteps, 0)
            Task { @MainActor in
                guard let self else { return }
                self.liveSteps = finalSteps
                completion(self.makeSession(started: started, ended: ended, steps: finalSteps,
                                             distance: distanceSnapshot, route: routeSnapshot))
            }
        }
    }

    private func makeSession(started: Date, ended: Date, steps: Int, distance: Double,
                             route: [WalkSession.RoutePoint]) -> WalkSession {
        WalkSession(id: UUID(), startedAt: started, endedAt: ended, steps: steps,
                    distanceMeters: distance, route: route)
    }

    private func configureBackgroundLocation() {
        location.allowsBackgroundLocationUpdates = true
        locationStatus = "GPS recording active — background location allowed"
    }

    private func requestAlwaysIfNeeded() {
        guard !requestedAlways else { return }
        requestedAlways = true
        location.requestAlwaysAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            configureBackgroundLocation()
            if isTracking { manager.startUpdatingLocation() }
        case .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = false
            locationStatus = "Foreground GPS active; Always access is needed when screen is locked"
            requestAlwaysIfNeeded()
            if isTracking { manager.startUpdatingLocation() }
        case .denied, .restricted:
            manager.allowsBackgroundLocationUpdates = false
            locationStatus = "Location access denied — route cannot be recorded"
        case .notDetermined:
            locationStatus = "Waiting for location permission"
        @unknown default:
            locationStatus = "Unknown location permission state"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking else { return }
        for point in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard point.horizontalAccuracy >= 0, point.horizontalAccuracy <= 35 else { continue }
            if let previous = route.last {
                guard point.timestamp > previous.timestamp else { continue }
                let old = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                let delta = point.distance(from: old)
                let elapsed = point.timestamp.timeIntervalSince(previous.timestamp)
                // Do not bridge long GPS gaps or accept implausible walking jumps.
                if elapsed > 0, elapsed <= 30, delta >= 0, delta / elapsed <= 8 {
                    distanceMeters += delta
                }
            }
            route.append(WalkSession.RoutePoint(
                latitude: point.coordinate.latitude,
                longitude: point.coordinate.longitude,
                timestamp: point.timestamp,
                horizontalAccuracy: point.horizontalAccuracy
            ))
            gpsAccuracy = point.horizontalAccuracy
        }
        if gpsAccuracy == nil { locationStatus = "Waiting for a reliable GPS fix" }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationStatus = "GPS issue: \(error.localizedDescription)"
    }
}
