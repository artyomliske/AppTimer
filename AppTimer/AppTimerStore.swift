// AppTimer application store: coordinates local persistence, sessions, project selection and reports.
import AppKit
import Foundation
import Observation
import OSLog
import SwiftData

@MainActor
@Observable
final class AppTimerStore {
    var projects: [Project] = []
    var sessions: [WorkSession] = []
    var contextSegments: [ContextSegment] = []
    var selectedProjectIDs: Set<UUID> = []
    var selectedAllocationMode: AllocationMode = .equal
    var customWeights: [UUID: Double] = [:]
    var activeSession: WorkSession?
    var now = Date()
    var statusMessage = L10n.text("status.choose_project")
    var recoveredSessionNotice: RecoveredSessionNotice?
    var storageErrorMessage: String?

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var workspaceMonitor = WorkspaceMonitor()
    @ObservationIgnored private var idleMonitor = IdleMonitor()
    @ObservationIgnored private var notificationManager = LocalNotificationManager()
    @ObservationIgnored private let sessionService = SessionService()
    @ObservationIgnored private let focusService = FocusService()
    @ObservationIgnored private let reminderService = ReminderService()
    @ObservationIgnored private let contextRecorder = ContextRecorder()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var activeSegment: AppSegment?
    @ObservationIgnored private var lastHeartbeatAt: Date?
    @ObservationIgnored private var lastContextCleanupAt: Date?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private let logger = Logger(subsystem: "com.apptimer.app", category: "persistence")
    @ObservationIgnored private var isConfigured = false
    let settings: AppTimerSettings

    init(settings: AppTimerSettings? = nil) {
        self.settings = settings ?? AppTimerSettings()
    }

    var defaultAllocationMode: AllocationMode {
        get { settings.defaultAllocationMode }
        set { settings.defaultAllocationMode = newValue }
    }

    var excludedBundleIdentifiers: Set<String> {
        get { settings.excludedBundleIdentifiers }
        set { settings.excludedBundleIdentifiers = newValue }
    }

    var idlePauseEnabled: Bool {
        settings.idlePauseEnabled
    }

    var idlePauseMinutes: Int {
        settings.idlePauseMinutes
    }

    var unassignedReminderEnabled: Bool {
        settings.unassignedReminderEnabled
    }

    var unassignedReminderMinutes: Int {
        settings.unassignedReminderMinutes
    }

    var focusModeEnabled: Bool {
        settings.focusModeEnabled
    }

    var distractionAlertMinutes: Int {
        settings.distractionAlertMinutes
    }

    var distractionReminderCooldownMinutes: Int {
        settings.distractionReminderCooldownMinutes
    }

    var workBundleIdentifiers: Set<String> {
        settings.workBundleIdentifiers
    }

    var distractingBundleIdentifiers: Set<String> {
        settings.distractingBundleIdentifiers
    }

    var passiveContextRecordingEnabled: Bool {
        settings.passiveContextRecordingEnabled
    }

    var contextRetention: ContextHistoryRetention {
        settings.contextRetention
    }

    private var recentProjectIDs: [UUID] {
        get { settings.recentProjectIDs }
        set { settings.recentProjectIDs = newValue }
    }

    var selectedProjects: [Project] {
        projects.filter { selectedProjectIDs.contains($0.id) }
    }

    var recentProjects: [Project] {
        let byID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        return recentProjectIDs.compactMap { id in
            guard let project = byID[id], !project.isArchived else { return nil }
            return project
        }
    }

    var isTracking: Bool { activeSession != nil }

    var activeFocusPreset: FocusSessionPreset? { focusService.activePreset }

    var hasActiveFocusSession: Bool { focusService.hasActiveSession }

    var focusSessionRemaining: TimeInterval {
        focusService.remaining(at: now)
    }

    var focusSessionProgress: Double {
        focusService.progress(at: now)
    }

    var focusPulseState: FocusPulseState {
        focusService.pulseState(isTracking: isTracking, at: now)
    }

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

    var todayFocusDurations: FocusDurationSummary {
        ReportCalculator.focusDurations(
            for: sessions,
            interval: todayInterval,
            workBundleIdentifiers: workBundleIdentifiers,
            distractingBundleIdentifiers: distractingBundleIdentifiers,
            now: now
        )
    }

