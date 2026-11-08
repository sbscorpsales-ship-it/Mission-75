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
    private var lastAcceptedLocation: CLLocation?
    private var backgroundActivity: CLBackgroundActivitySession?
    private var sensorsStarted = false

    override init() {
        super.init()
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 5
        location.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true
        startDate = Date()
        distanceMeters = 0
        route = []
        liveSteps = 0
        lastAcceptedLocation = nil
        sensorsStarted = false

        switch location.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startLocationCapture()
        case .notDetermined:
            locationStatus = "Requesting location permission"
            location.requestWhenInUseAuthorization()
        case .denied, .restricted:
            locationStatus = "Location permission denied — route unavailable"
        @unknown default:
            locationStatus = "Location authorization unavailable"
        }

        if CMPedometer.isStepCountingAvailable(), let startDate {
            pedometer.startUpdates(from: startDate) { [weak self] data, error in
                guard error == nil, let count = data?.numberOfSteps.intValue else { return }
                Task { @MainActor in
                    guard self?.isTracking == true else { return }
                    self?.liveSteps = max(0, count)
                }
            }
        } else {
            locationStatus = "Motion step counting unavailable"
        }
    }

    func stop() -> WalkSession? {
        guard isTracking, let startDate else { return nil }
        isTracking = false
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        backgroundActivity?.invalidate()
        backgroundActivity = nil
        sensorsStarted = false
        pedometer.stopUpdates()
        let session = WalkSession(
            id: UUID(),
            startedAt: startDate,
            endedAt: Date(),
            steps: liveSteps,
            distanceMeters: distanceMeters,
            route: route
        )
        self.startDate = nil
        lastAcceptedLocation = nil
        return session
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationStatus = "Location enabled for this walk"
            if isTracking { startLocationCapture() }
        case .denied, .restricted:
            locationStatus = "Location permission denied — route unavailable"
            location.stopUpdatingLocation()
            location.allowsBackgroundLocationUpdates = false
            backgroundActivity?.invalidate()
            backgroundActivity = nil
            sensorsStarted = false
        case .notDetermined:
            locationStatus = "Location permission needed"
        @unknown default:
            locationStatus = "Location authorization unavailable"
        }
    }

    private func startLocationCapture() {
        guard isTracking, !sensorsStarted else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            locationStatus = "iPhone Location Services are off"
            return
        }
        // The visible background activity session allows a user-started walk to
        // continue receiving When In Use location updates while the screen is locked.
        backgroundActivity = CLBackgroundActivitySession()
        location.allowsBackgroundLocationUpdates = true
        location.showsBackgroundLocationIndicator = true
        location.startUpdatingLocation()
        sensorsStarted = true
        locationStatus = "Recording GPS route"
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationStatus = "GPS update: \(error.localizedDescription)"
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking else { return }
        for point in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let age = Date().timeIntervalSince(point.timestamp)
            guard point.horizontalAccuracy >= 0,
                  point.horizontalAccuracy <= 35,
                  age >= -5,
                  age <= 30 else { continue }

            if let previous = lastAcceptedLocation {
                let elapsed = point.timestamp.timeIntervalSince(previous.timestamp)
                guard elapsed > 0 else { continue }
                let delta = point.distance(from: previous)
                let impliedSpeed = delta / elapsed

                // Reject impossible jumps. For a long signal gap, start a new
                // continuity point but do not invent distance across the gap.
                if elapsed <= 30 {
                    guard delta <= 100, impliedSpeed <= 7.0 else { continue }
                    if delta >= 1.0 { distanceMeters += delta }
                }
            }

            lastAcceptedLocation = point
            route.append(
                .init(
                    latitude: point.coordinate.latitude,
                    longitude: point.coordinate.longitude
                )
            )
        }
    }
}
