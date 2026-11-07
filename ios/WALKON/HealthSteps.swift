import Foundation
import Combine
import HealthKit

@MainActor
final class HealthSteps: ObservableObject {
    @Published private(set) var steps: Int?
    @Published private(set) var status = "Apple Health has not been checked"
    @Published private(set) var lastUpdated: Date?

    #if targetEnvironment(simulator)
    private let store: HKHealthStore? = nil
    #else
    private let store: HKHealthStore? = HKHealthStore()
    #endif
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
    private var observerInstalled = false

    func requestAccessAndRefresh() {
        #if targetEnvironment(simulator)
        status = "Apple Health step access requires a physical iPhone"
        #else
        guard HKHealthStore.isHealthDataAvailable(), let store else {
            status = "Apple Health is unavailable on this device"
            return
        }
        status = "Requesting Apple Health access"
        store.requestAuthorization(toShare: [], read: [stepType]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.status = "Apple Health request failed: \(error.localizedDescription)"
                    return
                }
                // HealthKit intentionally does not reveal whether read access was denied.
                self.status = "Checking today's available step data"
                self.installObserverIfNeeded()
                self.refresh()
            }
        }
        #endif
    }

    func refresh() { refresh(completion: nil) }

    private func refresh(completion: (() -> Void)?) {
        #if targetEnvironment(simulator)
        status = "Apple Health step access requires a physical iPhone"
        completion?()
        return
        #else
        guard HKHealthStore.isHealthDataAvailable(), let store else {
            status = "Apple Health is unavailable on this device"
            completion?()
            return
        }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: .strictStartDate
        )
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            Task { @MainActor in
                guard let self else { completion?(); return }
                if let error {
                    self.status = "Could not read Apple Health: \(error.localizedDescription)"
                    completion?()
                    return
                }
                guard let quantity = result?.sumQuantity() else {
                    self.steps = nil
                    self.status = "No step total is available for today"
                    self.lastUpdated = Date()
                    completion?()
                    return
                }
                self.steps = max(Int(quantity.doubleValue(for: .count()).rounded()), 0)
                self.lastUpdated = Date()
                self.status = "Apple Health total updated"
                completion?()
            }
        }
        store.execute(query)
        #endif
    }

    private func installObserverIfNeeded() {
        guard !observerInstalled, let store else { return }
        observerInstalled = true
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completion, error in
            guard error == nil else { completion(); return }
            Task { @MainActor in
                guard let self else { completion(); return }
                self.refresh(completion: completion)
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { [weak self] success, _ in
            if !success {
                Task { @MainActor in
                    self?.status = "Apple Health connected; background refresh is limited"
                }
            }
        }
    }
}
