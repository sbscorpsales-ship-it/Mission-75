import Foundation
import Combine
import HealthKit

@MainActor
final class HealthSteps: ObservableObject {
    @Published private(set) var steps: Int?
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
            steps = nil
            hasStepSamples = false
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
                    self.steps = nil
                    self.hasStepSamples = false
                    self.status = "Health request failed: " + error.localizedDescription
                    self.didRequestAuthorization = false
                    return
                }
                // HealthKit deliberately does not disclose read authorization status to an app.
                // A successful request callback is not proof that read access was granted.
                self.status = success
                    ? "Checking Apple Health step data…"
                    : "Apple Health request could not be completed"
                if !success {
                    self.didRequestAuthorization = false
                    return
                }
                self.installObserverIfNeeded()
                self.refresh()
            }
        }
    }

    /// A missing HealthKit aggregate remains nil; zero is shown only for an actual sample total of zero.
    func refresh(completion: (() -> Void)? = nil) {
        guard isAvailable else {
            steps = nil
            hasStepSamples = false
            status = "Apple Health unavailable"
            lastUpdated = Date()
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
            let quantity = result?.sumQuantity()
            let count = quantity?.doubleValue(for: .count())
            Task { @MainActor in
                guard let self else {
                    completion?()
                    return
                }
                defer { completion?() }
                if let error {
                    self.steps = nil
                    self.hasStepSamples = false
                    self.status = "Step data unavailable: " + error.localizedDescription
                    self.lastUpdated = Date()
                    return
                }
                guard let count else {
                    self.steps = nil
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
                    self?.status = "Health update notification failed: " + error.localizedDescription
                    completion()
                }
                return
            }
            Task { @MainActor in
                guard let self else {
                    completion()
                    return
                }
                // Acknowledge the HealthKit delivery only after the refresh query finishes.
                self.refresh(completion: completion)
            }
        }
        observerQuery = query
        store.execute(query)
        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { [weak self] success, error in
            Task { @MainActor in
                if success {
                    self?.status = "Apple Health background refresh enabled"
                } else if let error {
                    self?.status = "Background refresh unavailable: " + error.localizedDescription
                } else {
                    self?.status = "Apple Health background refresh unavailable"
                }
            }
        }
    }
}
