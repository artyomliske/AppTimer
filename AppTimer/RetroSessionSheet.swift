// AppTimer retro annotation: turns a selected Timeline range into a local WorkSession with explicit conflict handling.
import SwiftUI

struct RetroSessionDraft: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
}

@MainActor
struct RetroSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTimerStore.self) private var store
    let draft: RetroSessionDraft
    @State private var start: Date
    @State private var end: Date
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var allocationMode: AllocationMode = .equal
    @State private var conflictResolution: RetroSessionConflictResolution = .trimExisting
    @State private var appeared = false

    init(draft: RetroSessionDraft) {
        self.draft = draft
        _start = State(initialValue: draft.start)
        _end = State(initialValue: draft.end)
    }

    private var conflicts: [WorkSession] {
        store.retroSessionConflicts(start: start, end: end)
    }

    var body: some View {
        Form {
            Section("Диапазон") {
                DatePicker("Начало", selection: $start)
                DatePicker("Окончание", selection: $end, in: start...store.now)
            }

            Section("Проекты") {
                if store.projects.filter({ !$0.isArchived }).isEmpty {
                    Text("Сначала создайте активный проект.").foregroundStyle(.secondary)
                } else {
                    ForEach(store.projects.filter { !$0.isArchived }) { project in
                        Toggle(project.name, isOn: Binding(
                            get: { selectedProjectIDs.contains(project.id) },
                            set: { selected in
                                if selected { selectedProjectIDs.insert(project.id) }
                                else { selectedProjectIDs.remove(project.id) }
                            }
                        ))
                    }
                }
                Picker("Распределение", selection: $allocationMode) {
                    ForEach(AllocationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            if !conflicts.isEmpty {
                Section("Пересечение с существующей разметкой") {
                    Text("Найдено интервалов: \(conflicts.count). Новая разметка не будет наложена поверх них без явного решения.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Действие", selection: $conflictResolution) {
                        Text("Обрезать существующие").tag(RetroSessionConflictResolution.trimExisting)
                        Text("Заменить существующие").tag(RetroSessionConflictResolution.replaceExisting)
                    }
                    Text(conflictResolution == .trimExisting
                         ? "Существующие интервалы будут сокращены или разделены вокруг нового диапазона."
                         : "Пересекающиеся существующие интервалы и их ручные сегменты будут удалены.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                Button("Создать разметку") {
                    let resolution: RetroSessionConflictResolution? = conflicts.isEmpty ? nil : conflictResolution
                    if store.createRetroSession(
                        start: start,
                        end: end,
                        projectIDs: selectedProjectIDs,
                        allocationMode: allocationMode,
                        resolution: resolution
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProjectIDs.isEmpty || end <= start || end > store.now)
            }
        }
        .padding(24)
        .frame(width: 460)
        .navigationTitle("Разметить время")
        .onAppear {
            guard !appeared else { return }
            appeared = true
            selectedProjectIDs = store.selectedProjectIDs
            allocationMode = store.selectedAllocationMode
        }
    }
}
