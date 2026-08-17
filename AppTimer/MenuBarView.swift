// AppTimer Menu Bar: manual multi-project selection and direct control of the active local timer.
import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var newProjectName = ""
    let onShowDashboard: () -> Void

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FocusPulseIndicator(state: store.focusPulseState, progress: store.focusSessionProgress)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.focusPulseState.title)
                        .font(.headline)
                    Text(store.hasActiveFocusSession ? "До паузы: \(store.focusSessionRemaining.appTimerCompactText)" : store.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(store.hasActiveFocusSession ? store.focusSessionRemaining.appTimerCompactText : store.elapsedText)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(pulseColor)
            }

            Divider()

            if !store.recentProjects.isEmpty {
                Text("Недавние проекты").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(store.recentProjects) { project in
                    Button { store.selectRecentProject(project) } label: {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: project.colorHex)).frame(width: 8, height: 8)
                            Text(project.name).lineLimit(1)
                            Spacer()
                            if store.selectedProjectIDs == [project.id] {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }

            Text("Текущие проекты").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            if store.projects.filter({ !$0.isArchived }).isEmpty {
                ContentUnavailableView("Создайте первый проект", systemImage: "folder.badge.plus", description: Text("Затем выберите его для начала учёта."))
                    .frame(height: 120)
            } else {
                ForEach(store.projects.filter { !$0.isArchived }) { project in
                    Toggle(isOn: Binding(
                        get: { store.selectedProjectIDs.contains(project.id) },
                        set: { _ in store.toggleProject(project) }
                    )) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: project.colorHex)).frame(width: 8, height: 8)
                            Text(project.name)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            HStack {
                TextField("Новый проект", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addProject)
                Button(action: addProject) { Image(systemName: "plus") }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Фокус-блок", systemImage: "scope")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let preset = store.activeFocusPreset {
                        Text(preset.title).font(.caption.monospacedDigit()).foregroundStyle(pulseColor)
                    }
                }
                if store.hasActiveFocusSession {
                    HStack {
                        Text("Один проект, без переключений")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Отменить") { store.cancelFocusSession() }
                            .buttonStyle(.borderless)
                    }
                } else {
                    HStack(spacing: 7) {
                        ForEach(FocusSessionPreset.allCases) { preset in
                            Button(preset.title) { store.startFocusSession(preset) }
                                .buttonStyle(.bordered)
                                .tint(.cyan)
                                .disabled(store.selectedProjectIDs.isEmpty)
                        }
                    }
                }
            }

            Divider()
            Picker("Распределение", selection: Binding(
                get: { store.selectedAllocationMode },
                set: { store.changeAllocationMode(to: $0) }
            )) {
                ForEach(AllocationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if store.selectedAllocationMode == .customWeights, !store.selectedProjects.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Ручные доли").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(store.selectedProjects) { project in
                        HStack {
                            Text(project.name).lineLimit(1)
                            Spacer()
                            TextField("%", value: Binding(
                                get: { (store.customWeights[project.id] ?? 0) * 100 },
                                set: { store.updateCustomWeight(for: project, percent: $0 / 100) }
                            ), format: .number.precision(.fractionLength(0)))
                            .frame(width: 48)
                            .multilineTextAlignment(.trailing)
                            Text("%")
                        }
                    }
                }
            }

            Button(store.isTracking ? "Остановить учёт" : "Начать учёт") {
                store.startOrStopTracking()
            }
            .buttonStyle(.borderedProminent)
            .tint(store.isTracking ? .red : .blue)
            .frame(maxWidth: .infinity)
            .disabled(!store.isTracking && store.selectedProjectIDs.isEmpty)

            Divider()
            HStack {
                Button("Показать Dashboard", action: onShowDashboard)
                Spacer()
                Button("Выйти") { NSApp.terminate(nil) }
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 330)
    }

    private func addProject() {
        store.createProject(named: newProjectName)
        newProjectName = ""
    }
}

private struct FocusPulseIndicator: View {
    let state: FocusPulseState
    let progress: Double

    private var color: Color {
        switch state {
        case .resting: .secondary
        case .tracking: .blue
        case .focused: .cyan
        case .distracted: .orange
        case .completed: .green
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 4)
            if state == .focused {
                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().fill(color.opacity(0.16))
            }
            Image(systemName: state.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 34, height: 34)
        .animation(.easeInOut(duration: 0.25), value: state.rawValue)
        .animation(.linear(duration: 0.8), value: progress)
        .accessibilityLabel("Focus Pulse: \(state.title)")
    }
}
