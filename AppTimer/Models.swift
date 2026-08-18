// AppTimer domain model: local-first time tracking with explicit project allocation and focus sessions.
import Foundation
import SwiftData

enum AllocationMode: String, CaseIterable, Codable, Identifiable {
    case equal
    case fullToEach
    case customWeights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equal: L10n.text("allocation.equal")
        case .fullToEach: L10n.text("allocation.full")
        case .customWeights: L10n.text("allocation.custom")
        }
    }

    var detail: String {
        switch self {
        case .equal: L10n.text("allocation.equal.detail")
        case .fullToEach: L10n.text("allocation.full.detail")
        case .customWeights: L10n.text("allocation.custom.detail")
        }
    }
}

enum FocusApplicationRole: String, CaseIterable, Codable, Identifiable {
    case work
    case neutral
    case distracting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: L10n.text("role.work")
        case .neutral: L10n.text("role.neutral")
        case .distracting: L10n.text("role.distracting")
        }
    }

    var detail: String {
        switch self {
        case .work: L10n.text("role.work.detail")
        case .neutral: L10n.text("role.neutral.detail")
        case .distracting: L10n.text("role.distracting.detail")
        }
    }
}

enum FocusSessionPreset: Int, CaseIterable, Identifiable {
    case short = 25
    case standard = 50
    case deep = 90

    var id: Int { rawValue }
    var minutes: Int { rawValue }
    var title: String { L10n.format("duration.minutes.format", rawValue) }

    var detail: String {
        switch self {
        case .short: L10n.text("focus.short.detail")
        case .standard: L10n.text("focus.standard.detail")
        case .deep: L10n.text("focus.deep.detail")
        }
    }
}

enum FocusPulseState: String {
    case resting
    case tracking
    case focused
    case distracted
    case completed

    var title: String {
        switch self {
        case .resting: L10n.text("pulse.resting")
        case .tracking: L10n.text("pulse.tracking")
        case .focused: L10n.text("pulse.focused")
        case .distracted: L10n.text("pulse.distracted")
        case .completed: L10n.text("pulse.completed")
        }
    }

    var symbolName: String {
        switch self {
        case .resting: "circle.dashed"
        case .tracking: "timer"
        case .focused: "scope"
        case .distracted: "exclamationmark.circle.fill"
        case .completed: "checkmark.circle.fill"
        }
    }
}

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date
    var isArchived: Bool
    var clientName: String?
    var hourlyRate: Double?
    var weeklyGoalMinutes: Int?

    init(name: String, colorHex: String = "397CFF") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.createdAt = Date()
        self.isArchived = false
        self.clientName = nil
        self.hourlyRate = nil
        self.weeklyGoalMinutes = nil
    }
}

@Model
final class WorkSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var allocationModeRaw: String
    var note: String?
    @Relationship(deleteRule: .cascade) var allocations: [SessionProjectAllocation]
    @Relationship(deleteRule: .cascade) var appSegments: [AppSegment]

    init(startedAt: Date = .now, allocationMode: AllocationMode) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = nil
        self.allocationModeRaw = allocationMode.rawValue
        self.note = nil
        self.allocations = []
        self.appSegments = []
    }

    var allocationMode: AllocationMode {
        get { AllocationMode(rawValue: allocationModeRaw) ?? .equal }
        set { allocationModeRaw = newValue.rawValue }
    }

    func duration(until now: Date = .now) -> TimeInterval {
        (endedAt ?? now).timeIntervalSince(startedAt)
    }
}

@Model
final class SessionProjectAllocation {
    @Attribute(.unique) var id: UUID
    var weight: Double
    var project: Project?
    var session: WorkSession?

    init(project: Project, session: WorkSession, weight: Double) {
        self.id = UUID()
        self.project = project
        self.session = session
        self.weight = weight
    }
}

@Model
final class AppSegment {
    @Attribute(.unique) var id: UUID
    var bundleIdentifier: String
    var appName: String
    var startedAt: Date
    var endedAt: Date?
    var session: WorkSession?

    init(bundleIdentifier: String, appName: String, session: WorkSession, startedAt: Date = .now) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.startedAt = startedAt
        self.endedAt = nil
        self.session = session
    }

    func duration(until now: Date = .now) -> TimeInterval {
        (endedAt ?? now).timeIntervalSince(startedAt)
    }
}

// Passive local application context. It intentionally has no relationship to WorkSession:
// manual sessions are an optional annotation layer over this continuous timeline.
@Model
final class ContextSegment {
    @Attribute(.unique) var id: UUID
    var bundleIdentifier: String
    var appName: String
    var startedAt: Date
    var endedAt: Date?

    init(bundleIdentifier: String, appName: String, startedAt: Date = .now) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.startedAt = startedAt
        self.endedAt = nil
    }

    func duration(until now: Date = .now) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }
}

struct ProjectDuration: Identifiable {
    let id: UUID
    let name: String
    let colorHex: String
    let actual: TimeInterval
    let allocated: TimeInterval
}

struct ApplicationDuration: Identifiable {
    let id: String
    let name: String
    let duration: TimeInterval
}

struct FocusApplication: Identifiable {
    let bundleIdentifier: String
    let name: String
    let role: FocusApplicationRole

    var id: String { bundleIdentifier }
}

struct FocusDurationSummary {
    let work: TimeInterval
    let distracting: TimeInterval
    let neutral: TimeInterval

    var observed: TimeInterval { work + distracting + neutral }
}

struct FocusDaySummary: Identifiable {
    let date: Date
    let work: TimeInterval
    let distracting: TimeInterval

    var id: Date { date }
}

struct RecoveredSessionNotice: Identifiable {
    let sessionID: UUID
    let closedAt: Date
    let projectNames: String

    var id: UUID { sessionID }
}

extension TimeInterval {
    var appTimerText: String {
        let hours = Int(self) / 3_600
        let minutes = (Int(self) % 3_600) / 60
        return hours > 0 ? L10n.format("duration.hours_minutes.format", hours, minutes) : L10n.format("duration.minutes.format", minutes)
    }

    var appTimerCompactText: String {
        let hours = Int(self) / 3_600
        let minutes = (Int(self) % 3_600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}
