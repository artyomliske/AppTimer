// AppTimer Dashboard: local reports for today, projects, reports and allocation settings.
import SwiftUI

@MainActor
struct DashboardView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var selection: SidebarItem? = .today

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("AppTimer") {
                    Label("Сегодня", systemImage: "clock") .tag(SidebarItem.today)
                    Label("Таймлайн", systemImage: "calendar.day.timeline.left") .tag(SidebarItem.timeline)
                    Label("Проекты", systemImage: "folder") .tag(SidebarItem.projects)
                    Label("Отчёты", systemImage: "chart.bar") .tag(SidebarItem.reports)
                }
                Section {
                    Label("Настройки", systemImage: "gearshape") .tag(SidebarItem.settings)
                }
            }
            .navigationTitle("AppTimer")
        } detail: {
            switch selection ?? .today {
            case .today: TodayView()
            case .timeline: TimelineView()
            case .projects: ProjectsView()
            case .reports: ReportsView()
            case .settings: SettingsView()
            }
        }
    }
}

private enum SidebarItem: Hashable {
    case today, timeline, projects, reports, settings
}

@MainActor
private struct TodayView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var editingRecoveredSession: WorkSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Сегодня").font(.largeTitle.bold())
                        Text("Локальный обзор вашего рабочего времени.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.isTracking ? "Остановить" : "Начать") { store.startOrStopTracking() }
                        .buttonStyle(.borderedProminent)
                        .tint(store.isTracking ? .red : .blue)
                        .disabled(!store.isTracking && store.selectedProjectIDs.isEmpty)
                }

                HStack(spacing: 14) {
                    MetricCard(title: "Фактическое время", value: store.todayActualDuration.appTimerText, detail: "все интервалы")
                    MetricCard(title: "Активный интервал", value: store.elapsedText, detail: store.isTracking ? "идёт учёт" : "учёт остановлен")
                    MetricCard(title: "Проекты", value: "\(store.selectedProjectIDs.count)", detail: "выбрано сейчас")
                }

                if let notice = store.recoveredSessionNotice {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Учёт был прерван некорректно")
                                .font(.headline)
                            Text("Интервал для «\(notice.projectNames)» закрыт в \(notice.closedAt.formatted(date: .omitted, time: .shortened)), чтобы не записать лишнее время.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let session = store.sessions.first(where: { $0.id == notice.sessionID }) {
                            Button("Править") {
                                editingRecoveredSession = session
                                store.dismissRecoveredSessionNotice()
                            }
                            .buttonStyle(.bordered)
                            Button("Удалить", role: .destructive) {
                                store.deleteCompletedSession(session)
                                store.dismissRecoveredSessionNotice()
                            }
                            .buttonStyle(.bordered)
                        }
                        Button("Скрыть") { store.dismissRecoveredSessionNotice() }
                            .buttonStyle(.borderless)
                    }
                    .padding(14)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }

                CalmFocusOverview()
                WeeklyFocusHeatmap()

                GroupBox("Выбранные проекты") {
                    if store.selectedProjects.isEmpty {
                        Text("Выберите проект в Menu Bar или на вкладке «Проекты».").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(store.selectedProjects) { project in
                                Label(project.name, systemImage: "circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(Color(hex: project.colorHex))
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(Color(hex: project.colorHex).opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 22) {
                    SummaryList(title: "По проектам", emptyText: "Нет завершённых интервалов", rows: store.todayProjectDurations.map {
                        SummaryRow(name: $0.name, primary: $0.allocated.appTimerText, secondary: "фактически \($0.actual.appTimerText)", color: Color(hex: $0.colorHex))
                    })
                    SummaryList(title: "По приложениям", emptyText: "Нет локальных меток программ", rows: store.todayApplicationDurations.map {
                        SummaryRow(name: $0.name, primary: $0.duration.appTimerText, secondary: nil, color: .secondary)
                    })
                }
            }
            .padding(28)
        }
        .navigationTitle("Сегодня")
        .sheet(item: $editingRecoveredSession) { SessionEditorSheet(session: $0) }
    }
}

@MainActor
private struct CalmFocusOverview: View {
    @Environment(AppTimerStore.self) private var store

