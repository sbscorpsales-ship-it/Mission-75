import Foundation
import Combine
import HealthKit

@MainActor
final class HealthSteps: ObservableObject {
    @Published private(set) var steps: Int = 0
    @Published private(set) var status = "Apple Health connection not checked"
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var hasStepSamples = false
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()

    private let store = HKHealthStore()
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
    private var observerQuery: HKObserverQuery?
    private var didRequestAuthorization = false

    func requestAccessAndRefresh() {
        guard isAvailable else {
            status = "Apple Health unavailable on this device"
            return
        }
        guard !didRequestAuthorization else {
            refresh()
            return
        }
        didRequestAuthorization = true
        store.requestAuthorization(toShare: [], read: [stepType]) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.status = "Health request failed: \(error.localizedDescription)"
                    return
                }
                // HealthKit deliberately does not disclose read authorization status to an app.
                // A successful request callback is not proof that read access was granted.
                self.status = success
                    ? "Checking Apple Health step data…"
                    : "Apple Health request could not be completed"
                self.installObserverIfNeeded()
                self.refresh()
            }
        }
    }

    func refresh() {
        guard isAvailable else {
            status = "Apple Health unavailable"
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
            let quantity = result?.sumQuantity()
            let count = quantity?.doubleValue(for: .count())
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.status = "Step data unavailable: \(error.localizedDescription)"
                    self.hasStepSamples = false
                    self.lastUpdated = Date()
                    return
                }
                guard let count else {
                    self.steps = 0
                    self.hasStepSamples = false
                    self.status = "No readable step samples for today"
                    self.lastUpdated = Date()
                    return
                }
                self.steps = max(0, Int(count.rounded()))
                self.hasStepSamples = true
                self.status = "Apple Health data refreshed"
                self.lastUpdated = Date()
            }
        }
        store.execute(query)
    }

    private func installObserverIfNeeded() {
        guard observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completion, error in
            if let error {
                Task { @MainActor in
                    self?.status = "Health update notification failed: \(error.localizedDescription)"
                    completion()
                }
                return
            }
            Task { @MainActor in
                self?.refresh()
                completion()
            }
        }
        observerQuery = query
        store.execute(query)
        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { [weak self] success, error in
            guard let error else { return }
            Task { @MainActor in
                self?.status = success
                    ? "Background refresh enabled"
                    : "Background refresh unavailable: \(error.localizedDescription)"
            }
        }
    }
}
