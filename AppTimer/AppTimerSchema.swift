// AppTimer SwiftData schema: versioned before the timeline changes introduce new persisted models.
import SwiftData

enum AppTimerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Project.self, WorkSession.self, SessionProjectAllocation.self, AppSegment.self]
    }
}

enum AppTimerSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    // V2 intentionally has the same persisted shape as V1. It establishes an explicit migration boundary
    // before the Timeline phase adds new model types or fields.
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
        [AppTimerSchemaV1.self, AppTimerSchemaV2.self, AppTimerSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: AppTimerSchemaV1.self, toVersion: AppTimerSchemaV2.self),
            .lightweight(fromVersion: AppTimerSchemaV2.self, toVersion: AppTimerSchemaV3.self)
        ]
    }
}

enum AppTimerSchema {
    static let current = Schema(AppTimerSchemaV3.models)
}
