// AppTimer settings: typed, observable local preferences backed by existing UserDefaults keys.
import Foundation
import Observation

@MainActor
@Observable
final class AppTimerSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var defaultAllocationMode: AllocationMode {
        didSet { defaults.set(defaultAllocationMode.rawValue, forKey: Key.defaultAllocationMode) }
    }
    var excludedBundleIdentifiers: Set<String> {
        didSet { defaults.set(excludedBundleIdentifiers.sorted(), forKey: Key.excludedBundleIdentifiers) }
    }
    var idlePauseEnabled: Bool {
        didSet { defaults.set(idlePauseEnabled, forKey: Key.idlePauseEnabled) }
    }
    var idlePauseMinutes: Int {
        didSet { persistMinimum(idlePauseMinutes, key: Key.idlePauseMinutes, assign: { self.idlePauseMinutes = $0 }) }
    }
    var unassignedReminderEnabled: Bool {
        didSet { defaults.set(unassignedReminderEnabled, forKey: Key.unassignedReminderEnabled) }
    }
    var unassignedReminderMinutes: Int {
        didSet { persistMinimum(unassignedReminderMinutes, key: Key.unassignedReminderMinutes, assign: { self.unassignedReminderMinutes = $0 }) }
    }
    var focusModeEnabled: Bool {
        didSet { defaults.set(focusModeEnabled, forKey: Key.focusModeEnabled) }
    }
    var distractionAlertMinutes: Int {
        didSet { persistMinimum(distractionAlertMinutes, key: Key.distractionAlertMinutes, assign: { self.distractionAlertMinutes = $0 }) }
    }
    var distractionReminderCooldownMinutes: Int {
        didSet { persistMinimum(distractionReminderCooldownMinutes, key: Key.distractionReminderCooldownMinutes, assign: { self.distractionReminderCooldownMinutes = $0 }) }
    }
    var workBundleIdentifiers: Set<String> {
        didSet { defaults.set(workBundleIdentifiers.sorted(), forKey: Key.workBundleIdentifiers) }
    }
    var distractingBundleIdentifiers: Set<String> {
        didSet { defaults.set(distractingBundleIdentifiers.sorted(), forKey: Key.distractingBundleIdentifiers) }
    }
    var recentProjectIDs: [UUID] {
        didSet { defaults.set(recentProjectIDs.map(\.uuidString), forKey: Key.recentProjectIDs) }
    }
    var focusApplicationNames: [String: String] {
        didSet { defaults.set(focusApplicationNames, forKey: Key.focusApplicationNames) }
    }
    var passiveContextRecordingEnabled: Bool {
        didSet { defaults.set(passiveContextRecordingEnabled, forKey: Key.passiveContextRecordingEnabled) }
    }
    var contextRetention: ContextHistoryRetention {
        didSet { defaults.set(contextRetention.rawValue, forKey: Key.contextRetentionDays) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultAllocationMode = AllocationMode(rawValue: defaults.string(forKey: Key.defaultAllocationMode) ?? AllocationMode.equal.rawValue) ?? .equal
        excludedBundleIdentifiers = Set(defaults.stringArray(forKey: Key.excludedBundleIdentifiers) ?? [])
        idlePauseEnabled = defaults.object(forKey: Key.idlePauseEnabled) as? Bool ?? true
        idlePauseMinutes = Self.minimum(defaults.object(forKey: Key.idlePauseMinutes) as? Int ?? 10)
        unassignedReminderEnabled = defaults.object(forKey: Key.unassignedReminderEnabled) as? Bool ?? true
        unassignedReminderMinutes = Self.minimum(defaults.object(forKey: Key.unassignedReminderMinutes) as? Int ?? 15)
        focusModeEnabled = defaults.object(forKey: Key.focusModeEnabled) as? Bool ?? false
        distractionAlertMinutes = Self.minimum(defaults.object(forKey: Key.distractionAlertMinutes) as? Int ?? 5)
        distractionReminderCooldownMinutes = Self.minimum(defaults.object(forKey: Key.distractionReminderCooldownMinutes) as? Int ?? 15)
        workBundleIdentifiers = Set(defaults.stringArray(forKey: Key.workBundleIdentifiers) ?? [])
        distractingBundleIdentifiers = Set(defaults.stringArray(forKey: Key.distractingBundleIdentifiers) ?? [])
        recentProjectIDs = (defaults.stringArray(forKey: Key.recentProjectIDs) ?? []).compactMap(UUID.init(uuidString:))
        focusApplicationNames = defaults.dictionary(forKey: Key.focusApplicationNames) as? [String: String] ?? [:]
        passiveContextRecordingEnabled = defaults.object(forKey: Key.passiveContextRecordingEnabled) as? Bool ?? false
        contextRetention = ContextHistoryRetention(rawValue: defaults.object(forKey: Key.contextRetentionDays) as? Int ?? ContextHistoryRetention.days30.rawValue) ?? .days30
    }

    func writeHeartbeat(sessionID: UUID, at date: Date) {
        defaults.set(sessionID.uuidString, forKey: Key.heartbeatSessionID)
        defaults.set(date, forKey: Key.heartbeatDate)
    }

    func heartbeat() -> (sessionID: UUID, date: Date)? {
        guard let rawID = defaults.string(forKey: Key.heartbeatSessionID),
              let sessionID = UUID(uuidString: rawID),
              let date = defaults.object(forKey: Key.heartbeatDate) as? Date else {
            return nil
        }
        return (sessionID, date)
    }

    func clearHeartbeat(for sessionID: UUID) {
        guard heartbeat()?.sessionID == sessionID else { return }
        defaults.removeObject(forKey: Key.heartbeatSessionID)
        defaults.removeObject(forKey: Key.heartbeatDate)
    }

    func writeContextHeartbeat(segmentID: UUID, at date: Date) {
        defaults.set(segmentID.uuidString, forKey: Key.contextHeartbeatSegmentID)
        defaults.set(date, forKey: Key.contextHeartbeatDate)
    }

    func contextHeartbeat() -> (segmentID: UUID, date: Date)? {
        guard let rawID = defaults.string(forKey: Key.contextHeartbeatSegmentID),
              let segmentID = UUID(uuidString: rawID),
              let date = defaults.object(forKey: Key.contextHeartbeatDate) as? Date else {
            return nil
        }
        return (segmentID, date)
    }

    func clearContextHeartbeat(for segmentID: UUID? = nil) {
        if let segmentID, contextHeartbeat()?.segmentID != segmentID { return }
        defaults.removeObject(forKey: Key.contextHeartbeatSegmentID)
        defaults.removeObject(forKey: Key.contextHeartbeatDate)
    }

    private func persistMinimum(_ value: Int, key: String, assign: (Int) -> Void) {
        let sanitized = Self.minimum(value)
        if sanitized != value {
            assign(sanitized)
        } else {
            defaults.set(sanitized, forKey: key)
        }
    }

    private static func minimum(_ value: Int) -> Int { max(1, value) }

    private enum Key {
        static let defaultAllocationMode = "defaultAllocationMode"
        static let excludedBundleIdentifiers = "excludedBundleIdentifiers"
        static let idlePauseEnabled = "idlePauseEnabled"
        static let idlePauseMinutes = "idlePauseMinutes"
        static let unassignedReminderEnabled = "unassignedReminderEnabled"
        static let unassignedReminderMinutes = "unassignedReminderMinutes"
        static let focusModeEnabled = "focusModeEnabled"
        static let distractionAlertMinutes = "distractionAlertMinutes"
        static let distractionReminderCooldownMinutes = "distractionReminderCooldownMinutes"
        static let workBundleIdentifiers = "focusWorkBundleIdentifiers"
        static let distractingBundleIdentifiers = "focusDistractingBundleIdentifiers"
        static let recentProjectIDs = "recentProjectIDs"
        static let focusApplicationNames = "focusApplicationNames"
        static let heartbeatSessionID = "activeSessionHeartbeatID"
        static let heartbeatDate = "activeSessionHeartbeatDate"
        static let passiveContextRecordingEnabled = "passiveContextRecordingEnabled"
        static let contextRetentionDays = "contextRetentionDays"
        static let contextHeartbeatSegmentID = "contextHeartbeatSegmentID"
        static let contextHeartbeatDate = "contextHeartbeatDate"
    }
}
