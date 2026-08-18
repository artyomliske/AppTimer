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
        case .equal: "Поровну"
        case .fullToEach: "Полностью каждому"
        case .customWeights: "Ручные доли"
        }
    }

    var detail: String {
        switch self {
        case .equal: "Время делится между выбранными проектами."
        case .fullToEach: "Каждый проект получает полную длительность интервала."
        case .customWeights: "Распределите время вручную в процентах."
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
        case .work: "Рабочее"
        case .neutral: "Нейтральное"
        case .distracting: "Отвлекающее"
        }
    }

    var detail: String {
        switch self {
        case .work: "Учитывается как контекст концентрации."
        case .neutral: "Сохраняется в отчёте, но не вызывает напоминаний."
        case .distracting: "Может вызвать напоминание во время активного учёта."
        }
    }
}

enum FocusSessionPreset: Int, CaseIterable, Identifiable {
    case short = 25
    case standard = 50
    case deep = 90

    var id: Int { rawValue }
    var minutes: Int { rawValue }
    var title: String { "\(rawValue) мин" }

    var detail: String {
        switch self {
        case .short: "Короткий разгон для одной задачи."
        case .standard: "Обычный блок глубокой работы."
        case .deep: "Длинный блок без переключений."
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
        case .resting: "Покой"
        case .tracking: "Учёт идёт"
        case .focused: "Фокус"
        case .distracted: "Отвлечение"
        case .completed: "Блок завершён"
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
        return hours > 0 ? String(format: "%d ч %02d мин", hours, minutes) : String(format: "%d мин", minutes)
    }

    var appTimerCompactText: String {
        let hours = Int(self) / 3_600
        let minutes = (Int(self) % 3_600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}
