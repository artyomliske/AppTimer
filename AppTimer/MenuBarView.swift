// AppTimer Menu Bar: manual multi-project selection and direct control of the active local timer.
import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var newProjectName = ""
    let onShowDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isTracking ? "Идёт учёт" : "AppTimer")
                        .font(.headline)
                    Text(store.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.elapsedText)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(store.isTracking ? .blue : .secondary)
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
