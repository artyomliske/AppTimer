// AppTimer SwiftData schema: versioned before the timeline changes introduce new persisted models.
import SwiftData

enum AppTimerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Project.self, WorkSession.self, SessionProjectAllocation.self, AppSegment.self]
    }
}

enum AppTimerSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    // ContextSegment is independent from WorkSession. Its addition is an additive, lightweight migration.
    static var models: [any PersistentModel.Type] {
        [Project.self, WorkSession.self, SessionProjectAllocation.self, AppSegment.self, ContextSegment.self]
    }
}

enum AppTimerSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        // Each migration-plan entry must have a distinct model checksum. V2 had the same
        // physical model shape as V1, so keeping both made Core Data abort before migration.
        // Existing V1/V2 stores share that legacy checksum and migrate directly to V3.
        [AppTimerSchemaV1.self, AppTimerSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: AppTimerSchemaV1.self, toVersion: AppTimerSchemaV3.self)
        ]
    }
}

enum AppTimerSchema {
    static let current = Schema(AppTimerSchemaV3.models)
}
