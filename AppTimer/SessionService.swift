// AppTimer session service: owns session lifecycle operations against a supplied local SwiftData context.
import Foundation
import SwiftData

enum RetroSessionConflictResolution: String, CaseIterable, Identifiable {
    case trimExisting
    case replaceExisting

    var id: String { rawValue }
}

@MainActor
final class SessionService {
    private static let interruptionGraceInterval: TimeInterval = 120

    func createProject(named name: String, existingCount: Int, in context: ModelContext) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let palette = ["397CFF", "8B5CF6", "10B981", "F59E0B", "EF4444", "06B6D4"]
        let project = Project(name: trimmed, colorHex: palette[existingCount % palette.count])
        context.insert(project)
        return project
    }

    func start(
        projects: [Project],
        allocationMode: AllocationMode,
        customWeights: [UUID: Double],
        in context: ModelContext
    ) -> WorkSession? {
        guard !projects.isEmpty else { return nil }
        let session = WorkSession(allocationMode: allocationMode)
        let weights = AllocationEngine.weights(for: projects, mode: allocationMode, customWeights: customWeights)
        context.insert(session)
        for project in projects {
            let allocation = SessionProjectAllocation(project: project, session: session, weight: weights[project.id] ?? 0)
            session.allocations.append(allocation)
            context.insert(allocation)
        }
        return session
    }

    func overlappingCompletedSessions(_ sessions: [WorkSession], start: Date, end: Date) -> [WorkSession] {
        sessions.filter { session in
            guard let sessionEnd = session.endedAt else { return false }
            return sessionEnd > start && session.startedAt < end
        }
    }

    func createRetroSession(
        start: Date,
        end: Date,
        projects: [Project],
        allocationMode: AllocationMode,
        customWeights: [UUID: Double],
        existingSessions: [WorkSession],
        resolution: RetroSessionConflictResolution?,
        in context: ModelContext
    ) -> WorkSession? {
        guard end > start, !projects.isEmpty else { return nil }
        let conflicts = overlappingCompletedSessions(existingSessions, start: start, end: end)
        if !conflicts.isEmpty {
            guard let resolution else { return nil }
            switch resolution {
            case .replaceExisting:
                conflicts.forEach(context.delete)
            case .trimExisting:
                conflicts.forEach { trim($0, excluding: DateInterval(start: start, end: end), in: context) }
            }
        }

        let session = WorkSession(startedAt: start, allocationMode: allocationMode)
        session.endedAt = end
        context.insert(session)
        let weights = AllocationEngine.weights(for: projects, mode: allocationMode, customWeights: customWeights)
        for project in projects {
            let allocation = SessionProjectAllocation(project: project, session: session, weight: weights[project.id] ?? 0)
            session.allocations.append(allocation)
            context.insert(allocation)
        }
        return session
    }

    func beginApplicationSegment(
        for session: WorkSession,
        application: ActiveApplicationInfo?,
        at date: Date,
        in context: ModelContext
    ) -> AppSegment? {
        guard let application,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let segment = AppSegment(
            bundleIdentifier: application.bundleIdentifier,
            appName: application.name,
            session: session,
            startedAt: date
        )
        session.appSegments.append(segment)
        context.insert(segment)
        return segment
    }

    func close(session: WorkSession, activeSegment: AppSegment?, at date: Date) {
        activeSegment?.endedAt = date
        session.appSegments
            .filter { $0.endedAt == nil }
            .forEach { $0.endedAt = max($0.startedAt, date) }
        session.endedAt = max(session.startedAt, date)
    }

    func recoverInterruptedSessions(
        _ sessions: [WorkSession],
        heartbeat: (sessionID: UUID, date: Date)?,
        now: Date
    ) -> [RecoveredSessionNotice] {
        sessions.compactMap { session in
            guard session.endedAt == nil else { return nil }
            var candidates = [session.startedAt]
            candidates.append(contentsOf: session.appSegments.map { $0.endedAt ?? $0.startedAt })
            if heartbeat?.sessionID == session.id, let heartbeatDate = heartbeat?.date {
                candidates.append(heartbeatDate)
            }
            let lastActivity = min(now, candidates.max() ?? session.startedAt)
            guard now.timeIntervalSince(lastActivity) > Self.interruptionGraceInterval else { return nil }
            let recoveryDate = min(now, max(session.startedAt, lastActivity))
            close(session: session, activeSegment: nil, at: recoveryDate)
            let projectNames = session.allocations.compactMap { $0.project?.name }.joined(separator: ", ")
            return RecoveredSessionNotice(
                sessionID: session.id,
                closedAt: recoveryDate,
                projectNames: projectNames.isEmpty ? L10n.text("status.no_project") : projectNames
            )
        }
    }

    private func trim(_ session: WorkSession, excluding interval: DateInterval, in context: ModelContext) {
        guard let sessionEnd = session.endedAt else { return }
        let ranges = remainingRanges(of: DateInterval(start: session.startedAt, end: sessionEnd), excluding: interval)
        let originalAllocations = session.allocations
        let originalSegments = session.appSegments

        guard let firstRange = ranges.first else {
            context.delete(session)
            return
        }

        rewrite(session, to: firstRange, originalSegments: originalSegments, in: context)
        if ranges.count > 1, let secondRange = ranges.last {
            let duplicate = WorkSession(startedAt: secondRange.start, allocationMode: session.allocationMode)
            duplicate.endedAt = secondRange.end
            duplicate.note = session.note
            context.insert(duplicate)
            for allocation in originalAllocations {
                guard let project = allocation.project else { continue }
                let copied = SessionProjectAllocation(project: project, session: duplicate, weight: allocation.weight)
                duplicate.allocations.append(copied)
                context.insert(copied)
            }
            copySegments(originalSegments, to: duplicate, range: secondRange, in: context)
        }
    }

    private func remainingRanges(of source: DateInterval, excluding interval: DateInterval) -> [DateInterval] {
        guard source.intersects(interval) else { return [source] }
        var ranges: [DateInterval] = []
        if source.start < interval.start {
            ranges.append(DateInterval(start: source.start, end: min(source.end, interval.start)))
        }
        if source.end > interval.end {
            ranges.append(DateInterval(start: max(source.start, interval.end), end: source.end))
        }
        return ranges.filter { $0.duration > 0 }
    }

    private func rewrite(_ session: WorkSession, to range: DateInterval, originalSegments: [AppSegment], in context: ModelContext) {
        session.startedAt = range.start
        session.endedAt = range.end
        session.appSegments = []
        originalSegments.forEach(context.delete)
        copySegments(originalSegments, to: session, range: range, in: context)
    }

    private func copySegments(_ segments: [AppSegment], to session: WorkSession, range: DateInterval, in context: ModelContext) {
        for segment in segments {
            let segmentEnd = segment.endedAt ?? range.end
            guard segmentEnd > range.start, segment.startedAt < range.end else { continue }
            let copy = AppSegment(
                bundleIdentifier: segment.bundleIdentifier,
                appName: segment.appName,
                session: session,
                startedAt: max(segment.startedAt, range.start)
            )
            copy.endedAt = min(segmentEnd, range.end)
            session.appSegments.append(copy)
            context.insert(copy)
        }
    }
}
