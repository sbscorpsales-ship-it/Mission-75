import Foundation

struct HealthKitWorkoutExportCoalescer {
    typealias Completion = (Result<Void, Error>) -> Void
    private var waiting: [UUID: [Completion]] = [:]

    mutating func begin(id: UUID, completion: @escaping Completion) -> Bool {
        if waiting[id] != nil {
            waiting[id]?.append(completion)
            return false
        }
        waiting[id] = [completion]
        return true
    }

    mutating func finish(id: UUID) -> [Completion] {
        waiting.removeValue(forKey: id) ?? []
    }

    func isInFlight(_ id: UUID) -> Bool {
        waiting[id] != nil
    }
}
