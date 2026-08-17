// AppTimer CSV export: writes a UTF-8 project summary through the standard macOS save panel.
import AppKit
import Foundation

@MainActor
enum CSVExporter {
    static func export(projects: [ProjectDuration], period: String) {
        let header = "Период,Проект,Фактическое время (сек),Распределённое время (сек)"
        let rows = projects.map { row in
            [escape(period), escape(row.name), String(Int(row.actual)), String(Int(row.allocated))].joined(separator: ",")
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "AppTimer-\(period).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ([header] + rows).joined(separator: "\n").data(using: .utf8)?.write(to: url)
    }

    private static func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
