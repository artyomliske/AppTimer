import SwiftUI

struct SessionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTimerStore.self) private var store
    let session: WorkSession
    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var note: String

    init(session: WorkSession) {
        self.session = session
        _startedAt = State(initialValue: session.startedAt)
        _endedAt = State(initialValue: session.endedAt ?? .now)
        _note = State(initialValue: session.note ?? "")
    }

    var body: some View {
        Form {
            DatePicker("Начало", selection: $startedAt)
            DatePicker("Окончание", selection: $endedAt, in: startedAt...)
            TextField("Комментарий", text: $note, axis: .vertical).lineLimit(3...6)
            HStack { Spacer(); Button("Отмена") { dismiss() }; Button("Сохранить") { store.updateCompletedSession(session, startedAt: startedAt, endedAt: endedAt, note: note); dismiss() }.buttonStyle(.borderedProminent) }
        }
        .padding(24).frame(width: 430).navigationTitle("Интервал")
    }
}
