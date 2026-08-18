import Foundation
import SwiftData
import XCTest

@MainActor
class AppTimerModelTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    private let preferenceKeys = [
        "defaultAllocationMode", "excludedBundleIdentifiers", "idlePauseEnabled", "idlePauseMinutes",
        "unassignedReminderEnabled", "unassignedReminderMinutes", "focusModeEnabled", "distractionAlertMinutes",
        "distractionReminderCooldownMinutes", "focusWorkBundleIdentifiers", "focusDistractingBundleIdentifiers",
        "focusApplicationNames", "recentProjectIDs", "activeSessionHeartbeatID", "activeSessionHeartbeatDate",
        "passiveContextRecordingEnabled", "contextRetentionDays", "contextHeartbeatSegmentID", "contextHeartbeatDate"
    ]

    override func setUpWithError() throws {
        resetPreferences()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Project.self,
            WorkSession.self,
            SessionProjectAllocation.self,
            AppSegment.self,
            ContextSegment.self,
            configurations: configuration
        )
        modelContext = modelContainer.mainContext
    }

    override func tearDownWithError() throws {
        resetPreferences()
        modelContext = nil
        modelContainer = nil
    }

    func makeProject(named name: String) -> Project {
        let project = Project(name: name)
        modelContext.insert(project)
        return project
    }

    func makeSession(start: Date, end: Date?, mode: AllocationMode = .equal) -> WorkSession {
        let session = WorkSession(startedAt: start, allocationMode: mode)
        session.endedAt = end
        modelContext.insert(session)
        return session
    }

    func makeAllocation(project: Project, session: WorkSession, weight: Double) -> SessionProjectAllocation {
        let allocation = SessionProjectAllocation(project: project, session: session, weight: weight)
        session.allocations.append(allocation)
        modelContext.insert(allocation)
        return allocation
    }

    func makeSegment(bundleIdentifier: String, appName: String, session: WorkSession, startedAt: Date, endedAt: Date?) -> AppSegment {
        let segment = AppSegment(bundleIdentifier: bundleIdentifier, appName: appName, session: session, startedAt: startedAt)
        segment.endedAt = endedAt
        modelContext.insert(segment)
        return segment
    }

    func makeStore() -> AppTimerStore {
        UserDefaults.standard.set(false, forKey: "idlePauseEnabled")
        UserDefaults.standard.set(false, forKey: "unassignedReminderEnabled")
        UserDefaults.standard.set(false, forKey: "focusModeEnabled")
        let store = AppTimerStore()
        store.configure(with: modelContext)
        return store
    }

    private func resetPreferences() {
        preferenceKeys.forEach(UserDefaults.standard.removeObject(forKey:))
    }
}

final class AllocationEngineTests: AppTimerModelTests {
    func testEmptyProjectsProduceNoWeights() {
        XCTAssertEqual(AllocationEngine.weights(for: [], mode: .equal, customWeights: [:]), [:])
    }

    func testEqualAllocationSplitsWeightEvenly() {
        let projects = [makeProject(named: "A"), makeProject(named: "B"), makeProject(named: "C")]
        let weights = AllocationEngine.weights(for: projects, mode: .equal, customWeights: [:])

        XCTAssertEqual(weights.values.reduce(0, +), 1, accuracy: 0.000_001)
        projects.forEach { XCTAssertEqual(weights[$0.id] ?? 0, 1.0 / 3.0, accuracy: 0.000_001) }
    }

    func testEqualAllocationForSingleProjectIsFullWeight() {
        let project = makeProject(named: "A")
        XCTAssertEqual(AllocationEngine.weights(for: [project], mode: .equal, customWeights: [:])[project.id], 1)
    }

    func testFullToEachGivesEveryProjectFullWeight() {
        let projects = [makeProject(named: "A"), makeProject(named: "B")]
        let weights = AllocationEngine.weights(for: projects, mode: .fullToEach, customWeights: [:])

        XCTAssertEqual(weights[projects[0].id], 1)
        XCTAssertEqual(weights[projects[1].id], 1)
        XCTAssertEqual(weights.values.reduce(0, +), 2)
    }