    var recentFocusDays: [FocusDaySummary] {
        let calendar = Calendar.current
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 6, to: now),
                  let interval = calendar.dateInterval(of: .day, for: date) else { return nil }
            let durations = ReportCalculator.focusDurations(
                for: sessions,
                interval: interval,
                workBundleIdentifiers: workBundleIdentifiers,
                distractingBundleIdentifiers: distractingBundleIdentifiers,
                now: now
            )
            return FocusDaySummary(date: interval.start, work: durations.work, distracting: durations.distracting)
        }
    }

    var focusApplications: [FocusApplication] {
        var names = settings.focusApplicationNames
        sessions.forEach { session in
            session.appSegments.forEach { segment in
                if names[segment.bundleIdentifier] == nil { names[segment.bundleIdentifier] = segment.appName }
            }
        }
        settings.workBundleIdentifiers.union(settings.distractingBundleIdentifiers).forEach { identifier in
            if names[identifier] == nil { names[identifier] = identifier }
        }
        return names.map { identifier, name in
            FocusApplication(bundleIdentifier: identifier, name: name, role: focusRole(for: identifier))
        }
        .sorted { lhs, rhs in
            if lhs.role != rhs.role { return lhs.role.rawValue < rhs.role.rawValue }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
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
        refresh()
        recoverInterruptedSessionsIfNeeded()
        recoverPassiveContextIfNeeded()
        purgeExpiredPassiveContextIfNeeded(force: true)
        workspaceMonitor.onApplicationChange = { [weak self] application in
            self?.recordPassiveContext(application: application, at: .now)
            self?.transition(to: application)
        }
        workspaceMonitor.onSystemPause = { [weak self] in
            self?.stopTracking(reason: L10n.text("status.sleep_stopped"))
        }
        idleMonitor.onIdleThresholdReached = { [weak self] in
            self?.pauseForInactivity()
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeActiveSession(at: .now)
                self?.closePassiveContext(at: .now)
            }
        }
        if idlePauseEnabled || unassignedReminderEnabled || focusModeEnabled {
            notificationManager.requestAuthorizationIfNeeded()
        }
        if idlePauseEnabled {
            idleMonitor.start(threshold: TimeInterval(idlePauseMinutes * 60))
        }
        workspaceMonitor.start()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.now = .now
                self?.checkUnassignedProjectReminder()
                self?.checkDistractionReminder()
                self?.updateFocusSession()
                self?.updateHeartbeatIfNeeded()
                self?.updatePassiveContextHeartbeatIfNeeded()
                self?.purgeExpiredPassiveContextIfNeeded()
            }
        }
    }

    func refresh() {
        guard let modelContext else { return }
        let projectDescriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.name)])
        let sessionDescriptor = FetchDescriptor<WorkSession>(sortBy: [SortDescriptor(\WorkSession.startedAt, order: .reverse)])
        let contextDescriptor = FetchDescriptor<ContextSegment>(sortBy: [SortDescriptor(\ContextSegment.startedAt, order: .reverse)])
        do {
            projects = try modelContext.fetch(projectDescriptor)
            sessions = try modelContext.fetch(sessionDescriptor)
            contextSegments = try modelContext.fetch(contextDescriptor)
            storageErrorMessage = nil
        } catch {
            logger.error("Не удалось загрузить локальные данные: \(error.localizedDescription, privacy: .public)")
            storageErrorMessage = L10n.text("status.storage_load_failed")
            statusMessage = L10n.text("status.storage_load_error")
            return
        }
        activeSession = sessions.first(where: { $0.endedAt == nil })
        activeSegment = activeSession?.appSegments.last(where: { $0.endedAt == nil })

        if let activeSession {
            selectedProjectIDs = Set(activeSession.allocations.compactMap { $0.project?.id })
            selectedAllocationMode = activeSession.allocationMode
            customWeights = Dictionary(uniqueKeysWithValues: activeSession.allocations.compactMap { allocation in
                allocation.project.map { ($0.id, allocation.weight) }
            })
            statusMessage = L10n.format("status.tracking", elapsedText)
        }
    }

    func createProject(named name: String) {
        guard let modelContext,
              let project = sessionService.createProject(named: name, existingCount: projects.count, in: modelContext) else { return }
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
        isTracking ? stopTracking(reason: L10n.text("status.tracking_stopped")) : startTracking()
    }

    func startFocusSession(_ preset: FocusSessionPreset) {
        guard !selectedProjectIDs.isEmpty else {
            statusMessage = L10n.text("status.choose_focus_project")
            return
        }
        if !isTracking { startTracking() }
        guard isTracking else { return }

        focusService.start(preset, at: now)
        notificationManager.requestAuthorizationIfNeeded()
        statusMessage = L10n.format("status.focus", preset.title)
    }

    func cancelFocusSession() {
        guard hasActiveFocusSession else { return }
        focusService.cancel()
        statusMessage = isTracking ? L10n.text("status.focus_cancelled_tracking") : L10n.text("status.focus_cancelled")
    }

    func startTracking() {
        guard let modelContext else { return }
        let currentProjects = selectedProjects
        guard !currentProjects.isEmpty else {
            statusMessage = L10n.text("status.choose_at_least_one")
            return
        }
        rememberRecentProjects(currentProjects)
        guard let session = sessionService.start(
            projects: currentProjects,
            allocationMode: selectedAllocationMode,
            customWeights: customWeights,
            in: modelContext
        ) else { return }
        activeSession = session
        now = .now
        transition(to: workspaceMonitor.currentApplication)
        saveAndRefresh()
        writeHeartbeat(at: now)
        statusMessage = L10n.format("status.tracking", elapsedText)
    }

    func stopTracking(reason: String = L10n.text("status.tracking_stopped")) {
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

    func setIdlePauseEnabled(_ enabled: Bool) {
        settings.idlePauseEnabled = enabled
        if enabled {
            notificationManager.requestAuthorizationIfNeeded()
            idleMonitor.start(threshold: TimeInterval(idlePauseMinutes * 60))
        } else {
            idleMonitor.stop()
        }
    }

    func setIdlePauseMinutes(_ minutes: Int) {
        settings.idlePauseMinutes = minutes
        idleMonitor.updateThreshold(TimeInterval(settings.idlePauseMinutes * 60))
    }

    func setUnassignedReminderEnabled(_ enabled: Bool) {
        settings.unassignedReminderEnabled = enabled
        if enabled { notificationManager.requestAuthorizationIfNeeded() }
        reminderService.resetUnassignedReminder()
    }

    func setUnassignedReminderMinutes(_ minutes: Int) {
        settings.unassignedReminderMinutes = minutes
        reminderService.resetUnassignedReminder()
    }

    func setFocusModeEnabled(_ enabled: Bool) {
        settings.focusModeEnabled = enabled
        if enabled { notificationManager.requestAuthorizationIfNeeded() }
        updateDistractionState(for: enabled ? workspaceMonitor.currentApplication : nil, at: .now)
    }

    func setDistractionAlertMinutes(_ minutes: Int) {
        settings.distractionAlertMinutes = minutes
    }

    func setDistractionReminderCooldownMinutes(_ minutes: Int) {
        settings.distractionReminderCooldownMinutes = minutes
    }

    func setPassiveContextRecordingEnabled(_ enabled: Bool) {
        guard settings.passiveContextRecordingEnabled != enabled else { return }
        settings.passiveContextRecordingEnabled = enabled
        if enabled {
            recordPassiveContext(application: workspaceMonitor.currentApplication, at: .now)
            purgeExpiredPassiveContextIfNeeded(force: true)
        } else {
            closePassiveContext(at: .now)
        }
    }

    func setContextRetention(_ retention: ContextHistoryRetention) {
        settings.contextRetention = retention
        purgeExpiredPassiveContextIfNeeded(force: true)
    }

    func deletePassiveContextHistory() {
        guard let modelContext,
              contextRecorder.deleteAllSegments(contextSegments, settings: settings, in: modelContext, at: .now) else { return }
        _ = saveAndRefresh()
    }

    func focusRole(for bundleIdentifier: String) -> FocusApplicationRole {
        if distractingBundleIdentifiers.contains(bundleIdentifier) { return .distracting }
        if workBundleIdentifiers.contains(bundleIdentifier) { return .work }
        return .neutral
    }

    func setFocusRole(_ role: FocusApplicationRole, for bundleIdentifier: String, name: String? = nil) {
        let identifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return }
        var work = workBundleIdentifiers
        var distracting = distractingBundleIdentifiers
        work.remove(identifier)
        distracting.remove(identifier)
        switch role {
        case .work: work.insert(identifier)
        case .distracting: distracting.insert(identifier)
        case .neutral: break
        }
        settings.workBundleIdentifiers = work
        settings.distractingBundleIdentifiers = distracting
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            var names = settings.focusApplicationNames
            names[identifier] = name
            settings.focusApplicationNames = names
        }
        updateDistractionState(for: workspaceMonitor.currentApplication, at: .now)
    }

    func selectRecentProject(_ project: Project) {
        guard !project.isArchived else { return }
        let shouldRestart = isTracking
        if shouldRestart { closeActiveSession() }
        selectedProjectIDs = [project.id]
        if selectedAllocationMode == .customWeights, customWeights[project.id] == nil {
            customWeights[project.id] = 1
        }
        if shouldRestart { startTracking() }
        updateIdleStatus()
    }

    func updateCompletedSession(_ session: WorkSession, startedAt: Date, endedAt: Date, note: String = "") {
        guard session.endedAt != nil, endedAt > startedAt else { return }
        let conflicts = sessionService.overlappingCompletedSessions(
            sessions.filter { $0.id != session.id },
            start: startedAt,
            end: endedAt
        )
        guard conflicts.isEmpty else { return }
        session.startedAt = startedAt
        session.endedAt = endedAt
        session.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAndRefresh()
    }

    func retroSessionConflicts(start: Date, end: Date) -> [WorkSession] {
        sessionService.overlappingCompletedSessions(sessions, start: start, end: end)
    }

    @discardableResult
    func createRetroSession(
        start: Date,
        end: Date,
        projectIDs: Set<UUID>,
        allocationMode: AllocationMode,
        customWeights: [UUID: Double] = [:],
        resolution: RetroSessionConflictResolution?
    ) -> Bool {
        guard let modelContext,
              end > start,
              end <= now,
              !projectIDs.isEmpty else { return false }
        let projects = self.projects.filter { projectIDs.contains($0.id) && !$0.isArchived }
        guard projects.count == projectIDs.count,
              sessionService.createRetroSession(
                start: start,
                end: end,
                projects: projects,
                allocationMode: allocationMode,
                customWeights: customWeights,
                existingSessions: sessions,
                resolution: resolution,
                in: modelContext
              ) != nil else { return false }
        return saveAndRefresh()
    }

    func updateProject(_ project: Project, clientName: String, hourlyRate: Double?, weeklyGoalMinutes: Int?) {
        project.clientName = clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : clientName
        project.hourlyRate = hourlyRate
        project.weeklyGoalMinutes = weeklyGoalMinutes
        saveAndRefresh()
    }

    func deleteCompletedSession(_ session: WorkSession) {
        guard session.endedAt != nil else { return }
        modelContext?.delete(session)
        saveAndRefresh()
    }

    func dismissRecoveredSessionNotice() {
        recoveredSessionNotice = nil
    }

    func toggleApplicationExclusion(_ bundleIdentifier: String) {
        var excluded = excludedBundleIdentifiers
        if excluded.contains(bundleIdentifier) { excluded.remove(bundleIdentifier) }
        else { excluded.insert(bundleIdentifier) }
        excludedBundleIdentifiers = excluded
    }

    private func closeActiveSession(at end: Date = .now) {
        guard let session = activeSession else { return }
        endActiveSegment(at: end)
        sessionService.close(session: session, activeSegment: nil, at: end)
        activeSession = nil
        resetDistractionState()
        cancelFocusSession()
        if saveAndRefresh() {
            clearHeartbeat(for: session.id)
        }
    }

    private func transition(to application: ActiveApplicationInfo?) {
        guard let session = activeSession else { return }
        let end = Date()
        endActiveSegment(at: end)
        updateDistractionState(for: application, at: end)

        guard let modelContext else { return }
        activeSegment = sessionService.beginApplicationSegment(
            for: session,
            application: application,
            at: end,
            in: modelContext
        )
        _ = save(context: "смена активного приложения")
    }

    private func endActiveSegment(at date: Date) {
        activeSegment?.endedAt = date
        activeSegment = nil
    }

    @discardableResult
    private func saveAndRefresh() -> Bool {
        guard save(context: "сохранение данных") else { return false }
        refresh()
        return true
    }

    @discardableResult
    private func save(context: String) -> Bool {
        guard let modelContext else { return false }
        do {
            try modelContext.save()
            storageErrorMessage = nil
            return true
        } catch {
            logger.error("Не удалось выполнить \(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
            storageErrorMessage = L10n.text("status.storage_save_failed")
            statusMessage = L10n.text("status.storage_save_error")
            return false
        }
    }

    private func updateIdleStatus() {
        if !isTracking {
            statusMessage = selectedProjectIDs.isEmpty ? L10n.text("status.choose_project") : L10n.text("status.ready")
        }
    }

    private func rememberRecentProjects(_ projects: [Project]) {
        var ids = recentProjectIDs
        for project in projects.reversed() {
            ids.removeAll { $0 == project.id }
            ids.insert(project.id, at: 0)
        }
        recentProjectIDs = Array(ids.prefix(5))
    }

    private var activeSessionHeartbeat: (sessionID: UUID, date: Date)? {
        settings.heartbeat()
    }

    private func updateHeartbeatIfNeeded() {
        guard isTracking else { return }
        guard lastHeartbeatAt == nil || now.timeIntervalSince(lastHeartbeatAt!) >= 30 else { return }
        writeHeartbeat(at: now)
    }

    private func writeHeartbeat(at date: Date) {
        guard let sessionID = activeSession?.id else { return }
        settings.writeHeartbeat(sessionID: sessionID, at: date)
        lastHeartbeatAt = date
    }

    private func clearHeartbeat(for sessionID: UUID) {
        settings.clearHeartbeat(for: sessionID)
        lastHeartbeatAt = nil
    }

    private func recordPassiveContext(application: ActiveApplicationInfo?, at date: Date) {
        guard let modelContext else { return }
        let didChange = contextRecorder.record(
            application: application,
            enabled: passiveContextRecordingEnabled,
            settings: settings,
            context: modelContext,
            at: date
        )
        if didChange { _ = saveAndRefresh() }
    }

    private func closePassiveContext(at date: Date) {
        guard contextRecorder.close(settings: settings, at: date) else { return }
        _ = saveAndRefresh()
    }

    private func recoverPassiveContextIfNeeded() {
        guard contextRecorder.restoreOpenSegments(contextSegments, settings: settings, now: .now) else { return }
        _ = saveAndRefresh()
    }

    private func updatePassiveContextHeartbeatIfNeeded() {
        guard passiveContextRecordingEnabled else { return }
        contextRecorder.updateHeartbeat(settings: settings, at: now)
    }

    private func purgeExpiredPassiveContextIfNeeded(force: Bool = false) {
        guard let modelContext else { return }
        if !force,
           let lastContextCleanupAt,
           now.timeIntervalSince(lastContextCleanupAt) < 3_600 { return }
        lastContextCleanupAt = now
        guard contextRecorder.purgeExpiredSegments(
            contextSegments,
            retention: contextRetention,
            in: modelContext,
            now: now
        ) else { return }
        _ = saveAndRefresh()
    }

    private func recoverInterruptedSessionsIfNeeded() {
        let notices = sessionService.recoverInterruptedSessions(sessions, heartbeat: activeSessionHeartbeat, now: Date())
        notices.forEach { clearHeartbeat(for: $0.sessionID) }
        guard !notices.isEmpty else { return }
        recoveredSessionNotice = notices.last
        if save(context: "восстановление прерванной сессии") {
            refresh()
        }
    }

    private func pauseForInactivity() {
        guard idlePauseEnabled, isTracking else { return }
        stopTracking(reason: L10n.format("status.idle_paused", idlePauseMinutes))
        notificationManager.post(
            identifier: "apptimer.idle-pause",
            title: L10n.text("notification.idle.title"),
            body: L10n.format("notification.idle.body", idlePauseMinutes)
        )
    }

    private func updateDistractionState(for application: ActiveApplicationInfo?, at date: Date) {
        focusService.updateDistraction(
            application: application,
            focusEnabled: focusModeEnabled,
            isTracking: isTracking,
            isDistracting: { self.focusRole(for: $0) == .distracting },
            at: date
        )
    }

    private func resetDistractionState() {
        focusService.resetDistraction()
    }

    private func checkDistractionReminder() {
        guard focusModeEnabled,
              isTracking,
              let application = focusService.shouldSendDistractionReminder(
                after: distractionAlertMinutes,
                cooldownMinutes: distractionReminderCooldownMinutes,
                now: now
              ) else { return }

        let projectNames = selectedProjects.map(\.name).joined(separator: ", ")
        notificationManager.post(
            identifier: "apptimer.distraction-reminder",
            title: L10n.text("notification.distraction.title"),
            body: L10n.format("notification.distraction.body", application.name, distractionAlertMinutes, projectNames)
        )
    }

    private func updateFocusSession() {
        guard let preset = focusService.completeIfNeeded(at: now) else { return }
        statusMessage = L10n.format("status.focus_completed", preset.title)
        notificationManager.post(
            identifier: "apptimer.focus-session-complete",
            title: L10n.text("notification.focus.title"),
            body: L10n.format("notification.focus.body", preset.title)
        )
    }

    private func checkUnassignedProjectReminder() {
        guard reminderService.shouldSendUnassignedReminder(
            enabled: unassignedReminderEnabled,
            isTracking: isTracking,
            hasSelectedProjects: !selectedProjectIDs.isEmpty,
            secondsSinceUserInput: idleMonitor.secondsSinceUserInput,
            thresholdMinutes: unassignedReminderMinutes,
            now: now
        ) else { return }

        notificationManager.post(
            identifier: "apptimer.project-reminder",
            title: L10n.text("notification.project.title"),
            body: L10n.text("notification.project.body")
        )
    }
}
