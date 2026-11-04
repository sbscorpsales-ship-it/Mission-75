import Foundation
import HealthKit
import Combine

/// Read-only HealthKit integration. HealthKit performs source aggregation so
/// GATIVX does not add overlapping iPhone and wearable step samples itself.
@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var todaySteps: Int?
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var statusMessage = "Apple Health is not connected."

    var onDailyTotal: ((Date, Int) -> Void)?

    private let store = HKHealthStore()
    private let connectionRequestedKey = "gativx.healthkit.connectionRequested"
    private var stepObserver: HKObserverQuery?
    private var refreshCompletions: [() -> Void] = []
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!

    /// Call on launch. The app remembers that the user initiated Health access,
    /// then re-registers its observer after every app restart.
    func resumeIfPreviouslyConnected() {
        guard UserDefaults.standard.bool(forKey: connectionRequestedKey) else { return }
        guard isAvailable else {
            statusMessage = "Apple Health is not available on this device."
            return
        }
        startObserving()
        refreshRecentDays()
    }

    func requestReadAccessAndStart() {
        guard isAvailable else {
            statusMessage = "Apple Health is not available on this device."
            return
        }

        store.requestAuthorization(toShare: [], read: [stepType]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.statusMessage = "Health access request failed: \(error.localizedDescription)"
                    return
                }
                // HealthKit does not reveal whether read access was denied.
                UserDefaults.standard.set(true, forKey: self.connectionRequestedKey)
                self.startObserving()
                self.refreshRecentDays()
                self.statusMessage = "Apple Health connection requested. Waiting for step data."
            }
        }
    }

    /// Fetch daily cumulative totals for today and the previous 29 local days.
    /// Missing samples remain nil; they are never represented as a measured zero.
    func refreshRecentDays(days: Int = 30, onComplete: (() -> Void)? = nil) {
        guard isAvailable else { onComplete?(); return }
        if isRefreshing {
            if let onComplete { refreshCompletions.append(onComplete) }
            return
        }
        isRefreshing = true
        if let onComplete { refreshCompletions.append(onComplete) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: today),
              let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) else {
            isRefreshing = false
            let completions = refreshCompletions
            refreshCompletions.removeAll()
            completions.forEach { $0() }
            return
        }

        var anchorComponents = calendar.dateComponents([.year, .month, .day], from: today)
        anchorComponents.hour = 0
        guard let anchor = calendar.date(from: anchorComponents) else {
            isRefreshing = false
            let completions = refreshCompletions
            refreshCompletions.removeAll()
            completions.forEach { $0() }
            return
        }

        let query = HKStatisticsCollectionQuery(
            quantityType: stepType,
            quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )

        query.initialResultsHandler = { [weak self] _, collection, error in
            Task { @MainActor in
                guard let self else { return }
                defer {
                    self.isRefreshing = false
                    self.lastRefresh = Date()
                    let completions = self.refreshCompletions
                    self.refreshCompletions.removeAll()
                    completions.forEach { $0() }
                }
                if let error {
                    self.statusMessage = "Could not read Apple Health steps: \(error.localizedDescription)"
                    return
                }
                guard let collection else {
                    self.todaySteps = nil
                    self.statusMessage = "Apple Health returned no step summary."
                    return
                }

                self.todaySteps = nil
                var foundToday = false
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let day = calendar.startOfDay(for: statistics.startDate)
                    guard let quantity = statistics.sumQuantity() else { return }
                    let total = max(0, Int(quantity.doubleValue(for: .count())))
                    self.onDailyTotal?(day, total)
                    if calendar.isDateInToday(day) {
                        foundToday = true
                        self.todaySteps = total
                    }
                }
                self.statusMessage = foundToday
                    ? "Apple Health step totals refreshed."
                    : "No step samples returned. Check Health access and device data; no zero has been assumed."
            }
        }
        store.execute(query)
    }

    /// iOS background delivery is best-effort and not a real-time guarantee.
    func startObserving() {
        guard stepObserver == nil, isAvailable else { return }

        let observer = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completion, error in
            guard let self else {
                completion()
                return
            }
            if error != nil {
                completion()
                return
            }
            Task { @MainActor in
                self.refreshRecentDays(days: 30, onComplete: completion)
            }
        }
        stepObserver = observer
        store.execute(observer)

        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { [weak self] success, error in
            Task { @MainActor in
                if let error {
                    self?.statusMessage = "Background refresh unavailable: \(error.localizedDescription)"
                } else if success {
                    self?.statusMessage = "Apple Health background updates enabled where iOS permits."
                }
            }
        }
    }

    func refreshOnForeground() {
        refreshRecentDays()
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: connectionRequestedKey)
        if let stepObserver {
            store.stop(stepObserver)
            self.stepObserver = nil
        }
        store.disableBackgroundDelivery(for: stepType) { _, _ in }
        todaySteps = nil
        statusMessage = "Apple Health connection stopped in GATIVX."
    }
}