    func testCustomWeightsNormalizeToOne() {
        let projects = [makeProject(named: "A"), makeProject(named: "B")]
        let weights = AllocationEngine.weights(
            for: projects,
            mode: .customWeights,
            customWeights: [projects[0].id: 2, projects[1].id: 6]
        )

        XCTAssertEqual(weights[projects[0].id] ?? 0, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(weights[projects[1].id] ?? 0, 0.75, accuracy: 0.000_001)
    }

    func testCustomWeightsTreatMissingWeightAsZero() {
        let projects = [makeProject(named: "A"), makeProject(named: "B")]
        let weights = AllocationEngine.weights(for: projects, mode: .customWeights, customWeights: [projects[0].id: 4])

        XCTAssertEqual(weights[projects[0].id], 1)
        XCTAssertEqual(weights[projects[1].id], 0)
    }

    func testCustomWeightsIgnoreUnselectedProject() {
        let projects = [makeProject(named: "A"), makeProject(named: "B")]
        let unrelated = UUID()
        let weights = AllocationEngine.weights(
            for: projects,
            mode: .customWeights,
            customWeights: [projects[0].id: 3, projects[1].id: 1, unrelated: 100]
        )

        XCTAssertEqual(weights[projects[0].id] ?? 0, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(weights[projects[1].id] ?? 0, 0.25, accuracy: 0.000_001)
        XCTAssertNil(weights[unrelated])
    }

    func testCustomDecimalWeightsRemainNormalized() {
        let projects = [makeProject(named: "A"), makeProject(named: "B"), makeProject(named: "C")]
        let weights = AllocationEngine.weights(
            for: projects,
            mode: .customWeights,
            customWeights: [projects[0].id: 0.1, projects[1].id: 0.2, projects[2].id: 0.7]
        )

        XCTAssertEqual(weights.values.reduce(0, +), 1, accuracy: 0.000_001)
        XCTAssertEqual(weights[projects[2].id] ?? 0, 0.7, accuracy: 0.000_001)
    }

    func testZeroCustomWeightsFallBackToEqualAllocation() {
        let projects = [makeProject(named: "A"), makeProject(named: "B")]
        let weights = AllocationEngine.weights(
            for: projects,
            mode: .customWeights,
            customWeights: [projects[0].id: 0, projects[1].id: -1]
        )

        XCTAssertEqual(weights[projects[0].id] ?? 0, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(weights[projects[1].id] ?? 0, 0.5, accuracy: 0.000_001)
    }

    func testPercentageRoundsCustomWeight() {
        let projects = [makeProject(named: "A"), makeProject(named: "B"), makeProject(named: "C")]
        let percentage = AllocationEngine.percentage(
            for: projects[0].id,
            in: projects,
            mode: .customWeights,
            customWeights: [projects[0].id: 1, projects[1].id: 1, projects[2].id: 1]
        )

        XCTAssertEqual(percentage, 33)
    }

    func testPercentageForUnknownProjectIsZero() {
        let project = makeProject(named: "A")
        XCTAssertEqual(AllocationEngine.percentage(for: UUID(), in: [project], mode: .equal, customWeights: [:]), 0)
    }
}

final class ReportCalculatorTests: AppTimerModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute))!
    }

    func testSessionInsideIntervalKeepsFullDuration() {
        let work = makeSession(start: date(4, 10), end: date(4, 11))
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))
        XCTAssertEqual(ReportCalculator.actualDuration(of: work, clippedTo: interval), 3_600)
    }

    func testSessionCrossingMidnightIsClippedToDay() {
        let work = makeSession(start: date(4, 23), end: date(5, 1))
        let interval = DateInterval(start: date(5, 0), end: date(6, 0))
        XCTAssertEqual(ReportCalculator.actualDuration(of: work, clippedTo: interval), 3_600)
    }

    func testOpenSessionUsesProvidedNow() {
        let work = makeSession(start: date(4, 10), end: nil)
        let now = date(4, 12, 30)
        XCTAssertEqual(ReportCalculator.actualDuration(of: work, now: now), 9_000)
    }

    func testNonOverlappingSessionIsExcluded() {
        let work = makeSession(start: date(1, 10), end: date(1, 11))
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))
        XCTAssertTrue(ReportCalculator.sessions(in: interval, from: [work]).isEmpty)
    }

    func testSessionEndingAtIntervalStartIsExcluded() {
        let work = makeSession(start: date(3, 23), end: date(4, 0))
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))
        XCTAssertTrue(ReportCalculator.sessions(in: interval, from: [work]).isEmpty)
    }

    func testSessionStartingAtIntervalEndIsExcluded() {
        let work = makeSession(start: date(5, 0), end: date(5, 1))
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))
        XCTAssertTrue(ReportCalculator.sessions(in: interval, from: [work]).isEmpty)
    }

    func testNegativeClosedSessionDurationIsZero() {
        let work = makeSession(start: date(4, 11), end: date(4, 10))
        XCTAssertEqual(ReportCalculator.actualDuration(of: work), 0)
    }

    func testProjectDurationsKeepActualAndAllocatedValues() {
        let first = makeProject(named: "A")
        let second = makeProject(named: "B")
        let session = makeSession(start: date(4, 10), end: date(4, 11))
        makeAllocation(project: first, session: session, weight: 0.25)
        makeAllocation(project: second, session: session, weight: 0.75)
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))
        let durations = ReportCalculator.projectDurations(for: [session], interval: interval)
        let firstDuration = durations.first { $0.id == first.id }
        let secondDuration = durations.first { $0.id == second.id }

        XCTAssertEqual(firstDuration?.actual, 3_600)
        XCTAssertEqual(firstDuration?.allocated, 900)
        XCTAssertEqual(secondDuration?.actual, 3_600)
        XCTAssertEqual(secondDuration?.allocated, 2_700)
    }

    func testProjectDurationsAreSortedByAllocatedDuration() {
        let first = makeProject(named: "A")
        let second = makeProject(named: "B")
        let session = makeSession(start: date(4, 10), end: date(4, 11))
        makeAllocation(project: first, session: session, weight: 0.2)
        makeAllocation(project: second, session: session, weight: 0.8)
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        XCTAssertEqual(ReportCalculator.projectDurations(for: [session], interval: interval).map(\.id), [second.id, first.id])
    }

    func testProjectDurationsIgnoreAllocationWithoutProject() {
        let project = makeProject(named: "A")
        let session = makeSession(start: date(4, 10), end: date(4, 11))
        let allocation = makeAllocation(project: project, session: session, weight: 1)
        allocation.project = nil
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        XCTAssertTrue(ReportCalculator.projectDurations(for: [session], interval: interval).isEmpty)
    }

    func testApplicationDurationsExcludeConfiguredBundleIdentifier() {
        let work = makeSession(start: date(4, 10), end: date(4, 11))
        let included = makeSegment(bundleIdentifier: "com.example.work", appName: "Work", session: work, startedAt: date(4, 10), endedAt: date(4, 10, 30))
        let excluded = makeSegment(bundleIdentifier: "com.example.chat", appName: "Chat", session: work, startedAt: date(4, 10, 30), endedAt: date(4, 11))
        work.appSegments = [included, excluded]
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        let durations = ReportCalculator.applicationDurations(
            for: [work],
            interval: interval,
            excludedBundleIdentifiers: ["com.example.chat"]
        )

        XCTAssertEqual(durations.count, 1)
        XCTAssertEqual(durations.first?.id, "com.example.work")
        XCTAssertEqual(durations.first?.duration ?? 0, 1_800)
    }

    func testApplicationDurationsMergeSegmentsForSameBundleIdentifier() {
        let work = makeSession(start: date(4, 10), end: date(4, 11))
        let first = makeSegment(bundleIdentifier: "com.example.editor", appName: "Editor", session: work, startedAt: date(4, 10), endedAt: date(4, 10, 15))
        let second = makeSegment(bundleIdentifier: "com.example.editor", appName: "Editor", session: work, startedAt: date(4, 10, 30), endedAt: date(4, 11))
        work.appSegments = [first, second]
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        XCTAssertEqual(ReportCalculator.applicationDurations(for: [work], interval: interval).first?.duration, 2_700)
    }

    func testApplicationDurationsClipSegmentsToInterval() {
        let work = makeSession(start: date(4, 8), end: date(4, 16))
        let segment = makeSegment(bundleIdentifier: "com.example.editor", appName: "Editor", session: work, startedAt: date(4, 9), endedAt: date(4, 15))
        work.appSegments = [segment]
        let interval = DateInterval(start: date(4, 10), end: date(4, 12))

        XCTAssertEqual(ReportCalculator.applicationDurations(for: [work], interval: interval).first?.duration, 7_200)
    }

    func testApplicationDurationsUseProvidedNowForOpenSegment() {
        let work = makeSession(start: date(4, 10), end: nil)
        let segment = makeSegment(bundleIdentifier: "com.example.editor", appName: "Editor", session: work, startedAt: date(4, 10), endedAt: nil)
        work.appSegments = [segment]
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        XCTAssertEqual(ReportCalculator.applicationDurations(for: [work], interval: interval, now: date(4, 10, 45)).first?.duration, 2_700)
    }

    func testPassiveContextIsClippedToManualSessionAndReportInterval() {
        let work = makeSession(start: date(4, 10), end: date(4, 11))
        let first = ContextSegment(bundleIdentifier: "com.example.editor", appName: "Editor", startedAt: date(4, 9, 30))
        first.endedAt = date(4, 10, 30)
        let second = ContextSegment(bundleIdentifier: "com.example.editor", appName: "Editor", startedAt: date(4, 10, 30))
        second.endedAt = date(4, 11, 30)
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        let durations = ReportCalculator.applicationDurations(for: [work], contextSegments: [first, second], interval: interval)
        XCTAssertEqual(durations.count, 1)
        XCTAssertEqual(durations.first?.id, "com.example.editor")
        XCTAssertEqual(durations.first?.duration, 3_600)
    }

    func testContextReportFallsBackToHistoricAppSegmentsWhenNoPassiveContextIntersects() {
        let work = makeSession(start: date(4, 10), end: date(4, 11))
        let historic = makeSegment(bundleIdentifier: "com.example.legacy", appName: "Legacy", session: work, startedAt: date(4, 10), endedAt: date(4, 11))
        work.appSegments = [historic]
        let unrelated = ContextSegment(bundleIdentifier: "com.example.other", appName: "Other", startedAt: date(4, 8))
        unrelated.endedAt = date(4, 9)
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        let durations = ReportCalculator.applicationDurations(for: [work], contextSegments: [unrelated], interval: interval)
        XCTAssertEqual(durations.first?.id, "com.example.legacy")
        XCTAssertEqual(durations.first?.duration, 3_600)
    }

    func testFocusDurationsSeparateWorkDistractionAndNeutralContext() {
        let work = makeSession(start: date(4, 10), end: date(4, 11))
        let editor = makeSegment(bundleIdentifier: "com.example.editor", appName: "Editor", session: work, startedAt: date(4, 10), endedAt: date(4, 10, 20))
        let chat = makeSegment(bundleIdentifier: "com.example.chat", appName: "Chat", session: work, startedAt: date(4, 10, 20), endedAt: date(4, 10, 45))
        let finder = makeSegment(bundleIdentifier: "com.apple.finder", appName: "Finder", session: work, startedAt: date(4, 10, 45), endedAt: date(4, 11))
        work.appSegments = [editor, chat, finder]
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        let result = ReportCalculator.focusDurations(
            for: [work],
            interval: interval,
            workBundleIdentifiers: ["com.example.editor"],
            distractingBundleIdentifiers: ["com.example.chat"]
        )

        XCTAssertEqual(result.work, 1_200)
        XCTAssertEqual(result.distracting, 1_500)
        XCTAssertEqual(result.neutral, 900)
    }

    func testFocusDurationsWithEmptyRolesAreNeutral() {
        let work = makeSession(start: date(4, 10), end: date(4, 11))
        let segment = makeSegment(bundleIdentifier: "com.example.editor", appName: "Editor", session: work, startedAt: date(4, 10), endedAt: date(4, 11))
        work.appSegments = [segment]
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        let result = ReportCalculator.focusDurations(for: [work], interval: interval, workBundleIdentifiers: [], distractingBundleIdentifiers: [])
        XCTAssertEqual(result.work, 0)
        XCTAssertEqual(result.distracting, 0)
        XCTAssertEqual(result.neutral, 3_600)
    }

    func testDistractingRoleTakesPriorityWhenRoleSetsOverlap() {
        let work = makeSession(start: date(4, 10), end: date(4, 11))
        let segment = makeSegment(bundleIdentifier: "com.example.chat", appName: "Chat", session: work, startedAt: date(4, 10), endedAt: date(4, 11))
        work.appSegments = [segment]
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        let result = ReportCalculator.focusDurations(
            for: [work],
            interval: interval,
            workBundleIdentifiers: ["com.example.chat"],
            distractingBundleIdentifiers: ["com.example.chat"]
        )

        XCTAssertEqual(result.work, 0)
        XCTAssertEqual(result.distracting, 3_600)
    }
}

