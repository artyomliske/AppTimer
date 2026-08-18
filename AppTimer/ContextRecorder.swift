// AppTimer context recorder: opt-in, local-only application metadata with bounded retention.
import Foundation
import SwiftData

@MainActor
final class ContextRecorder {
    private var activeSegment: ContextSegment?
    private var lastHeartbeatAt: Date?

    func restoreOpenSegments(_ segments: [ContextSegment], settings: AppTimerSettings, now: Date) -> Bool {
        let heartbeat = settings.contextHeartbeat()
        var didRecover = false
        for segment in segments where segment.endedAt == nil {
            let recoveryDate: Date
            if heartbeat?.segmentID == segment.id, let heartbeatDate = heartbeat?.date {
                recoveryDate = min(now, max(segment.startedAt, heartbeatDate))
            } else {
                recoveryDate = segment.startedAt
            }
            segment.endedAt = recoveryDate
            didRecover = true
        }
        if didRecover { settings.clearContextHeartbeat() }
        return didRecover
    }

    @discardableResult
    func record(
        application: ActiveApplicationInfo?,
        enabled: Bool,
        settings: AppTimerSettings,
        context: ModelContext,
        at date: Date
    ) -> Bool {
        guard enabled,
              let application,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return close(settings: settings, at: date)
        }
        if activeSegment?.bundleIdentifier == application.bundleIdentifier { return false }

        let didClose = close(settings: settings, at: date)
        let segment = ContextSegment(
            bundleIdentifier: application.bundleIdentifier,
            appName: application.name,
            startedAt: date
        )
        context.insert(segment)
        activeSegment = segment
        settings.writeContextHeartbeat(segmentID: segment.id, at: date)
        lastHeartbeatAt = date
        return didClose || true
    }

    @discardableResult
    func close(settings: AppTimerSettings, at date: Date) -> Bool {
        guard let activeSegment else { return false }
        activeSegment.endedAt = max(activeSegment.startedAt, date)
        settings.clearContextHeartbeat(for: activeSegment.id)
        self.activeSegment = nil
        lastHeartbeatAt = nil
        return true
    }

    func updateHeartbeat(settings: AppTimerSettings, at date: Date) {
        guard let activeSegment,
              lastHeartbeatAt == nil || date.timeIntervalSince(lastHeartbeatAt!) >= 30 else { return }
        settings.writeContextHeartbeat(segmentID: activeSegment.id, at: date)
        lastHeartbeatAt = date
    }

    @discardableResult
    func purgeExpiredSegments(_ segments: [ContextSegment], retention: ContextHistoryRetention, in context: ModelContext, now: Date) -> Bool {
        guard let days = retention.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return false }
        let expired = segments.filter { ($0.endedAt ?? $0.startedAt) < cutoff && $0 !== activeSegment }
        expired.forEach(context.delete)
        return !expired.isEmpty
    }

    @discardableResult
    func deleteAllSegments(_ segments: [ContextSegment], settings: AppTimerSettings, in context: ModelContext, at date: Date) -> Bool {
        _ = close(settings: settings, at: date)
        guard !segments.isEmpty else { return false }
        segments.forEach(context.delete)
        return true
    }
}
