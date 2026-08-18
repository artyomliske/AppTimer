// AppTimer Menu Bar: manual multi-project selection and direct control of the active local timer.
import AppKit
import SwiftUI

@MainActor
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(MenuVisual.blue.opacity(0.12))
                    FocusPulseIndicator(state: store.focusPulseState, progress: store.focusSessionProgress)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AppTimer · \(store.focusPulseState.title)")
                        .font(.headline.weight(.bold))
                    Text(store.hasActiveFocusSession ? "До паузы: \(store.focusSessionRemaining.appTimerCompactText)" : store.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(store.hasActiveFocusSession ? store.focusSessionRemaining.appTimerCompactText : store.elapsedText)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(pulseColor)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MenuVisual.blue.opacity(0.14), lineWidth: 1) }

            if !store.recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Недавние проекты").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(store.recentProjects) { project in
                        Button { store.selectRecentProject(project) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(Color(hex: project.colorHex)).frame(width: 8, height: 8)
                                Text(project.name).lineLimit(1)
                                Spacer()
                                if store.selectedProjectIDs == [project.id] {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(MenuVisual.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(MenuVisual.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Текущие проекты").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(store.selectedProjectIDs.count) выбрано").font(.caption2).foregroundStyle(MenuVisual.blue)
                }

                if store.projects.filter({ !$0.isArchived }).isEmpty {
                    ContentUnavailableView("Создайте первый проект", systemImage: "folder.badge.plus", description: Text("Затем выберите его для начала учёта."))
                        .frame(height: 120)
                } else {
                    ForEach(store.projects.filter { !$0.isArchived }) { project in
                        Toggle(isOn: Binding(
                            get: { store.selectedProjectIDs.contains(project.id) },
                            set: { _ in store.toggleProject(project) }
                        )) {
                            HStack(spacing: 9) {
                                Circle().fill(Color(hex: project.colorHex)).frame(width: 10, height: 10)
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
            }
            .padding(13)
            .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

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
                                .tint(MenuVisual.blue)
                                .disabled(store.selectedProjectIDs.isEmpty)
                        }
                    }
                }
            }
            .padding(13)
            .background(MenuVisual.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

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
            .controlSize(.large)
            .tint(store.isTracking ? .red : MenuVisual.blue)
            .frame(maxWidth: .infinity)
            .disabled(!store.isTracking && store.selectedProjectIDs.isEmpty)

            HStack {
                Button("Показать Dashboard", action: onShowDashboard)
                Spacer()
                Button("Выйти") { NSApp.terminate(nil) }
            }
            .font(.caption)
        }
        .padding(18)
        .frame(width: 360)
        .background(MenuVisual.surface)
    }

    private func addProject() {
        store.createProject(named: newProjectName)
        newProjectName = ""
    }
}

@MainActor
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

private enum MenuVisual {
    static let blue = Color(red: 0.13, green: 0.42, blue: 0.95)
    static let surface = Color.primary.opacity(0.015)
}