final class AppTimerStoreTests: AppTimerModelTests {
    func testStartTrackingRequiresASelectedProject() {
        let store = makeStore()
        store.startTracking()

        XCTAssertFalse(store.isTracking)
        XCTAssertEqual(store.statusMessage, L10n.text("status.choose_at_least_one"))
    }

    func testStartAndStopTrackingCreateAndCloseSession() {
        let store = makeStore()
        store.createProject(named: "A")
        store.startTracking()

        XCTAssertTrue(store.isTracking)
        XCTAssertEqual(store.activeSession?.allocations.count, 1)
        store.stopTracking()

        XCTAssertFalse(store.isTracking)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertNotNil(store.sessions.first?.endedAt)
    }

    func testChangingProjectsDuringTrackingClosesAndRestartsSession() {
        let store = makeStore()
        store.createProject(named: "A")
        store.createProject(named: "B")
        guard let second = store.projects.first(where: { $0.name == "B" }) else {
            return XCTFail("Second project should be available")
        }
        store.toggleProject(second)
        store.startTracking()
        guard let firstSession = store.activeSession else {
            return XCTFail("Tracking session should start")
        }

        store.toggleProject(second)

        guard let restartedSession = store.activeSession else {
            return XCTFail("Tracking should restart")
        }
        XCTAssertTrue(store.isTracking)
        XCTAssertNotEqual(restartedSession.id, firstSession.id)
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertNotNil(store.sessions.first(where: { $0.id == firstSession.id })?.endedAt)
    }

