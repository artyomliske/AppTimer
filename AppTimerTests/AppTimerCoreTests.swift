import Foundation
import XCTest

final class AllocationEngineTests: XCTestCase {
    func testEmptyProjectsProduceNoWeights() {
        XCTAssertEqual(AllocationEngine.weights(for: [], mode: .equal, customWeights: [:]), [:])
    }

    func testEqualAllocationSplitsWeightEvenly() {
        let projects = [Project(name: "A"), Project(name: "B"), Project(name: "C")]
        let weights = AllocationEngine.weights(for: projects, mode: .equal, customWeights: [:])

        XCTAssertEqual(weights.values.reduce(0, +), 1, accuracy: 0.000_001)
        projects.forEach { XCTAssertEqual(weights[$0.id] ?? 0, 1.0 / 3.0, accuracy: 0.000_001) }
    }

    func testFullToEachGivesEveryProjectFullWeight() {
        let projects = [Project(name: "A"), Project(name: "B")]
        let weights = AllocationEngine.weights(for: projects, mode: .fullToEach, customWeights: [:])

        XCTAssertEqual(weights[projects[0].id], 1)
        XCTAssertEqual(weights[projects[1].id], 1)
        XCTAssertEqual(weights.values.reduce(0, +), 2)
    }

    func testCustomWeightsNormalizeToOne() {
        let projects = [Project(name: "A"), Project(name: "B")]
        let weights = AllocationEngine.weights(
            for: projects,
            mode: .customWeights,
            customWeights: [projects[0].id: 2, projects[1].id: 6]
        )

        XCTAssertEqual(weights[projects[0].id] ?? 0, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(weights[projects[1].id] ?? 0, 0.75, accuracy: 0.000_001)
    }

    func testZeroCustomWeightsFallBackToEqualAllocation() {
        let projects = [Project(name: "A"), Project(name: "B")]
        let weights = AllocationEngine.weights(
            for: projects,
            mode: .customWeights,
            customWeights: [projects[0].id: 0, projects[1].id: -1]
        )

        XCTAssertEqual(weights[projects[0].id] ?? 0, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(weights[projects[1].id] ?? 0, 0.5, accuracy: 0.000_001)
    }
}

final class ReportCalculatorTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute))!
    }

    private func session(start: Date, end: Date?) -> WorkSession {
        let session = WorkSession(startedAt: start, allocationMode: .equal)
        session.endedAt = end
        return session
    }

    func testSessionInsideIntervalKeepsFullDuration() {
        let work = session(start: date(4, 10), end: date(4, 11))
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        XCTAssertEqual(ReportCalculator.actualDuration(of: work, clippedTo: interval), 3_600)
    }

    func testSessionCrossingMidnightIsClippedToDay() {
        let work = session(start: date(4, 23), end: date(5, 1))
        let interval = DateInterval(start: date(5, 0), end: date(6, 0))

        XCTAssertEqual(ReportCalculator.actualDuration(of: work, clippedTo: interval), 3_600)
    }

    func testOpenSessionUsesProvidedNow() {
        let work = session(start: date(4, 10), end: nil)
        let now = date(4, 12, 30)

        XCTAssertEqual(ReportCalculator.actualDuration(of: work, now: now), 9_000)
    }

    func testNonOverlappingSessionIsExcluded() {
        let work = session(start: date(1, 10), end: date(1, 11))
        let interval = DateInterval(start: date(4, 0), end: date(5, 0))

        XCTAssertTrue(ReportCalculator.sessions(in: interval, from: [work]).isEmpty)
    }

    func testApplicationDurationsExcludeConfiguredBundleIdentifier() {
        let work = session(start: date(4, 10), end: date(4, 11))
        let included = AppSegment(bundleIdentifier: "com.example.work", appName: "Work", session: work, startedAt: date(4, 10))
        included.endedAt = date(4, 10, 30)
        let excluded = AppSegment(bundleIdentifier: "com.example.chat", appName: "Chat", session: work, startedAt: date(4, 10, 30))
        excluded.endedAt = date(4, 11)
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

    func testFocusDurationsSeparateWorkDistractionAndNeutralContext() {
        let work = session(start: date(4, 10), end: date(4, 11))
        let editor = AppSegment(bundleIdentifier: "com.example.editor", appName: "Editor", session: work, startedAt: date(4, 10))
        editor.endedAt = date(4, 10, 20)
        let chat = AppSegment(bundleIdentifier: "com.example.chat", appName: "Chat", session: work, startedAt: date(4, 10, 20))
        chat.endedAt = date(4, 10, 45)
        let finder = AppSegment(bundleIdentifier: "com.apple.finder", appName: "Finder", session: work, startedAt: date(4, 10, 45))
        finder.endedAt = date(4, 11)
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
}
