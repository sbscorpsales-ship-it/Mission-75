import Foundation
import HealthKit
import Combine

/// Native, read-only Apple Health daily aggregate.
/// HealthKit is the authority for the all-source daily total; CoreMotion is never added to it.
@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var todaySteps: Int?
    @Published private(set) var todayActiveEnergyKcal: Int?
    @Published private(set) var todaySleepMinutes: Int?
    @Published private(set) var sleepStatusMessage = "No measured sleep data available yet."
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var statusMessage = "Apple Health is not connected."
    var onDailyTotal: ((Date, Int) -> Void)?
    var onActiveEnergy: ((Date, Int) -> Void)?
    var onSleep: ((Date, Int) -> Void)?

    private let store = HKHealthStore()
    private let connectionRequestedKey = "gativx.healthkit.connectionRequested"
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
    private let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private var observers: [HKObserverQuery] = []
    private var refreshAgain = false
    private var pendingCompletions: [() -> Void] = []

    func resumeIfPreviouslyConnected() {
        guard UserDefaults.standard.bool(forKey: connectionRequestedKey) else { return }
        guard isAvailable else { statusMessage = "Apple Health is unavailable on this iPhone."; return }
        startObserving()
        refreshRecentDays()
        refreshTodayEnergy()
        refreshTodaySleep()
    }

    func requestReadAccessAndStart() {
        guard isAvailable else { statusMessage = "Apple Health is unavailable on this iPhone."; return }
        store.requestAuthorization(toShare: [], read: [stepType, energyType, sleepType]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.statusMessage = "Health permission request failed: \(error.localizedDescription)"
                    return
                }
                // HealthKit intentionally does not reveal whether read access was denied.
                UserDefaults.standard.set(true, forKey: self.connectionRequestedKey)
                self.statusMessage = "Apple Health access was requested. Checking today's measured steps…"
                self.startObserving()
                self.refreshRecentDays()
                self.refreshTodayEnergy()
                self.refreshTodaySleep()
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

    /// Reads asleep stages from the previous 36 hours. Overlapping records are
    /// merged, and the latest sleep episode is attributed to its local wake-up day.
    func refreshTodaySleep(onComplete: (() -> Void)? = nil) {
        guard UserDefaults.standard.bool(forKey: connectionRequestedKey), isAvailable else {
            onComplete?()
            return
        }
        let now = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: now) ?? now.addingTimeInterval(-36 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { [weak self] _, samples, error in
            Task { @MainActor in
                guard let self else { onComplete?(); return }
                defer { onComplete?() }
                if let error {
                    self.todaySleepMinutes = nil
                    self.sleepStatusMessage = "Apple Health sleep read failed: \(error.localizedDescription)"
                    return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let intervals = (samples as? [HKCategorySample] ?? []).compactMap { sample -> DateInterval? in
                    guard asleepValues.contains(sample.value), sample.endDate > sample.startDate else { return nil }
                    return DateInterval(start: sample.startDate, end: sample.endDate)
                }.sorted { $0.start < $1.start }

                var episodes: [[DateInterval]] = []
                for interval in intervals {
                    if let last = episodes.indices.last,
                       let previous = episodes[last].last,
                       interval.start.timeIntervalSince(previous.end) <= 90 * 60 {
                        episodes[last].append(interval)
                    } else {
                        episodes.append([interval])
                    }
                }
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: now)
                let latestEpisode = episodes
                    .filter { episode in episode.last.map { calendar.isDate($0.end, inSameDayAs: today) } ?? false }
                    .max { ($0.last?.end ?? .distantPast) < ($1.last?.end ?? .distantPast) }

                guard let episode = latestEpisode, let first = episode.first else {
                    self.todaySleepMinutes = nil
                    self.sleepStatusMessage = "No measured asleep stages were returned for the latest local wake-up day. No sleep duration has been assumed."
                    return
                }
                var mergedStart = first.start
                var mergedEnd = first.end
                var seconds: TimeInterval = 0
                for interval in episode.dropFirst() {
                    if interval.start <= mergedEnd {
                        mergedEnd = max(mergedEnd, interval.end)
                    } else {
                        seconds += mergedEnd.timeIntervalSince(mergedStart)
                        mergedStart = interval.start
                        mergedEnd = interval.end
                    }
                }
                seconds += mergedEnd.timeIntervalSince(mergedStart)
                let minutes = max(0, Int((seconds / 60).rounded()))
                self.todaySleepMinutes = minutes > 0 ? minutes : nil
                if minutes > 0 {
                    self.sleepStatusMessage = "Measured Apple Health sleep: \(minutes / 60)h \(minutes % 60)m, attributed to the local wake-up day."
                    self.onSleep?(today, minutes)
                } else {
                    self.sleepStatusMessage = "No measured sleep duration is available. No zero has been assumed."
                }
            }
        }
        store.execute(query)
    }

    func startObserving() {
        guard observers.isEmpty, isAvailable else { return }
        // Observe both quantities so a change in active energy refreshes calories
        // even when no new step sample is written at the same time.
        let observedTypes: [HKSampleType] = [stepType, energyType, sleepType]
        for type in observedTypes {
            let observedType = type
            let query = HKObserverQuery(sampleType: observedType, predicate: nil) { [weak self] _, completion, error in
                guard let self else { completion(); return }
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    if observedType.identifier == HKQuantityTypeIdentifier.activeEnergyBurned.rawValue {
                        self.refreshTodayEnergy(onComplete: completion)
                    } else if observedType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
                        self.refreshTodaySleep(onComplete: completion)
                    } else {
                        self.refreshRecentDays(onComplete: completion)
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
        refreshTodaySleep()
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: connectionRequestedKey)
        observers.forEach { store.stop($0) }
        observers.removeAll()
        store.disableBackgroundDelivery(for: stepType) { _, _ in }
        store.disableBackgroundDelivery(for: energyType) { _, _ in }
        store.disableBackgroundDelivery(for: sleepType) { _, _ in }
        todaySteps = nil
        todayActiveEnergyKcal = nil
        todaySleepMinutes = nil
        sleepStatusMessage = "Apple Health disconnected in GATIVX."
        lastRefresh = nil
        statusMessage = "Apple Health disconnected in GATIVX."
    }
}