    func testChangingAllocationModeDuringTrackingRestartsSession() {
        let store = makeStore()
        store.createProject(named: "A")
        store.startTracking()
        guard let firstSession = store.activeSession else {
            return XCTFail("Tracking session should start")
        }

        store.changeAllocationMode(to: AllocationMode.fullToEach)

        guard let restartedSession = store.activeSession else {
            return XCTFail("Tracking should restart")
        }
        XCTAssertEqual(restartedSession.allocationMode.rawValue, AllocationMode.fullToEach.rawValue)
        XCTAssertNotEqual(restartedSession.id, firstSession.id)
        XCTAssertEqual(store.sessions.count, 2)
    }

    func testUpdatingCustomWeightDuringTrackingRestartsSession() {
        let store = makeStore()
        store.createProject(named: "A")
        guard let project = store.projects.first else {
            return XCTFail("Project should be available")
        }
        store.changeAllocationMode(to: AllocationMode.customWeights)
        store.startTracking()
        guard let firstSession = store.activeSession else {
            return XCTFail("Tracking session should start")
        }

        store.updateCustomWeight(for: project, percent: 25)

        guard let restartedSession = store.activeSession else {
            return XCTFail("Tracking should restart")
        }
        XCTAssertNotEqual(restartedSession.id, firstSession.id)
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(restartedSession.allocationMode.rawValue, AllocationMode.customWeights.rawValue)
    }

