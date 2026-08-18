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
    var selectedProjectIDs: Set<UUID> = []
    var selectedAllocationMode: AllocationMode = .equal
    var customWeights: [UUID: Double] = [:]
    var activeSession: WorkSession?
    var now = Date()
    var statusMessage = "Выберите проект, чтобы начать учёт"
    private(set) var focusSettingsRevision = 0
    var activeFocusPreset: FocusSessionPreset?
    var focusSessionStartedAt: Date?
    var focusSessionEndsAt: Date?
    var lastFocusSessionCompletedAt: Date?
    var recoveredSessionNotice: RecoveredSessionNotice?
    var storageErrorMessage: String?

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var workspaceMonitor = WorkspaceMonitor()
    @ObservationIgnored private var idleMonitor = IdleMonitor()
    @ObservationIgnored private var notificationManager = LocalNotificationManager()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var activeSegment: AppSegment?
    @ObservationIgnored private var unassignedActivityStartedAt: Date?
    @ObservationIgnored private var lastUnassignedReminderAt: Date?
    @ObservationIgnored private var distractingApplication: ActiveApplicationInfo?
    @ObservationIgnored private var distractingApplicationStartedAt: Date?
    @ObservationIgnored private var lastDistractionReminderAt: Date?
    @ObservationIgnored private var lastHeartbeatAt: Date?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private let logger = Logger(subsystem: "com.apptimer.app", category: "persistence")
    @ObservationIgnored private var isConfigured = false

    private static let heartbeatSessionIDKey = "activeSessionHeartbeatID"
    private static let heartbeatDateKey = "activeSessionHeartbeatDate"
    private static let interruptionGraceInterval: TimeInterval = 120

    var defaultAllocationMode: AllocationMode {
        get { AllocationMode(rawValue: UserDefaults.standard.string(forKey: "defaultAllocationMode") ?? "equal") ?? .equal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "defaultAllocationMode") }
    }

    var excludedBundleIdentifiers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIdentifiers") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "excludedBundleIdentifiers") }
    }

    var idlePauseEnabled: Bool {
        UserDefaults.standard.object(forKey: "idlePauseEnabled") as? Bool ?? true
    }

    var idlePauseMinutes: Int {
        max(1, UserDefaults.standard.object(forKey: "idlePauseMinutes") as? Int ?? 10)
    }

    var unassignedReminderEnabled: Bool {
        UserDefaults.standard.object(forKey: "unassignedReminderEnabled") as? Bool ?? true
    }

    var unassignedReminderMinutes: Int {
        max(1, UserDefaults.standard.object(forKey: "unassignedReminderMinutes") as? Int ?? 15)
    }

    var focusModeEnabled: Bool {
        _ = focusSettingsRevision
        return UserDefaults.standard.object(forKey: "focusModeEnabled") as? Bool ?? false
    }

    var distractionAlertMinutes: Int {
        _ = focusSettingsRevision
        return max(1, UserDefaults.standard.object(forKey: "distractionAlertMinutes") as? Int ?? 5)
    }

    var distractionReminderCooldownMinutes: Int {
        _ = focusSettingsRevision
        return max(1, UserDefaults.standard.object(forKey: "distractionReminderCooldownMinutes") as? Int ?? 15)
    }

    var workBundleIdentifiers: Set<String> {
        _ = focusSettingsRevision
        return Set(UserDefaults.standard.stringArray(forKey: "focusWorkBundleIdentifiers") ?? [])
    }

    var distractingBundleIdentifiers: Set<String> {
        _ = focusSettingsRevision
        return Set(UserDefaults.standard.stringArray(forKey: "focusDistractingBundleIdentifiers") ?? [])
    }

    private var recentProjectIDs: [UUID] {
        get {
            (UserDefaults.standard.stringArray(forKey: "recentProjectIDs") ?? [])
                .compactMap(UUID.init(uuidString:))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: "recentProjectIDs")
        }
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

    var hasActiveFocusSession: Bool { activeFocusPreset != nil && focusSessionEndsAt != nil }

    var focusSessionRemaining: TimeInterval {
        guard let focusSessionEndsAt else { return 0 }
        return max(0, focusSessionEndsAt.timeIntervalSince(now))
    }

    var focusSessionProgress: Double {
        guard let preset = activeFocusPreset, let startedAt = focusSessionStartedAt else { return 0 }
        let duration = TimeInterval(preset.minutes * 60)
        return min(1, max(0, now.timeIntervalSince(startedAt) / duration))
    }

    var focusPulseState: FocusPulseState {
        if distractingApplication != nil { return .distracted }
        if hasActiveFocusSession { return .focused }
        if let completedAt = lastFocusSessionCompletedAt,
           now.timeIntervalSince(completedAt) < 20 { return .completed }
        return isTracking ? .tracking : .resting
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
        _ = focusSettingsRevision
        var names = focusApplicationNames
        sessions.forEach { session in
            session.appSegments.forEach { segment in
                if names[segment.bundleIdentifier] == nil { names[segment.bundleIdentifier] = segment.appName }
            }
        }
        workBundleIdentifiers.union(distractingBundleIdentifiers).forEach { identifier in
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
        workspaceMonitor.onApplicationChange = { [weak self] application in
            self?.transition(to: application)
        }
        workspaceMonitor.onSystemPause = { [weak self] in
            self?.stopTracking(reason: "Учёт остановлен во время сна Mac")
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
            }
        }
    }

    func refresh() {
        guard let modelContext else { return }
        let projectDescriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.name)])
        let sessionDescriptor = FetchDescriptor<WorkSession>(sortBy: [SortDescriptor(\WorkSession.startedAt, order: .reverse)])
        do {
            projects = try modelContext.fetch(projectDescriptor)
            sessions = try modelContext.fetch(sessionDescriptor)
            storageErrorMessage = nil
        } catch {
            logger.error("Не удалось загрузить локальные данные: \(error.localizedDescription, privacy: .public)")
            storageErrorMessage = "Не удалось загрузить локальные данные. Перезапустите AppTimer; исходные файлы хранилища не изменены."
            statusMessage = "Ошибка загрузки локальных данных"
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

    func startFocusSession(_ preset: FocusSessionPreset) {
        guard !selectedProjectIDs.isEmpty else {
            statusMessage = "Выберите проект для фокус-сессии"
            return
        }
        if !isTracking { startTracking() }
        guard isTracking else { return }

        activeFocusPreset = preset
        focusSessionStartedAt = now
        focusSessionEndsAt = now.addingTimeInterval(TimeInterval(preset.minutes * 60))
        lastFocusSessionCompletedAt = nil
        notificationManager.requestAuthorizationIfNeeded()
        statusMessage = "Фокус: \(preset.title)"
    }

    func cancelFocusSession() {
        guard hasActiveFocusSession else { return }
        activeFocusPreset = nil
        focusSessionStartedAt = nil
        focusSessionEndsAt = nil
        statusMessage = isTracking ? "Фокус-сессия отменена, учёт продолжается" : "Фокус-сессия отменена"
    }

    func startTracking() {
        guard let modelContext else { return }
        let currentProjects = selectedProjects
        guard !currentProjects.isEmpty else {
            statusMessage = "Выберите хотя бы один проект"
            return
        }
        rememberRecentProjects(currentProjects)
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
        writeHeartbeat(at: now)
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

    func setIdlePauseEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "idlePauseEnabled")
        if enabled {
            notificationManager.requestAuthorizationIfNeeded()
            idleMonitor.start(threshold: TimeInterval(idlePauseMinutes * 60))
        } else {
            idleMonitor.stop()
        }
    }

    func setIdlePauseMinutes(_ minutes: Int) {
        let value = max(1, minutes)
        UserDefaults.standard.set(value, forKey: "idlePauseMinutes")
        idleMonitor.updateThreshold(TimeInterval(value * 60))
    }

    func setUnassignedReminderEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "unassignedReminderEnabled")
        if enabled { notificationManager.requestAuthorizationIfNeeded() }
        unassignedActivityStartedAt = nil
        lastUnassignedReminderAt = nil
    }

    func setUnassignedReminderMinutes(_ minutes: Int) {
        UserDefaults.standard.set(max(1, minutes), forKey: "unassignedReminderMinutes")
        unassignedActivityStartedAt = nil
        lastUnassignedReminderAt = nil
    }

    func setFocusModeEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "focusModeEnabled")
        if enabled { notificationManager.requestAuthorizationIfNeeded() }
        updateDistractionState(for: enabled ? workspaceMonitor.currentApplication : nil, at: .now)
        focusSettingsRevision += 1
    }

    func setDistractionAlertMinutes(_ minutes: Int) {
        UserDefaults.standard.set(max(1, minutes), forKey: "distractionAlertMinutes")
        focusSettingsRevision += 1
    }

    func setDistractionReminderCooldownMinutes(_ minutes: Int) {
        UserDefaults.standard.set(max(1, minutes), forKey: "distractionReminderCooldownMinutes")
        focusSettingsRevision += 1
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
        UserDefaults.standard.set(Array(work).sorted(), forKey: "focusWorkBundleIdentifiers")
        UserDefaults.standard.set(Array(distracting).sorted(), forKey: "focusDistractingBundleIdentifiers")
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            var names = focusApplicationNames
            names[identifier] = name
            focusApplicationNames = names
        }
        updateDistractionState(for: workspaceMonitor.currentApplication, at: .now)
        focusSettingsRevision += 1
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
        session.startedAt = startedAt
        session.endedAt = endedAt
        session.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAndRefresh()
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
        session.endedAt = end
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
            storageErrorMessage = "Не удалось сохранить локальные данные. Изменения останутся в памяти до повторной попытки."
            statusMessage = "Ошибка сохранения локальных данных"
            return false
        }
    }

    private func updateIdleStatus() {
        if !isTracking {
            statusMessage = selectedProjectIDs.isEmpty ? "Выберите проект, чтобы начать учёт" : "Готово к началу учёта"
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

    private var focusApplicationNames: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "focusApplicationNames") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "focusApplicationNames") }
    }

    private var activeSessionHeartbeat: (sessionID: UUID, date: Date)? {
        guard let rawID = UserDefaults.standard.string(forKey: Self.heartbeatSessionIDKey),
              let sessionID = UUID(uuidString: rawID),
              let date = UserDefaults.standard.object(forKey: Self.heartbeatDateKey) as? Date else {
            return nil
        }
        return (sessionID, date)
    }

    private func updateHeartbeatIfNeeded() {
        guard isTracking else { return }
        guard lastHeartbeatAt == nil || now.timeIntervalSince(lastHeartbeatAt!) >= 30 else { return }
        writeHeartbeat(at: now)
    }

    private func writeHeartbeat(at date: Date) {
        guard let sessionID = activeSession?.id else { return }
        UserDefaults.standard.set(sessionID.uuidString, forKey: Self.heartbeatSessionIDKey)
        UserDefaults.standard.set(date, forKey: Self.heartbeatDateKey)
        lastHeartbeatAt = date
    }

    private func clearHeartbeat(for sessionID: UUID) {
        guard activeSessionHeartbeat?.sessionID == sessionID else { return }
        UserDefaults.standard.removeObject(forKey: Self.heartbeatSessionIDKey)
        UserDefaults.standard.removeObject(forKey: Self.heartbeatDateKey)
        lastHeartbeatAt = nil
    }

    private func recoverInterruptedSessionsIfNeeded() {
        let currentTime = Date()
        var didRecover = false

        for session in sessions where session.endedAt == nil {
            let lastActivity = trustedActivityDate(for: session, now: currentTime)
            guard currentTime.timeIntervalSince(lastActivity) > Self.interruptionGraceInterval else { continue }

            let recoveryDate = min(currentTime, max(session.startedAt, lastActivity))
            session.appSegments
                .filter { $0.endedAt == nil }
                .forEach { $0.endedAt = max($0.startedAt, recoveryDate) }
            session.endedAt = recoveryDate
            clearHeartbeat(for: session.id)
            didRecover = true

            let projectNames = session.allocations.compactMap { $0.project?.name }.joined(separator: ", ")
            recoveredSessionNotice = RecoveredSessionNotice(
                sessionID: session.id,
                closedAt: recoveryDate,
                projectNames: projectNames.isEmpty ? "Без проекта" : projectNames
            )
        }

        guard didRecover else { return }
        if save(context: "восстановление прерванной сессии") {
            refresh()
        }
    }

    private func trustedActivityDate(for session: WorkSession, now: Date) -> Date {
        var candidates = [session.startedAt]
        candidates.append(contentsOf: session.appSegments.map { $0.endedAt ?? $0.startedAt })
        if let heartbeat = activeSessionHeartbeat, heartbeat.sessionID == session.id {
            candidates.append(heartbeat.date)
        }
        return min(now, candidates.max() ?? session.startedAt)
    }

    private func pauseForInactivity() {
        guard idlePauseEnabled, isTracking else { return }
        stopTracking(reason: "Учёт приостановлен: нет активности \(idlePauseMinutes) мин")
        notificationManager.post(
            identifier: "apptimer.idle-pause",
            title: "Учёт приостановлен",
            body: "AppTimer остановил учёт после \(idlePauseMinutes) мин бездействия."
        )
    }

    private func updateDistractionState(for application: ActiveApplicationInfo?, at date: Date) {
        guard focusModeEnabled,
              isTracking,
              let application,
              application.bundleIdentifier != Bundle.main.bundleIdentifier,
              focusRole(for: application.bundleIdentifier) == .distracting else {
            resetDistractionState()
            return
        }

        if distractingApplication?.bundleIdentifier != application.bundleIdentifier {
            distractingApplication = application
            distractingApplicationStartedAt = date
            lastDistractionReminderAt = nil
        }
    }

    private func resetDistractionState() {
        distractingApplication = nil
        distractingApplicationStartedAt = nil
        lastDistractionReminderAt = nil
    }

    private func checkDistractionReminder() {
        guard focusModeEnabled,
              isTracking,
              let application = distractingApplication,
              let startedAt = distractingApplicationStartedAt else { return }

        let currentTime = Date()
        guard currentTime.timeIntervalSince(startedAt) >= TimeInterval(distractionAlertMinutes * 60),
              lastDistractionReminderAt == nil || currentTime.timeIntervalSince(lastDistractionReminderAt!) >= TimeInterval(distractionReminderCooldownMinutes * 60) else { return }

        let projectNames = selectedProjects.map(\.name).joined(separator: ", ")
        notificationManager.post(
            identifier: "apptimer.distraction-reminder",
            title: "Пора вернуться к задаче",
            body: "Вы уже \(distractionAlertMinutes) мин в «\(application.name)». Активный проект: \(projectNames)."
        )
        lastDistractionReminderAt = currentTime
    }

    private func updateFocusSession() {
        guard let preset = activeFocusPreset,
              let endsAt = focusSessionEndsAt,
              now >= endsAt else { return }

        activeFocusPreset = nil
        focusSessionStartedAt = nil
        focusSessionEndsAt = nil
        lastFocusSessionCompletedAt = now
        statusMessage = "Фокус-блок \(preset.title) завершён"
        notificationManager.post(
            identifier: "apptimer.focus-session-complete",
            title: "Фокус-блок завершён",
            body: "Вы завершили блок на \(preset.title). Сделайте короткую паузу или продолжите учёт."
        )
    }

    private func checkUnassignedProjectReminder() {
        guard unassignedReminderEnabled,
              !isTracking,
              selectedProjectIDs.isEmpty,
              idleMonitor.secondsSinceUserInput < 90 else {
            unassignedActivityStartedAt = nil
            return
        }

        let currentTime = Date()
        if unassignedActivityStartedAt == nil { unassignedActivityStartedAt = currentTime }
        guard let startedAt = unassignedActivityStartedAt,
              currentTime.timeIntervalSince(startedAt) >= TimeInterval(unassignedReminderMinutes * 60),
              lastUnassignedReminderAt == nil || currentTime.timeIntervalSince(lastUnassignedReminderAt!) >= TimeInterval(unassignedReminderMinutes * 60) else { return }

        notificationManager.post(
            identifier: "apptimer.project-reminder",
            title: "Выберите проект",
            body: "Вы используете Mac, но AppTimer пока не учитывает время."
        )
        lastUnassignedReminderAt = currentTime
    }
}
