import Foundation
import HealthKit
import Combine

private struct PendingHealthWorkout: Codable, Identifiable {
    let id: UUID
    let activity: String
    let startedAt: Date
    let finishedAt: Date
    let steps: Int?
    let distanceMeters: Double?
}

/// Reads measured Apple Health aggregates and exports completed GATIVX workouts.
/// HealthKit is the authority for the all-source daily total; Core Motion is never added to it.
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

    private let workoutOutboxKey = "gativx.healthkit.workout-export-outbox.v1"
    @Published private(set) var pendingWorkoutExportCount = 0
    @Published private(set) var isWorkoutOutboxReadable = true
    private var isRetryingWorkoutOutbox = false

    private func loadPendingWorkouts() -> [PendingHealthWorkout]? {
        guard let data = UserDefaults.standard.data(forKey: workoutOutboxKey) else {
            isWorkoutOutboxReadable = true
            pendingWorkoutExportCount = 0
            return []
        }
        do {
            let items = try JSONDecoder().decode([PendingHealthWorkout].self, from: data)
            isWorkoutOutboxReadable = true
            pendingWorkoutExportCount = items.count
            return items
        } catch {
            isWorkoutOutboxReadable = false
            statusMessage = "Apple Health export queue could not be read. Pending exports are unknown; original data was preserved."
            return nil
        }
    }

    private func savePendingWorkouts(_ items: [PendingHealthWorkout]) -> Bool {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: workoutOutboxKey)
            guard let saved = UserDefaults.standard.data(forKey: workoutOutboxKey),
                  let verified = try? JSONDecoder().decode([PendingHealthWorkout].self, from: saved),
                  verified.map(\.id) == items.map(\.id) else {
                isWorkoutOutboxReadable = false
                statusMessage = "Apple Health export queue could not be verified. The export was not marked complete."
                return false
            }
            isWorkoutOutboxReadable = true
            pendingWorkoutExportCount = verified.count
            return true
        } catch {
            statusMessage = "Apple Health export could not be queued: \(error.localizedDescription)"
            return false
        }
    }

    private func enqueueWorkout(_ item: PendingHealthWorkout) -> Bool {
        guard var items = loadPendingWorkouts() else { return false }
        if !items.contains(where: { $0.id == item.id }) { items.append(item) }
        return savePendingWorkouts(items)
    }

    private func acknowledgeWorkout(_ id: UUID) {
        guard let items = loadPendingWorkouts() else { return }
        _ = savePendingWorkouts(items.filter { $0.id != id })
    }

    func retryPendingWorkoutExports() {
        guard !isRetryingWorkoutOutbox, isAvailable else { return }
        guard let items = loadPendingWorkouts(), !items.isEmpty else { return }
        isRetryingWorkoutOutbox = true
        retryNextWorkout(items, index: 0)
    }

    private func retryNextWorkout(_ items: [PendingHealthWorkout], index: Int) {
        guard index < items.count else {
            isRetryingWorkoutOutbox = false
            return
        }
        let item = items[index]
        saveActivityWorkout(id: item.id, activity: item.activity, startedAt: item.startedAt,
                            finishedAt: item.finishedAt, steps: item.steps,
                            distanceMeters: item.distanceMeters) { [weak self] _ in
            Task { @MainActor in self?.retryNextWorkout(items, index: index + 1) }
        }
    }

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
        // Ask for workout and measured-distance write access when the member connects,
        // rather than surprising them with a second permission sheet only after a walk.
        // HealthKit does not disclose whether read or write access was individually denied.
        let workoutType = HKObjectType.workoutType()
        let shareTypes: Set<HKSampleType> = [workoutType, distanceType]
        let readTypes: Set<HKObjectType> = [stepType, energyType, distanceType, exerciseType, heartRateType, workoutType]
        store.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.statusMessage = "Health permission request failed: \(error.localizedDescription)"
                    return
                }
                UserDefaults.standard.set(true, forKey: self.connectionRequestedKey)
                self.hasRequestedAccess = true
                self.statusMessage = "Apple Health permissions requested for measured health data and GATIVX workout export. Checking today's steps…"
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
        // Clear prior readings before querying. A failed or denied read must not
        // leave yesterday's successful value looking like a current measurement.
        todayWalkingRunningDistanceKm = nil
        todayExerciseMinutes = nil
        todayAverageHeartRateBPM = nil
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
        // Observe every quantity shown on the dashboard so each metric can
        // refresh independently when HealthKit reports a change.
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
        let pending = PendingHealthWorkout(id: id, activity: activity, startedAt: startedAt,
                                           finishedAt: finishedAt, steps: steps, distanceMeters: distanceMeters)
        guard enqueueWorkout(pending) else {
            completion(.failure(NSError(domain: "GATIVXHealthKit", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The Apple Health export could not be safely queued. The local activity remains saved."])))
            return
        }
        guard isAvailable else {
            completion(.failure(NSError(domain: "GATIVXHealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Apple Health is unavailable on this iPhone."])))
            return
        }
        let workoutType = HKObjectType.workoutType()
        // The builder writes the workout plus its measured distance sample.
        let shareTypes: Set<HKSampleType> = [workoutType, distanceType]
        // Request workout read access as well as write access so the stable
        // sync identifier can be checked before attempting an export retry.
        let readTypes: Set<HKObjectType> = [self.stepType, self.energyType, workoutType]
        store.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] _, error in
            guard let self else { return }
            if let error { DispatchQueue.main.async { completion(.failure(error)) }; return }
            let syncID = "gativx.activity.\(id.uuidString)"
            let syncPredicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncID])
            let existing = HKSampleQuery(sampleType: workoutType, predicate: syncPredicate, limit: 1, sortDescriptors: nil) { [weak self] _, samples, queryError in
                guard let self else { return }
                if let queryError { DispatchQueue.main.async { completion(.failure(queryError)) }; return }
                if samples?.isEmpty == false { DispatchQueue.main.async { self.acknowledgeWorkout(id); completion(.success(())) }; return }

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
                    HKMetadataKeySyncVersion: 1
                ]
                // Preserve unavailable measurements as unavailable. Never export a
                // synthetic zero step count when the pedometer did not provide one.
                if let steps {
                    metadata["com.paramitsolutions.gativx.measuredSteps"] = steps
                }
                let totalDistance: HKQuantity?
                if let distanceMeters, distanceMeters > 0 {
                    metadata["com.paramitsolutions.gativx.measuredDistanceMeters"] = distanceMeters
                    totalDistance = HKQuantity(unit: .meter(), doubleValue: distanceMeters)
                } else {
                    totalDistance = nil
                }
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = type
                configuration.locationType = .unknown
                let builder = HKWorkoutBuilder(
                    healthStore: self.store,
                    configuration: configuration,
                    device: .local()
                )

                builder.beginCollection(withStart: startedAt) { began, beginError in
                    guard began else {
                        DispatchQueue.main.async {
                            completion(.failure(beginError ?? NSError(
                                domain: "GATIVXHealthKit",
                                code: 4,
                                userInfo: [NSLocalizedDescriptionKey: "Apple Health could not begin the workout export."]
                            )))
                        }
                        return
                    }

                    builder.addMetadata(metadata) { metadataSaved, metadataError in
                        guard metadataSaved else {
                            DispatchQueue.main.async {
                                completion(.failure(metadataError ?? NSError(
                                    domain: "GATIVXHealthKit",
                                    code: 5,
                                    userInfo: [NSLocalizedDescriptionKey: "Apple Health could not save workout metadata."]
                                )))
                            }
                            return
                        }

                        let finishCollection = {
                            builder.endCollection(withEnd: safeEnd) { ended, endError in
                                guard ended else {
                                    DispatchQueue.main.async {
                                        completion(.failure(endError ?? NSError(
                                            domain: "GATIVXHealthKit",
                                            code: 6,
                                            userInfo: [NSLocalizedDescriptionKey: "Apple Health could not finish collecting the workout."]
                                        )))
                                    }
                                    return
                                }

                                builder.finishWorkout { workout, finishError in
                                    DispatchQueue.main.async {
                                        if let finishError {
                                            completion(.failure(finishError))
                                        } else if workout != nil {
                                            self.acknowledgeWorkout(id)
                                            completion(.success(()))
                                        } else {
                                            completion(.failure(NSError(
                                                domain: "GATIVXHealthKit",
                                                code: 2,
                                                userInfo: [NSLocalizedDescriptionKey: "Apple Health did not confirm saving this workout."]
                                            )))
                                        }
                                    }
                                }
                            }
                        }

                        guard let totalDistance else {
                            finishCollection()
                            return
                        }

                        let distanceSample = HKQuantitySample(
                            type: self.distanceType,
                            quantity: totalDistance,
                            start: startedAt,
                            end: safeEnd
                        )
                        builder.add([distanceSample]) { distanceSaved, distanceError in
                            guard distanceSaved else {
                                DispatchQueue.main.async {
                                    completion(.failure(distanceError ?? NSError(
                                        domain: "GATIVXHealthKit",
                                        code: 7,
                                        userInfo: [NSLocalizedDescriptionKey: "Apple Health could not save the measured workout distance."]
                                    )))
                                }
                                return
                            }
                            finishCollection()
                        }
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
        // Stop background delivery for every quantity registered by startObserving().
        // Disabling only steps and energy leaves three HealthKit delivery registrations
        // active after the member disconnects GATIVX.
        for type in [stepType, energyType, distanceType, exerciseType, heartRateType] {
            store.disableBackgroundDelivery(for: type) { _, _ in }
        }
        todaySteps = nil
        todayActiveEnergyKcal = nil
        todayWalkingRunningDistanceKm = nil
        todayExerciseMinutes = nil
        todayAverageHeartRateBPM = nil
        lastRefresh = nil
        statusMessage = "Apple Health disconnected in GATIVX."
    }
}
