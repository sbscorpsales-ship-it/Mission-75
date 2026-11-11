import Foundation
import CoreMotion
import Combine

/// Low-power motion classification that starts GPS only after sustained walking
/// and closes a session after a sustained stationary period.
final class AutomaticWalkDetector: ObservableObject {
    @Published private(set) var status = "Automatic walk detection is starting…"

    var onWalkDetected: (() -> Void)?
    var onStationaryDetected: (() -> Void)?

    private let motion = CMMotionActivityManager()
    private var startWork: DispatchWorkItem?
    private var stopWork: DispatchWorkItem?
    private var sessionIsActive = false
    private var monitoring = false

    private let walkConfirmation: TimeInterval = 25
    private let stationaryGrace: TimeInterval = 180

    func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            status = "Automatic walk detection is not supported on this iPhone."
            return
        }
        guard !monitoring else { return }
        monitoring = true
        status = "Waiting for a confirmed walk…"
        motion.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            self.consume(activity)
        }
    }

    func stopMonitoring() {
        motion.stopActivityUpdates()
        startWork?.cancel()
        stopWork?.cancel()
        startWork = nil
        stopWork = nil
        monitoring = false
        status = "Automatic walk detection paused."
    }

    func markSessionStarted() {
        sessionIsActive = true
        startWork?.cancel()
        startWork = nil
        status = "Walk detected · GPS session active."
    }

    func markSessionFinished() {
        sessionIsActive = false
        stopWork?.cancel()
        stopWork = nil
        status = "Session saved · waiting for the next walk."
    }

    private func consume(_ activity: CMMotionActivity) {
        let confident = activity.confidence == .medium || activity.confidence == .high
        let walking = confident && (activity.walking || activity.running)

        if walking {
            stopWork?.cancel()
            stopWork = nil
            guard !sessionIsActive, startWork == nil else { return }
            status = "Walking detected · confirming movement…"
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.sessionIsActive else { return }
                self.startWork = nil
                self.sessionIsActive = true
                self.status = "Walk confirmed · starting GPS recording."
                self.onWalkDetected?()
            }
            startWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + walkConfirmation, execute: work)
            return
        }

        startWork?.cancel()
        startWork = nil

        guard sessionIsActive, confident, activity.stationary, stopWork == nil else { return }
        status = "Stationary · allowing a short pause before saving…"
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sessionIsActive else { return }
            self.stopWork = nil
            self.sessionIsActive = false
            self.status = "Walk ended · saving your activity."
            self.onStationaryDetected?()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + stationaryGrace, execute: work)
    }
}