    func testFocusSessionRequiresAProject() {
        let store = makeStore()
        store.startFocusSession(FocusSessionPreset.short)

        XCTAssertFalse(store.hasActiveFocusSession)
        XCTAssertEqual(store.statusMessage, L10n.text("status.choose_focus_project"))
    }

    func testArchivingAProjectClearsItsSelection() {
        let store = makeStore()
        store.createProject(named: "A")
        guard let project = store.projects.first else {
            return XCTFail("Project should be available")
        }
        store.archive(project)

        XCTAssertTrue(project.isArchived)
        XCTAssertTrue(store.selectedProjectIDs.isEmpty)
    }

    func testFocusRoleRoundTripUsesLocalSettings() {
        let store = makeStore()
        store.setFocusRole(FocusApplicationRole.work, for: "com.example.editor", name: "Editor")
        XCTAssertEqual(store.focusRole(for: "com.example.editor").rawValue, FocusApplicationRole.work.rawValue)

        store.setFocusRole(FocusApplicationRole.neutral, for: "com.example.editor")
        XCTAssertEqual(store.focusRole(for: "com.example.editor").rawValue, FocusApplicationRole.neutral.rawValue)
    }

    func testConfigureRecoversStaleOpenSession() {
        let session = makeSession(start: Date().addingTimeInterval(-600), end: nil)
        let store = makeStore()

        XCTAssertNotNil(store.sessions.first?.endedAt)
        XCTAssertEqual(store.recoveredSessionNotice?.sessionID, session.id)
    }
}

