// AppTimer application store: coordinates local persistence, sessions, project selection and reports.
import AppKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppTimerStore {
    var projects: [Project] = []
    var sessions: [WorkSession] = []
    var selectedProjectIDs: Set<UUID> = []
    var selectedAllocationMode: AllocationMode = .equal
    var customWeights: [UUID: Double] = [:]
    var activeSession: WorkSession?
    var now = Date()
    var statusMessage = "Выберите проект, чтобы начать учёт"

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var workspaceMonitor = WorkspaceMonitor()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var activeSegment: AppSegment?
    @ObservationIgnored private var isConfigured = false

    var defaultAllocationMode: AllocationMode {
        get { AllocationMode(rawValue: UserDefaults.standard.string(forKey: "defaultAllocationMode") ?? "equal") ?? .equal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "defaultAllocationMode") }
    }

    var excludedBundleIdentifiers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIdentifiers") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "excludedBundleIdentifiers") }
    }

    var selectedProjects: [Project] {
        projects.filter { selectedProjectIDs.contains($0.id) }
    }

    var isTracking: Bool { activeSession != nil }

    var elapsedText: String {
        guard let activeSession else { return "00:00" }
        return activeSession.duration(until: now).appTimerCompactText
    }

    var todayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 0)
    }

    var todayProjectDurations: [ProjectDuration] {
        ReportCalculator.projectDurations(for: sessions, interval: todayInterval, now: now)
    }

    var todayApplicationDurations: [ApplicationDuration] {
        ReportCalculator.applicationDurations(for: sessions, interval: todayInterval, excludedBundleIdentifiers: excludedBundleIdentifiers, now: now)
    }

    var todayActualDuration: TimeInterval {
        ReportCalculator.sessions(in: todayInterval, from: sessions, now: now)
            .reduce(0) { $0 + ReportCalculator.actualDuration(of: $1, clippedTo: todayInterval, now: now) }
    }

    func configure(with modelContext: ModelContext) {
        guard !isConfigured else { return }
        self.modelContext = modelContext
        isConfigured = true
        selectedAllocationMode = defaultAllocationMode
        workspaceMonitor.onApplicationChange = { [weak self] application in
            self?.transition(to: application)
        }
        workspaceMonitor.onSystemPause = { [weak self] in
            self?.stopTracking(reason: "Учёт остановлен во время сна Mac")
        }
        workspaceMonitor.start()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.now = .now
            }
        }
        refresh()
    }

    func refresh() {
        guard let modelContext else { return }
        let projectDescriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.name)])
        let sessionDescriptor = FetchDescriptor<WorkSession>(sortBy: [SortDescriptor(\WorkSession.startedAt, order: .reverse)])
        projects = (try? modelContext.fetch(projectDescriptor)) ?? []
        sessions = (try? modelContext.fetch(sessionDescriptor)) ?? []
        activeSession = sessions.first(where: { $0.endedAt == nil })

        if let activeSession {
            selectedProjectIDs = Set(activeSession.allocations.compactMap { $0.project?.id })
            selectedAllocationMode = activeSession.allocationMode
            customWeights = Dictionary(uniqueKeysWithValues: activeSession.allocations.compactMap { allocation in
                allocation.project.map { ($0.id, allocation.weight) }
            })
            statusMessage = "Идёт учёт: \(elapsedText)"
        }
    }

    func createProject(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let modelContext else { return }
        let palette = ["397CFF", "8B5CF6", "10B981", "F59E0B", "EF4444", "06B6D4"]
        let project = Project(name: trimmed, colorHex: palette[projects.count % palette.count])
        modelContext.insert(project)
        saveAndRefresh()
        selectedProjectIDs.insert(project.id)
    }

    func toggleProject(_ project: Project) {
        let shouldRestart = isTracking
        if shouldRestart { closeActiveSession() }
        if selectedProjectIDs.contains(project.id) {
            selectedProjectIDs.remove(project.id)
        } else {
            selectedProjectIDs.insert(project.id)
            if selectedAllocationMode == .customWeights, customWeights[project.id] == nil {
                customWeights[project.id] = 1
            }
        }
        if shouldRestart, !selectedProjectIDs.isEmpty { startTracking() }
        updateIdleStatus()
    }

    func changeAllocationMode(to mode: AllocationMode) {
        let shouldRestart = isTracking
        if shouldRestart { closeActiveSession() }
        selectedAllocationMode = mode
        if mode == .customWeights {
            selectedProjects.forEach { project in
                if customWeights[project.id] == nil { customWeights[project.id] = 1 }
            }
        }
        if shouldRestart, !selectedProjectIDs.isEmpty { startTracking() }
    }

    func updateCustomWeight(for project: Project, percent: Double) {
        let shouldRestart = isTracking
        if shouldRestart { closeActiveSession() }
        customWeights[project.id] = max(0, percent)
        if shouldRestart, !selectedProjectIDs.isEmpty { startTracking() }
    }

    func startOrStopTracking() {
        isTracking ? stopTracking(reason: "Учёт остановлен") : startTracking()
    }

    func startTracking() {
        guard let modelContext else { return }
        let currentProjects = selectedProjects
        guard !currentProjects.isEmpty else {
            statusMessage = "Выберите хотя бы один проект"
            return
        }
        let session = WorkSession(allocationMode: selectedAllocationMode)
        let weights = AllocationEngine.weights(for: currentProjects, mode: selectedAllocationMode, customWeights: customWeights)
        modelContext.insert(session)
        currentProjects.forEach { project in
            let allocation = SessionProjectAllocation(project: project, session: session, weight: weights[project.id] ?? 0)
            session.allocations.append(allocation)
            modelContext.insert(allocation)
        }
        activeSession = session
        now = .now
        transition(to: workspaceMonitor.currentApplication)
        saveAndRefresh()
        statusMessage = "Идёт учёт: \(elapsedText)"
    }

    func stopTracking(reason: String = "Учёт остановлен") {
        guard activeSession != nil else { return }
        closeActiveSession()
        statusMessage = reason
    }

    func archive(_ project: Project) {
        project.isArchived = true
        selectedProjectIDs.remove(project.id)
        saveAndRefresh()
    }

    func setDefaultAllocationMode(_ mode: AllocationMode) {
        defaultAllocationMode = mode
    }

    func updateCompletedSession(_ session: WorkSession, startedAt: Date, endedAt: Date) {
        guard session.endedAt != nil, endedAt > startedAt else { return }
        session.startedAt = startedAt
        session.endedAt = endedAt
        saveAndRefresh()
    }

    func deleteCompletedSession(_ session: WorkSession) {
        guard session.endedAt != nil else { return }
        modelContext?.delete(session)
        saveAndRefresh()
    }

    func toggleApplicationExclusion(_ bundleIdentifier: String) {
        var excluded = excludedBundleIdentifiers
        if excluded.contains(bundleIdentifier) { excluded.remove(bundleIdentifier) }
        else { excluded.insert(bundleIdentifier) }
        excludedBundleIdentifiers = excluded
    }

    private func closeActiveSession() {
        guard let session = activeSession else { return }
        let end = Date()
        endActiveSegment(at: end)
        session.endedAt = end
        activeSession = nil
        saveAndRefresh()
    }

    private func transition(to application: ActiveApplicationInfo?) {
        guard let session = activeSession else { return }
        let end = Date()
        endActiveSegment(at: end)

        guard let application,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let segment = AppSegment(
            bundleIdentifier: application.bundleIdentifier,
            appName: application.name,
            session: session,
            startedAt: end
        )
        session.appSegments.append(segment)
        modelContext?.insert(segment)
        activeSegment = segment
        try? modelContext?.save()
    }

    private func endActiveSegment(at date: Date) {
        activeSegment?.endedAt = date
        activeSegment = nil
    }

    private func saveAndRefresh() {
        try? modelContext?.save()
        refresh()
    }

    private func updateIdleStatus() {
        if !isTracking {
            statusMessage = selectedProjectIDs.isEmpty ? "Выберите проект, чтобы начать учёт" : "Готово к началу учёта"
        }
    }
}
