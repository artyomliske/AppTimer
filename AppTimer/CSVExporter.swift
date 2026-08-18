// AppTimer CSV export: writes a UTF-8 project summary with client and billing columns.
import AppKit
import Foundation

@MainActor
enum CSVExporter {
    static func export(projects: [ProjectDuration], catalog: [UUID: Project], period: String) {
        let header = L10n.text("csv.header")
        let rows = projects.map { row in
            let project = catalog[row.id]
            let rate = project?.hourlyRate ?? 0
            let amount = rate > 0 ? (row.allocated / 3600.0) * rate : 0
            return [
                escape(period),
                escape(row.name),
                escape(project?.clientName ?? ""),
                String(format: "%.2f", rate),
                String(Int(row.actual)),
                String(Int(row.allocated)),
                String(format: "%.2f", amount)
            ].joined(separator: ",")
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
