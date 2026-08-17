// AppTimer allocation engine: one source of truth for equal, full and weighted reporting.
import Foundation

enum AllocationEngine {
    static func weights(
        for projects: [Project],
        mode: AllocationMode,
        customWeights: [UUID: Double]
    ) -> [UUID: Double] {
        guard !projects.isEmpty else { return [:] }

        switch mode {
        case .equal:
            let equalWeight = 1.0 / Double(projects.count)
            return Dictionary(uniqueKeysWithValues: projects.map { ($0.id, equalWeight) })
        case .fullToEach:
            return Dictionary(uniqueKeysWithValues: projects.map { ($0.id, 1.0) })
        case .customWeights:
            let requested = projects.map { customWeights[$0.id] ?? 0 }
            let total = requested.reduce(0, +)
            guard total > 0 else {
                return weights(for: projects, mode: .equal, customWeights: [:])
            }
            return Dictionary(uniqueKeysWithValues: projects.enumerated().map { index, project in
                (project.id, requested[index] / total)
            })
        }
    }

    static func percentage(for projectID: UUID, in projects: [Project], mode: AllocationMode, customWeights: [UUID: Double]) -> Int {
        let weight = weights(for: projects, mode: mode, customWeights: customWeights)[projectID] ?? 0
        return Int((weight * 100).rounded())
    }
}
