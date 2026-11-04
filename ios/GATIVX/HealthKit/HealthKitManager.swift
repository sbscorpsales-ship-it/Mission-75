import Foundation
import HealthKit
import Combine

/// Read-only HealthKit integration for GATIVX.
/// HealthKit owns aggregation across iPhone, Apple Watch, and other authorized sources.
@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var todaySteps: Int = 0
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var statusMessage = "Apple Health is not connected."

    var onDailyTotal: ((Date, Int) -> Void)?

    private let store = HKHealthStore()
    private var stepObserver: HKObserverQuery?
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!

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
                // HealthKit intentionally does not reveal whether read access was denied.
                self.startObserving()
                self.refreshRecentDays()
                self.statusMessage = "Apple Health access request completed. Waiting for available step data."
            }
        }
    }

    /// Fetches daily cumulative totals for the current day and previous 29 local days.
    /// Each total is a HealthKit aggregate, not a sum of raw samples in app code.
    func refreshRecentDays(days: Int = 30, onComplete: (() -> Void)? = nil) {
        guard isAvailable else { onComplete?(); return }
        isRefreshing = true

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: today),
              let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) else {
            isRefreshing = false
            onComplete?()
            return
        }

        var anchorComponents = calendar.dateComponents([.year, .month, .day], from: today)
        anchorComponents.hour = 0
        guard let anchor = calendar.date(from: anchorComponents) else {
            isRefreshing = false
            onComplete?()
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
                    onComplete?()
                }
                if let error {
                    self.statusMessage = "Could not read Apple Health steps: \(error.localizedDescription)"
                    return
                }
                guard let collection else {
                    self.statusMessage = "No step summary is available yet."
                    return
                }

                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let total = Int(statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    let day = calendar.startOfDay(for: statistics.startDate)
                    self.onDailyTotal?(day, max(0, total))
                    if calendar.isDateInToday(day) {
                        self.todaySteps = max(0, total)
                    }
                }
                self.statusMessage = "Apple Health step totals refreshed."
            }
        }
        store.execute(query)
    }

    /// Register once after HealthKit permission is requested.
    /// iOS background delivery is periodic/best-effort, not a real-time guarantee.
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
                    self?.statusMessage = "Apple Health background updates are enabled where iOS permits."
                }
            }
        }
    }

    func refreshOnForeground() {
        refreshRecentDays()
    }

    func stopObserving() {
        if let stepObserver {
            store.stop(stepObserver)
            self.stepObserver = nil
        }
        store.disableBackgroundDelivery(for: stepType) { _, _ in }
    }
}
