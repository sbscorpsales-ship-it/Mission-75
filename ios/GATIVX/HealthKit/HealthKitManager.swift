import Foundation
import HealthKit
import Combine

/// Native, read-only Apple Health daily aggregate.
/// HealthKit is the authority for the all-source daily total; CoreMotion is never added to it.
@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var todaySteps: Int?
    @Published private(set) var todayActiveEnergyKcal: Int?
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var statusMessage = "Apple Health is not connected."
    var onDailyTotal: ((Date, Int) -> Void)?
    var onActiveEnergy: ((Date, Int) -> Void)?

    private let store = HKHealthStore()
    private let connectionRequestedKey = "gativx.healthkit.connectionRequested"
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
    private let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    private var observers: [HKObserverQuery] = []
    private var refreshAgain = false
    private var pendingCompletions: [() -> Void] = []

    func resumeIfPreviouslyConnected() {
        guard UserDefaults.standard.bool(forKey: connectionRequestedKey) else { return }
        guard isAvailable else { statusMessage = "Apple Health is unavailable on this iPhone."; return }
        startObserving()
        refreshRecentDays()
    }

    func requestReadAccessAndStart() {
        guard isAvailable else { statusMessage = "Apple Health is unavailable on this iPhone."; return }
        store.requestAuthorization(toShare: [], read: [stepType, energyType]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.statusMessage = "Health permission request failed: \(error.localizedDescription)"
                    return
                }
                // HealthKit intentionally does not reveal whether read access was denied.
                UserDefaults.standard.set(true, forKey: self.connectionRequestedKey)
                self.startObserving()
                self.refreshRecentDays()
                self.statusMessage = "Health access requested. Checking today's measured steps…"
            }
        }
    }

    /// Query one local calendar-day cumulative aggregate. Missing data remains nil, never a fabricated zero.
    func refreshRecentDays(days: Int = 30, onComplete: (() -> Void)? = nil) {
        guard UserDefaults.standard.bool(forKey: connectionRequestedKey), isAvailable else {
            onComplete?()
            return
        }
        if let onComplete { pendingCompletions.append(onComplete) }
        guard !isRefreshing else { refreshAgain = true; return }
        isRefreshing = true
        let start = Calendar.current.startOfDay(for: Date())
        let end = min(Date(), Calendar.current.date(byAdding: .day, value: 1, to: start) ?? Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, statistics, error in
            Task { @MainActor in
                guard let self else { onComplete?(); return }
                defer {
                    self.isRefreshing = false
                    let completions = self.pendingCompletions
                    self.pendingCompletions.removeAll()
                    completions.forEach { $0() }
                    if self.refreshAgain {
                        self.refreshAgain = false
                        self.refreshRecentDays(days: days)
                    }
                }
                if let error {
                    self.statusMessage = "Apple Health read failed: \(error.localizedDescription)"
                    return
                }
                guard let quantity = statistics?.sumQuantity() else {
                    self.todaySteps = nil
                    self.lastRefresh = Date()
                    self.statusMessage = "No step samples returned for today. No zero has been assumed."
                    return
                }
                let total = max(0, Int(quantity.doubleValue(for: .count()).rounded()))
                self.todaySteps = total
                self.lastRefresh = Date()
                self.statusMessage = "Apple Health daily aggregate refreshed."
                self.onDailyTotal?(start, total)
            }
        }
        store.execute(query)
    }

    private func refreshTodayEnergy(onComplete: (() -> Void)? = nil) {
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, statistics, _ in
            Task { @MainActor in
                guard let self else { onComplete?(); return }
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

    func startObserving() {
        guard observers.isEmpty, isAvailable else { return }
        // Observe both quantities so a change in active energy refreshes calories
        // even when no new step sample is written at the same time.
        for type in [stepType, energyType] {
            let observedType = type
            let query = HKObserverQuery(sampleType: observedType, predicate: nil) { [weak self] _, completion, error in
                guard let self else { completion(); return }
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    if observedType.identifier == HKQuantityTypeIdentifier.activeEnergyBurned.rawValue {
                        self.refreshTodayEnergy(onComplete: completion)
                    } else {
                        self.refreshRecentDays(onComplete: completion)
                    }
                }
            }
            observers.append(query)
            store.execute(query)
            store.enableBackgroundDelivery(for: observedType, frequency: .hourly) { [weak self] success, error in
                Task { @MainActor in
                    if let error { self?.statusMessage = "Apple Health background refresh unavailable: \(error.localizedDescription)" }
                    else if success { self?.statusMessage = "Apple Health step and active-energy updates enabled where iOS permits." }
                }
            }
        }
    }

    func refreshOnForeground() { refreshRecentDays() }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: connectionRequestedKey)
        observers.forEach { store.stop($0) }
        observers.removeAll()
        store.disableBackgroundDelivery(for: stepType) { _, _ in }
        store.disableBackgroundDelivery(for: energyType) { _, _ in }
        todaySteps = nil
        todayActiveEnergyKcal = nil
        lastRefresh = nil
        statusMessage = "Apple Health disconnected in GATIVX."
    }
}
