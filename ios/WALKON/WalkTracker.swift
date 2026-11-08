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
    private let store: ActivityStore
    private var workoutID: UUID?
    private var startDate: Date?
    private var lastAcceptedLocation: CLLocation?
    private var backgroundActivity: CLBackgroundActivitySession?
    private var sensorsStarted = false
    private var nextSequence = 0
    private var routeSegment = 0

    init(store: ActivityStore) {
        self.store = store
        super.init()
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 5
        location.pausesLocationUpdatesAutomatically = false
    }

    /// The draft is durably created before any sensor is started.
    @discardableResult
    func start() -> Bool {
        guard !isTracking else { return false }
        let id = UUID()
        let started = Date()
        guard store.beginDraft(id: id, startedAt: started) else {
            locationStatus = "Could not create a durable walk draft. No recording started."
            return false
        }
        workoutID = id
        isTracking = true
        startDate = started
        distanceMeters = 0
        route = []
        liveSteps = 0
        nextSequence = 0
        routeSegment = 0
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
                    guard let self, self.isTracking else { return }
                    self.liveSteps = max(0, count)
                    self.checkpointMetrics()
                }
            }
        } else {
            locationStatus = "Motion step counting unavailable"
        }
        return true
    }

    /// Stops capture first, then atomically converts the journal into a saved walk.
    @discardableResult
    func stop() -> Bool {
        guard isTracking, let workoutID else { return false }
        isTracking = false
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        backgroundActivity?.invalidate()
        backgroundActivity = nil
        sensorsStarted = false
        pedometer.stopUpdates()
        checkpointMetrics()
        let saved = store.finalizeDraft(workoutID, endedAt: Date())
        self.workoutID = nil
        startDate = nil
        lastAcceptedLocation = nil
        locationStatus = saved ? "Walk saved on this iPhone" : "Walk remains in recovery journal — retry from History"
        return saved
    }

    private func checkpointMetrics() {
        guard let workoutID else { return }
        _ = store.updateDraftMetrics(
            workoutID: workoutID,
            steps: liveSteps,
            distanceMeters: distanceMeters
        )
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
        guard isTracking, let workoutID else { return }
        for point in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let age = Date().timeIntervalSince(point.timestamp)
            guard point.horizontalAccuracy >= 0,
                  point.horizontalAccuracy <= 35,
                  age >= -5,
                  age <= 30 else { continue }

            var acceptedDistanceDelta = 0.0
            if let previous = lastAcceptedLocation {
                let elapsed = point.timestamp.timeIntervalSince(previous.timestamp)
                guard elapsed > 0 else { continue }
                let delta = point.distance(from: previous)
                if elapsed > 30 {
                    // Preserve the break as a new segment; never count distance over a GPS gap.
                    routeSegment += 1
                } else {
                    let impliedSpeed = delta / elapsed
                    guard delta <= 100, impliedSpeed <= 7.0 else { continue }
                    if delta >= 1.0 { acceptedDistanceDelta = delta }
                }
            }

            let coordinate = WalkSession.Coordinate(
                latitude: point.coordinate.latitude,
                longitude: point.coordinate.longitude
            )
            let journalPoint = JournalRoutePoint(
                sequence: nextSequence,
                segment: routeSegment,
                timestamp: point.timestamp,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                horizontalAccuracy: point.horizontalAccuracy
            )
            // Only expose a point in the live route after its durable checkpoint succeeds.
            guard store.appendRoutePoint(workoutID: workoutID, point: journalPoint) else {
                locationStatus = "Route checkpoint failed — local storage needs attention"
                continue
            }
            // Distance advances only after the matching route observation is durable.
            distanceMeters += acceptedDistanceDelta
            nextSequence += 1
            route.append(coordinate)
            lastAcceptedLocation = point
            checkpointMetrics()
        }
    }
}
