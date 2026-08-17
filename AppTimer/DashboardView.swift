// AppTimer Dashboard: local reports for today, projects, reports and allocation settings.
import SwiftUI

struct DashboardView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var selection: SidebarItem? = .today

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("AppTimer") {
                    Label("Сегодня", systemImage: "clock") .tag(SidebarItem.today)
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
            case .projects: ProjectsView()
            case .reports: ReportsView()
            case .settings: SettingsView()
            }
        }
    }
}

private enum SidebarItem: Hashable {
    case today, projects, reports, settings
}

private struct TodayView: View {
    @Environment(AppTimerStore.self) private var store

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
    }
}

private struct ProjectsView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var newProjectName = ""

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
    }

    private func addProject() {
        store.createProject(named: newProjectName)
        newProjectName = ""
    }
}

private struct ReportsView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var period: ReportPeriod = .today

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
                    CSVExporter.export(projects: rows, period: period.title)
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
    }
}

private struct SettingsView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var launchAtLogin = LaunchAtLoginManager()
    @State private var hotKey = TrackingHotKeyManager()

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
            Section("Приватность") {
                LabeledContent("Хранилище", value: "Только на этом Mac")
                LabeledContent("Контекст приложений", value: "Название и bundle identifier")
                Text("AppTimer не записывает содержимое окон, сайты, введённый текст или данные в облако.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Следующие возможности") {
                Text("Исключение приложений и экспорт CSV будут добавлены после проверки базового сценария учёта.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Настройки")
    }
}

private enum ReportPeriod: String, CaseIterable, Identifiable {
    case today, week, month
    var id: String { rawValue }
    var title: String { switch self { case .today: "День"; case .week: "Неделя"; case .month: "Месяц" } }
}

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