final class ModelUtilityTests: AppTimerModelTests {
    func testWorkSessionClosedDurationUsesEndDate() {
        let session = makeSession(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 160))
        XCTAssertEqual(session.duration(), 60)
    }

    func testWorkSessionOpenDurationUsesProvidedNow() {
        let session = makeSession(start: Date(timeIntervalSince1970: 100), end: nil)
        XCTAssertEqual(session.duration(until: Date(timeIntervalSince1970: 190)), 90)
    }

    func testCompactTimeIntervalFormattingUsesHoursAndMinutes() {
        XCTAssertEqual(TimeInterval(5_400).appTimerCompactText, "01:30")
    }

    func testLongTimeIntervalFormattingUsesCurrentLocalizedTemplate() {
        XCTAssertEqual(TimeInterval(5_400).appTimerText, L10n.format("duration.hours_minutes.format", 1, 30))
    }

    func testRussianLocalizationHasTrackingStatus() {
        XCTAssertEqual(L10n.text("status.choose_project", languageCode: "ru"), "Выберите проект, чтобы начать учёт")
    }

    func testEnglishLocalizationHasTrackingStatus() {
        XCTAssertEqual(L10n.text("status.choose_project", languageCode: "en"), "Choose a project to start tracking")
    }
}

@MainActor
final class AppTimerSettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        let suite = "AppTimerSettingsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaults.volatileDomainNames.first ?? "")
        defaults = nil
    }

    func testSettingsPreserveExistingAllocationModeKey() {
        defaults.set(AllocationMode.fullToEach.rawValue, forKey: "defaultAllocationMode")
        XCTAssertEqual(AppTimerSettings(defaults: defaults).defaultAllocationMode, .fullToEach)
    }

    func testSettingsSanitizeMinuteValuesAndPersistThem() {
        let settings = AppTimerSettings(defaults: defaults)
        settings.idlePauseMinutes = 0
        settings.distractionAlertMinutes = -3

        XCTAssertEqual(settings.idlePauseMinutes, 1)
        XCTAssertEqual(settings.distractionAlertMinutes, 1)
        XCTAssertEqual(defaults.object(forKey: "idlePauseMinutes") as? Int, 1)
        XCTAssertEqual(defaults.object(forKey: "distractionAlertMinutes") as? Int, 1)
    }

    func testSettingsRoundTripFocusRolesAndHeartbeat() {
        let settings = AppTimerSettings(defaults: defaults)
        settings.workBundleIdentifiers = ["com.example.editor"]
        settings.distractingBundleIdentifiers = ["com.example.chat"]
        let sessionID = UUID()
        let heartbeatDate = Date(timeIntervalSince1970: 1_000)
        settings.writeHeartbeat(sessionID: sessionID, at: heartbeatDate)

        XCTAssertEqual(AppTimerSettings(defaults: defaults).workBundleIdentifiers, ["com.example.editor"])
        XCTAssertEqual(AppTimerSettings(defaults: defaults).distractingBundleIdentifiers, ["com.example.chat"])
        XCTAssertEqual(AppTimerSettings(defaults: defaults).heartbeat()?.sessionID, sessionID)
        settings.clearHeartbeat(for: sessionID)
        XCTAssertNil(settings.heartbeat())
    }

    func testPassiveContextSettingsArePrivateByDefaultAndPersist() {
        let settings = AppTimerSettings(defaults: defaults)
        XCTAssertFalse(settings.passiveContextRecordingEnabled)
        XCTAssertEqual(settings.contextRetention, .days30)

        settings.passiveContextRecordingEnabled = true
        settings.contextRetention = .days7
        let restored = AppTimerSettings(defaults: defaults)
        XCTAssertTrue(restored.passiveContextRecordingEnabled)
        XCTAssertEqual(restored.contextRetention, .days7)
    }
}

