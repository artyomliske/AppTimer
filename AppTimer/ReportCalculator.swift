// AppTimer reporting: computes actual and allocated durations from immutable local intervals.
import Foundation

enum ReportCalculator {
    static func sessions(in interval: DateInterval, from sessions: [WorkSession], now: Date = .now) -> [WorkSession] {
        sessions.filter { session in
            let sessionEnd = session.endedAt ?? now
            return sessionEnd > interval.start && session.startedAt < interval.end
        }
    }

    static func actualDuration(of session: WorkSession, clippedTo interval: DateInterval? = nil, now: Date = .now) -> TimeInterval {
        let start = session.startedAt
        let end = session.endedAt ?? now
        guard let interval else { return max(0, end.timeIntervalSince(start)) }
        let clippedStart = max(start, interval.start)
        let clippedEnd = min(end, interval.end)
        return max(0, clippedEnd.timeIntervalSince(clippedStart))
    }

    static func projectDurations(for sessions: [WorkSession], interval: DateInterval, now: Date = .now) -> [ProjectDuration] {
        var actualByProject: [UUID: TimeInterval] = [:]
        var allocatedByProject: [UUID: TimeInterval] = [:]
        var projects: [UUID: Project] = [:]

        Self.sessions(in: interval, from: sessions, now: now).forEach { session in
            let duration = actualDuration(of: session, clippedTo: interval, now: now)
            session.allocations.forEach { allocation in
                guard let project = allocation.project else { return }
                projects[project.id] = project
                actualByProject[project.id, default: 0] += duration
                allocatedByProject[project.id, default: 0] += duration * allocation.weight
            }
        }

        return projects.values.map { project in
            ProjectDuration(
                id: project.id,
                name: project.name,
                colorHex: project.colorHex,
                actual: actualByProject[project.id, default: 0],
                allocated: allocatedByProject[project.id, default: 0]
            )
        }.sorted { $0.allocated > $1.allocated }
    }

    static func applicationDurations(for sessions: [WorkSession], interval: DateInterval, now: Date = .now) -> [ApplicationDuration] {
        var summary: [String: (String, TimeInterval)] = [:]
        Self.sessions(in: interval, from: sessions, now: now).forEach { session in
            session.appSegments.forEach { segment in
                let start = max(segment.startedAt, interval.start)
                let end = min(segment.endedAt ?? now, interval.end)
                let duration = max(0, end.timeIntervalSince(start))
                summary[segment.bundleIdentifier, default: (segment.appName, 0)].1 += duration
            }
        }
        return summary.map { identifier, value in
            ApplicationDuration(id: identifier, name: value.0, duration: value.1)
        }.sorted { $0.duration > $1.duration }
    }
}
