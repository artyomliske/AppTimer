// AppTimer session service: owns session lifecycle operations against a supplied local SwiftData context.
import Foundation
import SwiftData

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
}