final class SessionServiceTests: AppTimerModelTests {
    func testSessionServiceCreatesAllocationsAndClosesSession() {
        let project = makeProject(named: "Project")
        let service = SessionService()
        let session = service.start(projects: [project], allocationMode: .equal, customWeights: [:], in: modelContext)
        let startedSession = try! XCTUnwrap(session)
        let closedAt = startedSession.startedAt.addingTimeInterval(60)

        XCTAssertEqual(session?.allocations.count, 1)
        service.close(session: startedSession, activeSegment: nil, at: closedAt)
        XCTAssertEqual(session?.endedAt, closedAt)
    }

    func testSessionServiceRecoversOnlyStaleOpenSession() {
        let oldSession = makeSession(start: Date(timeIntervalSince1970: 0), end: nil)
        let currentSession = makeSession(start: Date(timeIntervalSince1970: 990), end: nil)
        let notices = SessionService().recoverInterruptedSessions([oldSession, currentSession], heartbeat: nil, now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(notices.map(\.sessionID), [oldSession.id])
        XCTAssertNotNil(oldSession.endedAt)
        XCTAssertNil(currentSession.endedAt)
    }

    func testRetroSessionTrimSplitsExistingSessionWithoutOverlap() throws {
        let project = makeProject(named: "Project")
        let original = makeSession(start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 1_720))
        makeAllocation(project: project, session: original, weight: 1)
        let service = SessionService()

        let retro = service.createRetroSession(
            start: Date(timeIntervalSince1970: 1_180),
            end: Date(timeIntervalSince1970: 1_540),
            projects: [project],
            allocationMode: .equal,
            customWeights: [:],
            existingSessions: [original],
            resolution: .trimExisting,
            in: modelContext
        )

        XCTAssertNotNil(retro)
        let sessions = try modelContext.fetch(FetchDescriptor<WorkSession>(sortBy: [SortDescriptor(\WorkSession.startedAt)]))
        XCTAssertEqual(sessions.count, 3)
        XCTAssertFalse(sessions.contains { $0.id != retro?.id && ($0.endedAt ?? .distantFuture) > retro!.startedAt && $0.startedAt < retro!.endedAt! })
    }

    func testRetroSessionReplaceDeletesConflictingSession() throws {
        let project = makeProject(named: "Project")
        let original = makeSession(start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 1_720))
        let service = SessionService()

        let retro = service.createRetroSession(
            start: Date(timeIntervalSince1970: 1_180),
            end: Date(timeIntervalSince1970: 1_540),
            projects: [project],
            allocationMode: .equal,
            customWeights: [:],
            existingSessions: [original],
            resolution: .replaceExisting,
            in: modelContext
        )

        XCTAssertNotNil(retro)
        let sessions = try modelContext.fetch(FetchDescriptor<WorkSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, retro?.id)
    }
}

