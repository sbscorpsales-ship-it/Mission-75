import Foundation
import HealthKit
import Combine

/// Native, read-only Apple Health daily aggregate.
/// HealthKit is the authority for the all-source daily total; CoreMotion is never added to it.
@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var todaySteps: Int?
    @Published private(set) var todayActiveEnergyKcal: Int?
    @Published private(set) var todayWalkingRunningDistanceKm: Double?
    @Published private(set) var todayExerciseMinutes: Int?
    @Published private(set) var todayAverageHeartRateBPM: Int?
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasRequestedAccess = UserDefaults.standard.bool(forKey: "gativx.healthkit.connectionRequested")
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var statusMessage = "Apple Health is not connected."
    var onDailyTotal: ((Date, Int) -> Void)?
    var onActiveEnergy: ((Date, Int) -> Void)?

    private let store = HKHealthStore()
    private let connectionRequestedKey = "gativx.healthkit.connectionRequested"
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
    private let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
    private let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
    private var observers: [HKObserverQuery] = []
    private var refreshAgain = false
    private var pendingCompletions: [() -> Void] = []

    func resumeIfPreviouslyConnected() {
        guard UserDefaults.standard.bool(forKey: connectionRequestedKey) else { return }
        guard isAvailable else { statusMessage = "Apple Health is unavailable on this iPhone."; return }
        startObserving()
        refreshRecentDays()
        refreshTodayEnergy()
        refreshTodayMetrics()
    }

    func requestReadAccessAndStart() {
        guard isAvailable else { statusMessage = "Apple Health is unavailable on this iPhone."; return }
        store.requestAuthorization(toShare: [], read: [stepType, energyType, distanceType, exerciseType, heartRateType]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.statusMessage = "Health permission request failed: \(error.localizedDescription)"
                    return
                }
                // HealthKit intentionally does not reveal whether read access was denied.
                UserDefaults.standard.set(true, forKey: self.connectionRequestedKey)
                self.hasRequestedAccess = true
                self.statusMessage = "Apple Health access was requested. Checking today's measured steps…"
                self.startObserving()
                self.refreshRecentDays()
                self.refreshTodayEnergy()
                self.refreshTodayMetrics()
            }
        }
    }

    /// Import measured daily aggregates for the requested local-calendar window.
    /// Empty days are skipped rather than uploaded as fabricated zero values.
    func refreshRecentDays(days: Int = 30, onComplete: (() -> Void)? = nil) {
        guard UserDefaults.standard.bool(forKey: connectionRequestedKey), isAvailable else {
            onComplete?()
            return
        }
        if let onComplete { pendingCompletions.append(onComplete) }
        guard !isRefreshing else { refreshAgain = true; return }

        isRefreshing = true
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let safeDays = max(1, min(days, 365))
        guard let start = calendar.date(byAdding: .day, value: -(safeDays - 1), to: today) else {
            isRefreshing = false
            let completions = pendingCompletions
            pendingCompletions.removeAll()
            completions.forEach { $0() }
            statusMessage = "Could not calculate the Apple Health import date range."
            return
        }
        let end = Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsCollectionQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: today,
            intervalComponents: DateComponents(day: 1)
        )
        query.initialResultsHandler = { [weak self] _, collection, error in
            Task { @MainActor in
                guard let self else { onComplete?(); return }
                defer {
                    self.isRefreshing = false
                    let completions = self.pendingCompletions
                    self.pendingCompletions.removeAll()
                    completions.forEach { $0() }
                    if self.refreshAgain {
                        self.refreshAgain = false
                        self.refreshRecentDays(days: safeDays)
                    }
                }
                if let error {
                    self.statusMessage = "Apple Health read failed: \(error.localizedDescription)"
                    return
                }
                guard let collection else {
                    self.todaySteps = nil
                    self.lastRefresh = Date()
                    self.statusMessage = "Apple Health returned no daily statistics. No zero has been assumed."
                    return
                }

                self.todaySteps = nil
                var importedDays = 0
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else { return }
                    let total = max(0, Int(quantity.doubleValue(for: .count()).rounded()))
                    importedDays += 1
                    if calendar.isDate(statistics.startDate, inSameDayAs: today) {
                        self.todaySteps = total
                    }
                    self.onDailyTotal?(statistics.startDate, total)
                }
                if self.todaySteps == nil {
                    self.lastRefresh = Date()
                    self.statusMessage = importedDays == 0
                        ? "No step samples returned for the requested period. No zero has been assumed."
                        : "Historical Apple Health totals imported; no measured steps are available today."
                } else {
                    self.lastRefresh = Date()
                    self.statusMessage = "Imported measured Apple Health steps for \(importedDays) day(s), including today's total."
                }
            }
        }
        store.execute(query)
    }

    func refreshTodayEnergy(onComplete: (() -> Void)? = nil) {
        guard UserDefaults.standard.bool(forKey: connectionRequestedKey), isAvailable else {
            onComplete?()
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, statistics, error in
            Task { @MainActor in
                guard let self else { onComplete?(); return }
                if let error {
                    self.statusMessage = "Apple Health active-energy read failed: \(error.localizedDescription)"
                    onComplete?()
                    return
                }
                let total = statistics?.sumQuantity().map {
                    max(0, Int($0.doubleValue(for: .kilocalorie()).rounded()))
                }
                self.todayActiveEnergyKcal = total
                if let total { self.onActiveEnergy?(start, total) }
                onComplete?()
            }
        }
        store.execute(query)
    }


    /// Read measured daily distance, exercise minutes and average heart rate.
    /// Missing HealthKit samples remain nil; the dashboard must not invent values.
    func refreshTodayMetrics(onComplete: (() -> Void)? = nil) {
        guard UserDefaults.standard.bool(forKey: connectionRequestedKey), isAvailable else {
            onComplete?()
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let group = DispatchGroup()

        group.enter()
        let distanceQuery = HKStatisticsQuery(quantityType: distanceType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, statistics, error in
            Task { @MainActor in
                if error == nil {
                    self?.todayWalkingRunningDistanceKm = statistics?.sumQuantity().map { $0.doubleValue(for: .meter()) / 1000 }
                }
                group.leave()
            }
        }
        store.execute(distanceQuery)

        group.enter()
        let exerciseQuery = HKStatisticsQuery(quantityType: exerciseType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, statistics, error in
            Task { @MainActor in
                if error == nil {
                    self?.todayExerciseMinutes = statistics?.sumQuantity().map { Int($0.doubleValue(for: .minute()).rounded()) }
                }
                group.leave()
            }
        }
        store.execute(exerciseQuery)

        group.enter()
        let heartRateQuery = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteAverage) { [weak self] _, statistics, error in
            Task { @MainActor in
                if error == nil {
                    self?.todayAverageHeartRateBPM = statistics?.averageQuantity().map {
                        Int($0.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
                    }
                }
                group.leave()
            }
        }
        store.execute(heartRateQuery)

        group.notify(queue: .main) { onComplete?() }
    }

    func startObserving() {
        guard observers.isEmpty, isAvailable else { return }
        // Observe both quantities so a change in active energy refreshes calories
        // even when no new step sample is written at the same time.
        for type in [stepType, energyType, distanceType, exerciseType, heartRateType] {
            let observedType = type
            let query = HKObserverQuery(sampleType: observedType, predicate: nil) { [weak self] _, completion, error in
                guard let self else { completion(); return }
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    switch observedType.identifier {
                    case HKQuantityTypeIdentifier.stepCount.rawValue:
                        self.refreshRecentDays(onComplete: completion)
                    case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                        self.refreshTodayEnergy(onComplete: completion)
                    default:
                        self.refreshTodayMetrics(onComplete: completion)
                    }
                }
            }
            observers.append(query)
            store.execute(query)
            store.enableBackgroundDelivery(for: observedType, frequency: .immediate) { [weak self] success, error in
                Task { @MainActor in
                    if let error { self?.statusMessage = "Apple Health background refresh unavailable: \(error.localizedDescription)" }
                    else if success { self?.statusMessage = "Apple Health background updates enabled where supported. iOS may batch step updates to at most hourly; opening GATIVX refreshes the totals." }
                }
            }
        }
    }

    func refreshOnForeground() {
        refreshRecentDays()
        refreshTodayEnergy()
        refreshTodayMetrics()
    }

    /// Export one completed activity to Apple Health. The GATIVX local record is saved first,
    /// so HealthKit permission or signing failures never discard the member's activity.
    func saveActivityWorkout(
        id: UUID,
        activity: String,
        startedAt: Date,
        finishedAt: Date,
        steps: Int?,
        distanceMeters: Double?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard isAvailable else {
            completion(.failure(NSError(domain: "GATIVXHealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Apple Health is unavailable on this iPhone."])))
            return
        }
        let workoutType = HKObjectType.workoutType()
        let shareTypes: Set<HKSampleType> = [workoutType]
        store.requestAuthorization(toShare: shareTypes, read: [self.stepType, self.energyType]) { [weak self] _, error in
            guard let self else { return }
            if let error { DispatchQueue.main.async { completion(.failure(error)) }; return }
            let syncID = "gativx.activity.\(id.uuidString)"
            let syncPredicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncID])
            let existing = HKSampleQuery(sampleType: workoutType, predicate: syncPredicate, limit: 1, sortDescriptors: nil) { [weak self] _, samples, queryError in
                guard let self else { return }
                if let queryError { DispatchQueue.main.async { completion(.failure(queryError)) }; return }
                if samples?.isEmpty == false { DispatchQueue.main.async { completion(.success(())) }; return }

                let type: HKWorkoutActivityType
                switch activity.lowercased() {
                case "running": type = .running
                case "hiking": type = .hiking
                case "walking": type = .walking
                default: type = .other
                }
                let safeEnd = max(finishedAt, startedAt.addingTimeInterval(1))
                var metadata: [String: Any] = [
                    HKMetadataKeySyncIdentifier: syncID,
                    HKMetadataKeySyncVersion: 1,
                    "com.paramitsolutions.gativx.measuredSteps": max(0, steps ?? 0)
                ]
                if let distanceMeters, distanceMeters > 0 {
                    metadata["com.paramitsolutions.gativx.measuredDistanceMeters"] = distanceMeters
                }
                let totalDistance = (distanceMeters ?? 0) > 0
                    ? HKQuantity(unit: .meter(), doubleValue: distanceMeters!) : nil
                let workout = HKWorkout(activityType: type, start: startedAt, end: safeEnd, workoutEvents: nil, totalEnergyBurned: nil, totalDistance: totalDistance, metadata: metadata)
                self.store.save(workout) { success, saveError in
                    DispatchQueue.main.async {
                        if let saveError { completion(.failure(saveError)) }
                        else if success { completion(.success(())) }
                        else { completion(.failure(NSError(domain: "GATIVXHealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Apple Health did not confirm saving this workout."]))) }
                    }
                }
            }
            self.store.execute(existing)
        }
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: connectionRequestedKey)
        hasRequestedAccess = false
        observers.forEach { store.stop($0) }
        observers.removeAll()
        store.disableBackgroundDelivery(for: stepType) { _, _ in }
        store.disableBackgroundDelivery(for: energyType) { _, _ in }
        todaySteps = nil
        todayActiveEnergyKcal = nil
        todayWalkingRunningDistanceKm = nil
        todayExerciseMinutes = nil
        todayAverageHeartRateBPM = nil
        lastRefresh = nil
        statusMessage = "Apple Health disconnected in GATIVX."
    }
}