    private var pulseColor: Color {
        switch store.focusPulseState {
        case .resting: .secondary
        case .tracking: .blue
        case .focused: .cyan
        case .distracted: .orange
        case .completed: .green
        }
    }

    var body: some View {
        let summary = store.todayFocusDurations
        GroupBox {
            HStack(spacing: 28) {
                FocusRingChart(summary: summary, state: store.focusPulseState)
                    .frame(width: 158, height: 158)

                VStack(alignment: .leading, spacing: 11) {
                    Label(store.focusPulseState.title, systemImage: store.focusPulseState.symbolName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(pulseColor)

                    if store.hasActiveFocusSession, let preset = store.activeFocusPreset {
                        Text("До завершения блока: \(store.focusSessionRemaining.appTimerCompactText)")
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                        ProgressView(value: store.focusSessionProgress)
                            .tint(.cyan)
                        HStack {
                            Text("\(preset.title) без переключений")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Отменить") { store.cancelFocusSession() }
                                .buttonStyle(.borderless)
                        }
                    } else {
                        Text(summary.work.appTimerText)
                            .font(.system(.title, design: .rounded).weight(.bold))
                        Text(summary.observed == 0 ? "Назначьте роли приложениям, чтобы увидеть ритм дня." : "рабочего контекста за сегодня")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(FocusSessionPreset.allCases) { preset in
                                Button(preset.title) { store.startFocusSession(preset) }
                                    .buttonStyle(.bordered)
                                    .tint(.cyan)
                                    .disabled(store.selectedProjectIDs.isEmpty)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
        } label: {
            Label("Calm Focus", systemImage: "scope")
        }
    }
}

@MainActor
private struct FocusRingChart: View {
    let summary: FocusDurationSummary
    let state: FocusPulseState

    private var total: TimeInterval { max(summary.observed, 1) }
    private var workEnd: Double { summary.work / total }
    private var distractionEnd: Double { min(1, workEnd + summary.distracting / total) }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 15)
            if summary.observed > 0 {
                Circle()
                    .trim(from: 0, to: max(0.015, workEnd))
                    .stroke(.cyan, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if summary.distracting > 0 {
                    Circle()
                        .trim(from: min(0.99, workEnd + 0.015), to: max(workEnd + 0.02, distractionEnd))
                        .stroke(.orange, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if summary.neutral > 0 {
                    Circle()
                        .trim(from: min(0.99, distractionEnd + 0.015), to: 1)
                        .stroke(.secondary.opacity(0.65), style: StrokeStyle(lineWidth: 15, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            VStack(spacing: 4) {
                Image(systemName: state.symbolName)
                    .font(.title2)
                    .foregroundStyle(state == .distracted ? .orange : .cyan)
                Text(summary.observed.appTimerText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Контекст дня: рабочее время \(summary.work.appTimerText), отвлечения \(summary.distracting.appTimerText)")
    }
}

@MainActor
private struct WeeklyFocusHeatmap: View {
    @Environment(AppTimerStore.self) private var store

    private func fill(for day: FocusDaySummary) -> Color {
        guard day.work > 0 else { return .secondary.opacity(0.12) }
        let intensity = min(1, day.work / (3 * 60 * 60))
        return .cyan.opacity(0.20 + 0.68 * intensity)
    }

    var body: some View {
        let days = store.recentFocusDays
        let totalWork = days.reduce(0) { $0 + $1.work }
        let totalDistraction = days.reduce(0) { $0 + $1.distracting }

        GroupBox {
            HStack(spacing: 10) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(fill(for: day))
                                .frame(height: 52)
                                .overlay {
                                    Text(day.work > 0 ? day.work.appTimerCompactText : "—")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(day.work > 0 ? .primary : .secondary)
                                }
                            if day.distracting > 0 {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 7, height: 7)
                                    .padding(5)
                            }
                        }
                        Text(day.date, format: .dateTime.weekday(.narrow))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted)): фокус \(day.work.appTimerText), отвлечения \(day.distracting.appTimerText)")
                }
            }
            .padding(.vertical, 6)
            HStack {
                Text("За 7 дней: \(totalWork.appTimerText) фокуса")
                Spacer()
                if totalDistraction > 0 {
                    Label(totalDistraction.appTimerText, systemImage: "circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } label: {
            Label("Ритм недели", systemImage: "calendar.day.timeline.left")
        }
    }
}

@MainActor
private struct ProjectsView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var newProjectName = ""
    @State private var editingProject: Project?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Проекты").font(.largeTitle.bold())
            HStack {
                TextField("Название нового проекта", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addProject)
                Button("Добавить", action: addProject)
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 470)

            List {
                ForEach(store.projects) { project in
                    HStack(spacing: 12) {
                        Circle().fill(Color(hex: project.colorHex)).frame(width: 10, height: 10)
                        VStack(alignment: .leading) {
                            Text(project.name)
                            Text(project.isArchived ? "В архиве" : "Активный проект").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Реквизиты") { editingProject = project }
                            .buttonStyle(.borderless)
                        Toggle("Выбран", isOn: Binding(
                            get: { store.selectedProjectIDs.contains(project.id) },
                            set: { _ in store.toggleProject(project) }
                        ))
                        .labelsHidden()
                        if !project.isArchived {
                            Button("Архивировать") { store.archive(project) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(28)
        .navigationTitle("Проекты")
        .sheet(item: $editingProject) { ProjectDetailsSheet(project: $0) }
    }

    private func addProject() {
        store.createProject(named: newProjectName)
        newProjectName = ""
    }
}

@MainActor
private struct ReportsView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var period: ReportPeriod = .today
    @State private var editingSession: WorkSession?

    var interval: DateInterval {
        switch period {
        case .today: store.todayInterval
        case .week: Calendar.current.dateInterval(of: .weekOfYear, for: store.now) ?? store.todayInterval
        case .month: Calendar.current.dateInterval(of: .month, for: store.now) ?? store.todayInterval
        }
    }

    var body: some View {
        let rows = ReportCalculator.projectDurations(for: store.sessions, interval: interval, now: store.now)
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Отчёты").font(.largeTitle.bold())
                    Text("Фактическое время и распределение по проектам.").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Период", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 270)
                Button("Экспорт CSV") {
                    let catalog = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0) })
                    CSVExporter.export(projects: rows, catalog: catalog, period: period.title)
                }
            }

            GroupBox("Проекты") {
                if rows.isEmpty {
                    ContentUnavailableView("Нет данных за выбранный период", systemImage: "chart.bar")
                        .frame(maxWidth: .infinity, minHeight: 210)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            HStack {
                                Circle().fill(Color(hex: row.colorHex)).frame(width: 9, height: 9)
                                Text(row.name)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(row.allocated.appTimerText).monospacedDigit()
                                    Text("фактически \(row.actual.appTimerText)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                }
            }
            GroupBox("Последние завершённые интервалы") {
                let completed = store.sessions.filter { $0.endedAt != nil }.prefix(6)
                if completed.isEmpty {
                    Text("Завершённые интервалы появятся после остановки учёта.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(completed)) { session in
                        HStack {
                            Text(session.startedAt, format: .dateTime.day().month().hour().minute())
                            Spacer()
                            Text(session.duration().appTimerText).monospacedDigit()
                            Button("Править") { editingSession = session }
                                .buttonStyle(.borderless)
                            Button("Удалить", role: .destructive) { store.deleteCompletedSession(session) }
                                .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            if period == .week {
                GroupBox("Неделя по дням") {
                    let calendar = Calendar.current
                    let weekStart = calendar.dateInterval(of: .weekOfYear, for: store.now)?.start ?? store.now
                    ForEach(0..<7, id: \.self) { offset in
                        let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                        let dayInterval = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 0)
                        let duration = ReportCalculator.sessions(in: dayInterval, from: store.sessions, now: store.now)
                            .reduce(0) { $0 + ReportCalculator.actualDuration(of: $1, clippedTo: dayInterval, now: store.now) }
                        HStack {
                            Text(day, format: .dateTime.weekday(.wide).day().month())
                            Spacer()
                            Text(duration.appTimerText).monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Text("Для режима «Полностью каждому» сумма по проектам может быть больше фактического времени.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
        .navigationTitle("Отчёты")
        .sheet(item: $editingSession) { SessionEditorSheet(session: $0) }
    }
}

@MainActor
private struct SettingsView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var launchAtLogin = LaunchAtLoginManager()
    @State private var hotKey = TrackingHotKeyManager()
    @State private var newFocusApplicationName = ""
    @State private var newFocusBundleIdentifier = ""
    @State private var confirmingPassiveHistoryDeletion = false

    var body: some View {
        Form {
            Section("Распределение времени") {
                Picker("Режим по умолчанию", selection: Binding(
                    get: { store.defaultAllocationMode },
                    set: { store.setDefaultAllocationMode($0) }
                )) {
                    ForEach(AllocationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(store.defaultAllocationMode.detail).font(.caption).foregroundStyle(.secondary)
            }
            Section("Быстрый доступ") {
                Toggle("Запускать AppTimer при входе в macOS", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                Toggle("Глобальная горячая клавиша \(hotKey.displayName)", isOn: Binding(
                    get: { hotKey.isEnabled },
                    set: { hotKey.setEnabled($0) }
                ))
                Text("Комбинация \(hotKey.displayName) запускает или останавливает учёт выбранных проектов из любого приложения.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = launchAtLogin.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Напоминания и пауза") {
                Toggle("Останавливать учёт при бездействии", isOn: Binding(
                    get: { store.idlePauseEnabled },
                    set: { store.setIdlePauseEnabled($0) }
                ))
                if store.idlePauseEnabled {
                    Stepper("Пауза через \(store.idlePauseMinutes) мин", value: Binding(
                        get: { store.idlePauseMinutes },
                        set: { store.setIdlePauseMinutes($0) }
                    ), in: 1...120)
                    Text("После отсутствия действий мышью или клавиатурой AppTimer завершит текущий интервал и пришлёт локальное уведомление.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Напоминать, когда проект не выбран", isOn: Binding(
                    get: { store.unassignedReminderEnabled },
                    set: { store.setUnassignedReminderEnabled($0) }
                ))
                if store.unassignedReminderEnabled {
                    Stepper("Напоминание через \(store.unassignedReminderMinutes) мин", value: Binding(
                        get: { store.unassignedReminderMinutes },
                        set: { store.setUnassignedReminderMinutes($0) }
                    ), in: 1...120)
                    Text("Напоминание появляется только при активном использовании Mac, когда учёт остановлен и ни один проект не выбран.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Focus Companion") {
                Toggle("Напоминать при длительном отвлечении", isOn: Binding(
                    get: { store.focusModeEnabled },
                    set: { store.setFocusModeEnabled($0) }
                ))
                if store.focusModeEnabled {
                    Stepper("Первое напоминание через \(store.distractionAlertMinutes) мин", value: Binding(
                        get: { store.distractionAlertMinutes },
                        set: { store.setDistractionAlertMinutes($0) }
                    ), in: 1...60)
                    Stepper("Повторять не чаще чем раз в \(store.distractionReminderCooldownMinutes) мин", value: Binding(
                        get: { store.distractionReminderCooldownMinutes },
                        set: { store.setDistractionReminderCooldownMinutes($0) }
                    ), in: 1...120)
                }
                Text("Проверка действует только во время ручного учёта. AppTimer показывает уведомление, но не блокирует приложения и не читает их содержимое.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Пассивная история приложений") {
                Toggle("Записывать контекст приложений вне учёта", isOn: Binding(
                    get: { store.passiveContextRecordingEnabled },
                    set: { store.setPassiveContextRecordingEnabled($0) }
                ))
                Text("По умолчанию выключено. При включении AppTimer локально сохраняет только имя активного приложения и bundle identifier, даже когда ручной учёт остановлен.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.passiveContextRecordingEnabled {
                    Picker("Срок хранения", selection: Binding(
                        get: { store.contextRetention },
                        set: { store.setContextRetention($0) }
                    )) {
                        ForEach(ContextHistoryRetention.allCases) { retention in
                            Text(retention.title).tag(retention)
                        }
                    }
                    Button("Удалить всю пассивную историю", role: .destructive) {
                        confirmingPassiveHistoryDeletion = true
                    }
                }
            }
            Section("Роли приложений") {
                if store.focusApplications.isEmpty {
                    Text("Список пополнится приложениями из локального контекста учёта. Их также можно добавить вручную ниже.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.focusApplications) { application in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(application.name).lineLimit(1)
                                Spacer()
                                Picker("Роль \(application.name)", selection: Binding(
                                    get: { application.role },
                                    set: { store.setFocusRole($0, for: application.bundleIdentifier, name: application.name) }
                                )) {
                                    ForEach(FocusApplicationRole.allCases) { role in
                                        Text(role.title).tag(role)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 150)
                            }
                            Text(application.bundleIdentifier)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                TextField("Название приложения", text: $newFocusApplicationName)
                TextField("Bundle identifier, например com.apple.Safari", text: $newFocusBundleIdentifier)
                Button("Добавить нейтральное приложение") {
                    store.setFocusRole(.neutral, for: newFocusBundleIdentifier, name: newFocusApplicationName)
                    newFocusApplicationName = ""
                    newFocusBundleIdentifier = ""
                }
                .disabled(newFocusBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Рабочие приложения формируют сводку концентрации. Отвлекающие приложения могут прислать напоминание; все остальные считаются нейтральными.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Приватность") {
                LabeledContent("Хранилище", value: "Только на этом Mac")
                LabeledContent("Контекст приложений", value: "Название и bundle identifier")
                Text("AppTimer не записывает содержимое окон, сайты, введённый текст или данные в облако.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Настройки")
        .confirmationDialog(
            "Удалить всю пассивную историю?",
            isPresented: $confirmingPassiveHistoryDeletion,
            titleVisibility: .visible
        ) {
            Button("Удалить историю", role: .destructive) {
                store.deletePassiveContextHistory()
            }
        } message: {
            Text("Будут удалены все локальные отрезки активных приложений. Ручные интервалы и проекты останутся без изменений.")
        }
    }
}

@MainActor
private struct ProjectDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTimerStore.self) private var store
    let project: Project
    @State private var clientName: String
    @State private var hourlyRate: String
    @State private var weeklyGoalHours: String

    init(project: Project) {
        self.project = project
        _clientName = State(initialValue: project.clientName ?? "")
        _hourlyRate = State(initialValue: project.hourlyRate.map { String(format: "%.0f", $0) } ?? "")
        _weeklyGoalHours = State(initialValue: project.weeklyGoalMinutes.map { String($0 / 60) } ?? "")
    }

    var body: some View {
        Form {
            TextField("Клиент", text: $clientName)
            TextField("Ставка в час", text: $hourlyRate)
            TextField("Цель часов в неделю", text: $weeklyGoalHours)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                Button("Сохранить") {
                    let rate = Double(hourlyRate.replacingOccurrences(of: ",", with: "."))
                    let goalMinutes = Int(weeklyGoalHours).map { $0 * 60 }
                    store.updateProject(project, clientName: clientName, hourlyRate: rate, weeklyGoalMinutes: goalMinutes)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private enum ReportPeriod: String, CaseIterable, Identifiable {
    case today, week, month
    var id: String { rawValue }
    var title: String { switch self { case .today: "День"; case .week: "Неделя"; case .month: "Месяц" } }
}

@MainActor
private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SummaryRow: Identifiable {
    let id = UUID()
    let name: String
    let primary: String
    let secondary: String?
    let color: Color
}

@MainActor
private struct SummaryList: View {
    let title: String
    let emptyText: String
    let rows: [SummaryRow]
    var body: some View {
        GroupBox(title) {
            if rows.isEmpty {
                Text(emptyText).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack {
                            Circle().fill(row.color).frame(width: 8, height: 8)
                            Text(row.name).lineLimit(1)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(row.primary).monospacedDigit()
                                if let secondary = row.secondary { Text(secondary).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }.padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? sizes.map(\.width).max() ?? 0
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0
        for size in sizes {
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}

extension Color {
    init(hex: String) {
        let value = Int(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}
