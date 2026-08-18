// AppTimer reminder service: centralizes reminder eligibility and cooldown state without retaining user content.
import Foundation

@MainActor
final class ReminderService {
    private var unassignedActivityStartedAt: Date?
    private var lastUnassignedReminderAt: Date?

    func shouldSendUnassignedReminder(
        enabled: Bool,
        isTracking: Bool,
        hasSelectedProjects: Bool,
        secondsSinceUserInput: TimeInterval,
        thresholdMinutes: Int,
        now: Date
    ) -> Bool {
        guard enabled, !isTracking, !hasSelectedProjects, secondsSinceUserInput < 90 else {
            resetUnassignedReminder()
            return false
        }
        if unassignedActivityStartedAt == nil { unassignedActivityStartedAt = now }
        guard let startedAt = unassignedActivityStartedAt,
              now.timeIntervalSince(startedAt) >= TimeInterval(thresholdMinutes * 60),
              lastUnassignedReminderAt == nil || now.timeIntervalSince(lastUnassignedReminderAt!) >= TimeInterval(thresholdMinutes * 60) else {
            return false
        }
        lastUnassignedReminderAt = now
        return true
    }

    func resetUnassignedReminder() {
        unassignedActivityStartedAt = nil
        lastUnassignedReminderAt = nil
    }
}