final class ContextRecorderTests: AppTimerModelTests {
    func testRecorderWritesOnlyWhenExplicitlyEnabledAndClosesOnApplicationChange() throws {
        let recorder = ContextRecorder()
        let settings = AppTimerSettings()
        let start = Date(timeIntervalSince1970: 1_000)
        let editor = ActiveApplicationInfo(bundleIdentifier: "com.example.editor", name: "Editor")
        let chat = ActiveApplicationInfo(bundleIdentifier: "com.example.chat", name: "Chat")

        XCTAssertFalse(recorder.record(application: editor, enabled: false, settings: settings, context: modelContext, at: start))
        XCTAssertTrue(recorder.record(application: editor, enabled: true, settings: settings, context: modelContext, at: start))
        XCTAssertTrue(recorder.record(application: chat, enabled: true, settings: settings, context: modelContext, at: start.addingTimeInterval(120)))

        let segments = try modelContext.fetch(FetchDescriptor<ContextSegment>(sortBy: [SortDescriptor(\ContextSegment.startedAt)]))
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].bundleIdentifier, editor.bundleIdentifier)
        XCTAssertEqual(segments[0].endedAt, start.addingTimeInterval(120))
        XCTAssertEqual(segments[1].bundleIdentifier, chat.bundleIdentifier)
        XCTAssertNil(segments[1].endedAt)
    }

    func testRecorderPurgesOnlyExpiredClosedSegments() throws {
        let recorder = ContextRecorder()
        let settings = AppTimerSettings()
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let old = ContextSegment(bundleIdentifier: "com.example.old", appName: "Old", startedAt: now.addingTimeInterval(-40 * 86_400))
        old.endedAt = now.addingTimeInterval(-39 * 86_400)
        let recent = ContextSegment(bundleIdentifier: "com.example.recent", appName: "Recent", startedAt: now.addingTimeInterval(-2 * 86_400))
        recent.endedAt = now.addingTimeInterval(-1 * 86_400)
        modelContext.insert(old)
        modelContext.insert(recent)

        XCTAssertTrue(recorder.purgeExpiredSegments([old, recent], retention: .days30, in: modelContext, now: now))
        let remaining = try modelContext.fetch(FetchDescriptor<ContextSegment>())
        XCTAssertEqual(remaining.map(\.bundleIdentifier), ["com.example.recent"])
        _ = recorder.close(settings: settings, at: now)
    }
}

@MainActor
final class FocusAndReminderServiceTests: XCTestCase {
    func testFocusServiceTransitionsFromFocusedToCompleted() {
        let service = FocusService()
        let start = Date(timeIntervalSince1970: 1_000)
        service.start(.short, at: start)

        XCTAssertEqual(service.remaining(at: start), 1_500)
        XCTAssertEqual(service.pulseState(isTracking: true, at: start), .focused)
        XCTAssertEqual(service.completeIfNeeded(at: start.addingTimeInterval(1_500)), .short)
        XCTAssertEqual(service.pulseState(isTracking: false, at: start.addingTimeInterval(1_501)), .completed)
    }

    func testFocusServiceHonorsDistractionCooldown() {
        let service = FocusService()
        let start = Date(timeIntervalSince1970: 1_000)
        let application = ActiveApplicationInfo(bundleIdentifier: "com.example.chat", name: "Chat")
        service.updateDistraction(application: application, focusEnabled: true, isTracking: true, isDistracting: { $0 == application.bundleIdentifier }, at: start)

        XCTAssertNil(service.shouldSendDistractionReminder(after: 5, cooldownMinutes: 15, now: start.addingTimeInterval(299)))
        XCTAssertEqual(service.shouldSendDistractionReminder(after: 5, cooldownMinutes: 15, now: start.addingTimeInterval(300)), application)
        XCTAssertNil(service.shouldSendDistractionReminder(after: 5, cooldownMinutes: 15, now: start.addingTimeInterval(301)))
    }

    func testReminderServiceRequiresSustainedUnassignedActivity() {
        let service = ReminderService()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(service.shouldSendUnassignedReminder(enabled: true, isTracking: false, hasSelectedProjects: false, secondsSinceUserInput: 5, thresholdMinutes: 15, now: start))
        XCTAssertTrue(service.shouldSendUnassignedReminder(enabled: true, isTracking: false, hasSelectedProjects: false, secondsSinceUserInput: 5, thresholdMinutes: 15, now: start.addingTimeInterval(900)))
        XCTAssertFalse(service.shouldSendUnassignedReminder(enabled: true, isTracking: false, hasSelectedProjects: false, secondsSinceUserInput: 5, thresholdMinutes: 15, now: start.addingTimeInterval(901)))
    }
}

final class AppTimerSchemaTests: XCTestCase {
    func testMigrationPlanUsesDistinctPhysicalSchemaVersions() {
        XCTAssertEqual(AppTimerSchemaMigrationPlan.schemas.count, 2)
        XCTAssertEqual(AppTimerSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(AppTimerSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
    }
}
