// AppTimer focus service: owns focus block state and distraction classification.
import Foundation
import Observation

@MainActor
@Observable
final class FocusService {
    var activePreset: FocusSessionPreset?
    var startedAt: Date?
    var endsAt: Date?
    var lastCompletedAt: Date?
    private(set) var distractingApplication: ActiveApplicationInfo?
    private(set) var distractingApplicationStartedAt: Date?
    private(set) var lastDistractionReminderAt: Date?

    var hasActiveSession: Bool { activePreset != nil && endsAt != nil }

    func start(_ preset: FocusSessionPreset, at now: Date) {
        activePreset = preset
        startedAt = now
        endsAt = now.addingTimeInterval(TimeInterval(preset.minutes * 60))
        lastCompletedAt = nil
    }

    func cancel() {
        activePreset = nil
        startedAt = nil
        endsAt = nil
    }

    func remaining(at now: Date) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    func progress(at now: Date) -> Double {
        guard let activePreset, let startedAt else { return 0 }
        let duration = TimeInterval(activePreset.minutes * 60)
        return min(1, max(0, now.timeIntervalSince(startedAt) / duration))
    }

    func pulseState(isTracking: Bool, at now: Date) -> FocusPulseState {
        if distractingApplication != nil { return .distracted }
        if hasActiveSession { return .focused }
        if let lastCompletedAt, now.timeIntervalSince(lastCompletedAt) < 20 { return .completed }
        return isTracking ? .tracking : .resting
    }

    func updateDistraction(
        application: ActiveApplicationInfo?,
        focusEnabled: Bool,
        isTracking: Bool,
        isDistracting: (String) -> Bool,
        at date: Date
    ) {
        guard focusEnabled,
              isTracking,
              let application,
              application.bundleIdentifier != Bundle.main.bundleIdentifier,
              isDistracting(application.bundleIdentifier) else {
            resetDistraction()
            return
        }
        if distractingApplication?.bundleIdentifier != application.bundleIdentifier {
            distractingApplication = application
            distractingApplicationStartedAt = date
            lastDistractionReminderAt = nil
        }
    }

    func shouldSendDistractionReminder(after minutes: Int, cooldownMinutes: Int, now: Date) -> ActiveApplicationInfo? {
        guard let application = distractingApplication,
              let startedAt = distractingApplicationStartedAt,
              now.timeIntervalSince(startedAt) >= TimeInterval(minutes * 60),
              lastDistractionReminderAt == nil || now.timeIntervalSince(lastDistractionReminderAt!) >= TimeInterval(cooldownMinutes * 60) else {
            return nil
        }
        lastDistractionReminderAt = now
        return application
    }

    func completeIfNeeded(at now: Date) -> FocusSessionPreset? {
        guard let activePreset, let endsAt, now >= endsAt else { return nil }
        cancel()
        lastCompletedAt = now
        return activePreset
    }

    func resetDistraction() {
        distractingApplication = nil
        distractingApplicationStartedAt = nil
        lastDistractionReminderAt = nil
    }
}
