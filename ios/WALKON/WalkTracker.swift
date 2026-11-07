import Foundation
import Combine
import CoreLocation
import CoreMotion

private struct WalkLocationSample: Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double
}

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
    private var lastCheckpointAt = Date.distantPast
    private var lastCheckpointSteps = -1
    private var lastCheckpointRouteCount = -1
    var onCheckpoint: ((Date, Int, Double, [WalkSession.RoutePoint]) -> Void)?

    private func checkpoint(force: Bool = false) {
        guard let startDate else { return }
        let now = Date()
        let stepsAdvanced = lastCheckpointSteps < 0 || abs(liveSteps - lastCheckpointSteps) >= 20
        let routeAdvanced = lastCheckpointRouteCount < 0 || route.count - lastCheckpointRouteCount >= 5
        guard force || now.timeIntervalSince(lastCheckpointAt) >= 10 || stepsAdvanced || routeAdvanced else { return }
        onCheckpoint?(startDate, liveSteps, distanceMeters, route)
        lastCheckpointAt = now
        lastCheckpointSteps = liveSteps
        lastCheckpointRouteCount = route.count
    }

    func checkpointNow() { checkpoint(force: true) }

    func restore(_ snapshot: ActiveWalkSnapshot) {
        guard !isTracking else { return }
        isTracking = true
        startDate = snapshot.startedAt
        liveSteps = snapshot.steps
        distanceMeters = snapshot.distanceMeters
        route = snapshot.route
        gpsAccuracy = snapshot.route.last?.horizontalAccuracy
        lastCheckpointAt = .distantPast
        lastCheckpointSteps = -1
        lastCheckpointRouteCount = -1
        checkpoint(force: true)
        locationStatus = "Recovered interrupted walk — recording resumed"
        switch location.authorizationStatus {
        case .authorizedAlways:
            configureBackgroundLocation()
            location.startUpdatingLocation()
        case .authorizedWhenInUse:
            locationStatus = "Recovered walk; Always location is needed for locked-screen GPS"
            location.startUpdatingLocation()
            requestAlwaysIfNeeded()
        case .notDetermined:
            locationStatus = "Recovered walk; location permission is needed to resume GPS"
            location.requestWhenInUseAuthorization()
        case .denied, .restricted:
            locationStatus = "Recovered walk; location access is off — enable it in Settings"
        @unknown default:
            locationStatus = "Recovered walk; location permission status is unknown"
        }
        guard CMPedometer.isStepCountingAvailable() else { checkpoint(); return }
        pedometer.queryPedometerData(from: snapshot.startedAt, to: Date()) { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isTracking else { return }
                self.liveSteps = max(data?.numberOfSteps.intValue ?? snapshot.steps, snapshot.steps)
                self.checkpoint()
                self.pedometer.startUpdates(from: snapshot.startedAt) { [weak self] data, error in
                    Task { @MainActor in
                        guard let self, self.isTracking else { return }
                        if let count = data?.numberOfSteps.intValue { self.liveSteps = max(count, 0) }
                        if let error { self.locationStatus = "Step sensor issue: \(error.localizedDescription)" }
                        self.checkpoint()
                    }
                }
            }
        }
    }

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
        lastCheckpointAt = .distantPast
        lastCheckpointSteps = -1
        lastCheckpointRouteCount = -1
        checkpoint(force: true)

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
                        self.checkpoint()
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
        checkpoint(force: true)
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.handleAuthorizationChange(self.location.authorizationStatus)
        }
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            configureBackgroundLocation()
            if isTracking { location.startUpdatingLocation() }
        case .authorizedWhenInUse:
            location.allowsBackgroundLocationUpdates = false
            locationStatus = "Foreground GPS active; Always access is needed when screen is locked"
            requestAlwaysIfNeeded()
            if isTracking { location.startUpdatingLocation() }
        case .denied, .restricted:
            location.allowsBackgroundLocationUpdates = false
            locationStatus = "Location access denied — route cannot be recorded"
        case .notDetermined:
            locationStatus = "Waiting for location permission"
        @unknown default:
            locationStatus = "Unknown location permission state"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map {
            WalkLocationSample(latitude: $0.coordinate.latitude,
                               longitude: $0.coordinate.longitude,
                               timestamp: $0.timestamp,
                               horizontalAccuracy: $0.horizontalAccuracy)
        }
        Task { @MainActor [weak self] in
            self?.processLocationSamples(samples)
        }
    }

    private func processLocationSamples(_ samples: [WalkLocationSample]) {
        guard isTracking else { return }
        for sample in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= 35 else { continue }
            let nextPoint = WalkSession.RoutePoint(
                latitude: sample.latitude,
                longitude: sample.longitude,
                timestamp: sample.timestamp,
                horizontalAccuracy: sample.horizontalAccuracy
            )
            if let previous = route.last {
                guard sample.timestamp > previous.timestamp else { continue }
                // Do not bridge long GPS gaps or accept implausible walking jumps.
                if let increment = WalkSession.acceptedDistance(from: previous, to: nextPoint) {
                    distanceMeters += increment
                }
            }
            route.append(nextPoint)
            gpsAccuracy = sample.horizontalAccuracy
        }
        checkpoint()
        if gpsAccuracy == nil { locationStatus = "Waiting for a reliable GPS fix" }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.locationStatus = "GPS issue: \(message)"
        }
    }
}
