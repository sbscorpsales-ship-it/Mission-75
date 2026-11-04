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
                // HealthKit does not reveal whether read access was denied. A successful
                // request call is not proof that the user granted access; query results
                // may legitimately be empty.
                self.startObserving()
                self.refreshToday()
                self.statusMessage = "Apple Health connection requested. Waiting for available step data."
            }
        }
    }

    func refreshToday(onComplete: (() -> Void)? = nil) {
        guard isAvailable else {
            onComplete?()
            return
        }
        isRefreshing = true

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            isRefreshing = false
            onComplete?()
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, statistics, error in
            let count = Int(statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            Task { @MainActor in
                guard let self else {
                    onComplete?()
                    return
                }
                if let error {
                    self.statusMessage = "Could not read today's steps: \(error.localizedDescription)"
                } else {
                    self.todaySteps = max(0, count)
                    self.lastRefresh = Date()
                    self.statusMessage = "Step total refreshed from Apple Health."
                }
                self.isRefreshing = false
                onComplete?()
            }
        }
        store.execute(query)
    }

    /// Call after the user signs in and the app is ready to sync.
    /// The observer re-queries the aggregate; it does not attempt to sum raw samples.
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
                self.refreshToday(onComplete: completion)
            }
        }
        stepObserver = observer
        store.execute(observer)

        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { [weak self] success, error in
            Task { @MainActor in
                if let error {
                    self?.statusMessage = "Background step refresh is unavailable: \(error.localizedDescription)"
                } else if success {
                    self?.statusMessage = "Apple Health updates enabled (iOS may deliver them periodically)."
                }
            }
        }
    }

    func stopObserving() {
        if let stepObserver {
            store.stop(stepObserver)
            self.stepObserver = nil
        }
        store.disableBackgroundDelivery(for: stepType) { _, _ in }
    }
}
