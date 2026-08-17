// AppTimer idle monitor: observes local keyboard and pointer inactivity for automatic local pause.
import ApplicationServices
import Foundation

@MainActor
final class IdleMonitor {
    var onIdleThresholdReached: (() -> Void)?

    private var timer: Timer?
    private var threshold: TimeInterval = 300
    private var reportedCurrentIdlePeriod = false

    var secondsSinceUserInput: TimeInterval {
        let source = CGEventSourceStateID.combinedSessionState
        let eventTypes: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(source, eventType: $0) }
            .min() ?? 0
    }

    func start(threshold: TimeInterval) {
        self.threshold = max(60, threshold)
        reportedCurrentIdlePeriod = false
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkIdleState() }
        }
        checkIdleState()
    }

    func updateThreshold(_ threshold: TimeInterval) {
        self.threshold = max(60, threshold)
        reportedCurrentIdlePeriod = false
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reportedCurrentIdlePeriod = false
    }

    private func checkIdleState() {
        guard secondsSinceUserInput >= threshold else {
            reportedCurrentIdlePeriod = false
            return
        }
        guard !reportedCurrentIdlePeriod else { return }
        reportedCurrentIdlePeriod = true
        onIdleThresholdReached?()
    }
}
