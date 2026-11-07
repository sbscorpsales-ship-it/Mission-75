import Foundation
import Combine
import HealthKit

@MainActor
final class HealthSteps: ObservableObject {
    @Published private(set) var steps: Int = 0
    @Published private(set) var status = "Connect Apple Health"
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    private let store = HKHealthStore()
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!

    func requestAccessAndRefresh() {
        guard isAvailable else { status = "Apple Health unavailable"; return }
        store.requestAuthorization(toShare: [], read: [stepType]) { [weak self] success, error in
            Task { @MainActor in
                if let error { self?.status = error.localizedDescription; return }
                self?.status = success ? "Apple Health connected" : "Check Health permissions"
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard isAvailable else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, result, _ in
            let count = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            Task { @MainActor in self?.steps = Int(count.rounded()) }
        }
        store.execute(query)
    }
}
