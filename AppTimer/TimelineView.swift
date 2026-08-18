// AppTimer Timeline: read-only daily visualization of opt-in local app context and manual annotations.
import SwiftUI

@MainActor
struct TimelineView: View {
    @Environment(AppTimerStore.self) private var store
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: selectedDay) ?? DateInterval(start: selectedDay, duration: 86_400)
    }

    private var contextSegments: [ContextSegment] {
        store.contextSegments
            .filter { TimelineGeometry.intersects(start: $0.startedAt, end: $0.endedAt ?? store.now, interval: dayInterval) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private var sessions: [WorkSession] {
        store.sessions
            .filter { TimelineGeometry.intersects(start: $0.startedAt, end: $0.endedAt ?? store.now, interval: dayInterval) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !store.passiveContextRecordingEnabled {
                    ContentUnavailableView(
                        "Пассивная история выключена",
                        systemImage: "hand.raised.fill",
                        description: Text("Включите запись контекста приложений в настройках, чтобы видеть локальную ленту дня. AppTimer сохранит только имя приложения и bundle identifier."))
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    TimelineCanvas(
                        dayInterval: dayInterval,
                        now: store.now,
                        contextSegments: contextSegments,
                        sessions: sessions
                    )
                    .frame(height: 250)

                    HStack(alignment: .top, spacing: 14) {
                        legend("Контекст приложений", color: .secondary)
                        legend("Ручная разметка проектов", color: .accentColor)
                        Spacer()
                        Text("Только этот Mac · срок хранения: \(store.contextRetention.title)")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    GroupBox("Отрезки дня") {
                        if contextSegments.isEmpty {
                            Text("Для выбранного дня нет сохранённого контекста приложений.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 90)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(contextSegments) { segment in
                                    HStack(spacing: 10) {
                                        Circle().fill(TimelineGeometry.color(for: segment.bundleIdentifier)).frame(width: 8, height: 8)
                                        Text(segment.appName).lineLimit(1)
                                        Spacer()
                                        Text("\(segment.startedAt.formatted(date: .omitted, time: .shortened)) – \((segment.endedAt ?? store.now).formatted(date: .omitted, time: .shortened))")
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        Text(TimelineGeometry.duration(start: segment.startedAt, end: segment.endedAt ?? store.now, in: dayInterval).appTimerText)
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Таймлайн")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Таймлайн").font(.largeTitle.bold())
                Text("Локальная лента приложений и ручной разметки за день.").foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { shiftDay(by: -1) } label: { Image(systemName: "chevron.left") }
                Button("Сегодня") { selectedDay = Calendar.current.startOfDay(for: store.now) }
                Button { shiftDay(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.bordered)
        }
        .overlay(alignment: .bottomLeading) {
            Text(selectedDay, format: .dateTime.weekday(.wide).day().month().year())
                .font(.title3.weight(.semibold))
                .offset(y: 34)
        }
        .padding(.bottom, 18)
    }

    private func legend(_ title: String, color: Color) -> some View {
        Label(title, systemImage: "rectangle.fill")
            .font(.caption)
            .foregroundStyle(color)
    }

    private func shiftDay(by value: Int) {
        selectedDay = Calendar.current.date(byAdding: .day, value: value, to: selectedDay) ?? selectedDay
    }
}

@MainActor
private struct TimelineCanvas: View {
    let dayInterval: DateInterval
    let now: Date
    let contextSegments: [ContextSegment]
    let sessions: [WorkSession]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary.opacity(0.45))

                ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { hour in
                    let x = width * CGFloat(hour) / 24
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 26))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height - 16))
                    }
                    .stroke(.secondary.opacity(0.18), lineWidth: 1)
                    Text(String(format: "%02d:00", hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .position(x: min(max(x + 18, 20), width - 20), y: 13)
                }

                Text("Приложения").font(.caption.weight(.medium)).foregroundStyle(.secondary).position(x: 38, y: 47)
                Text("Проекты").font(.caption.weight(.medium)).foregroundStyle(.secondary).position(x: 32, y: 136)

                ForEach(contextSegments) { segment in
                    segmentBar(
                        start: segment.startedAt,
                        end: segment.endedAt ?? now,
                        label: segment.appName,
                        color: TimelineGeometry.color(for: segment.bundleIdentifier),
                        y: 62,
                        width: width
                    )
                }

                ForEach(sessions) { session in
                    let label = session.allocations.compactMap { $0.project?.name }.joined(separator: ", ")
                    segmentBar(
                        start: session.startedAt,
                        end: session.endedAt ?? now,
                        label: label.isEmpty ? "Без проекта" : label,
                        color: TimelineGeometry.projectColor(for: session),
                        y: 151,
                        width: width
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Лента дня с контекстом приложений и ручными проектными сессиями")
    }

    @ViewBuilder
    private func segmentBar(start: Date, end: Date, label: String, color: Color, y: CGFloat, width: CGFloat) -> some View {
        let frame = TimelineGeometry.frame(start: start, end: end, in: dayInterval, width: width)
        if frame.width > 1 {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(0.78))
                .frame(width: frame.width, height: 46)
                .overlay(alignment: .leading) {
                    if frame.width > 72 {
                        Text(label).lineLimit(1).font(.caption.weight(.medium)).foregroundStyle(.white).padding(.horizontal, 8)
                    }
                }
                .position(x: frame.midX, y: y + 25)
                .help("\(label): \(TimelineGeometry.duration(start: start, end: end, in: dayInterval).appTimerText)")
        }
    }
}

private enum TimelineGeometry {
    static func intersects(start: Date, end: Date, interval: DateInterval) -> Bool {
        end > interval.start && start < interval.end
    }

    static func duration(start: Date, end: Date, in interval: DateInterval) -> TimeInterval {
        max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start)))
    }

    static func frame(start: Date, end: Date, in interval: DateInterval, width: CGFloat) -> CGRect {
        let clippedStart = max(start, interval.start)
        let clippedEnd = min(end, interval.end)
        let leading = max(0, min(1, clippedStart.timeIntervalSince(interval.start) / interval.duration))
        let trailing = max(leading, min(1, clippedEnd.timeIntervalSince(interval.start) / interval.duration))
        return CGRect(x: width * leading, y: 0, width: max(2, width * (trailing - leading)), height: 1)
    }

    static func color(for identifier: String) -> Color {
        let colors: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .mint]
        let index = abs(identifier.unicodeScalars.reduce(0) { $0 + Int($1.value) }) % colors.count
        return colors[index]
    }

    static func projectColor(for session: WorkSession) -> Color {
        guard let hex = session.allocations.compactMap({ $0.project?.colorHex }).first else { return .gray }
        let value = Int(hex, radix: 16) ?? 0
        return Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}
