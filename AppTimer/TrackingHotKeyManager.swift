// AppTimer global shortcut: ⌥⌘T toggles the selected project's active timer.
import Carbon
import Foundation

private let appTimerHotKeySignature: OSType = 0x4150544D // APTM
private let appTimerHotKeyIdentifier: UInt32 = 1

private func appTimerHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return noErr }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard status == noErr, identifier.signature == appTimerHotKeySignature, identifier.id == appTimerHotKeyIdentifier else { return noErr }
    DispatchQueue.main.async { TrackingHotKeyManager.shared?.onPress?() }
    return noErr
}

@MainActor
final class TrackingHotKeyManager {
    static weak var shared: TrackingHotKeyManager?
    var onPress: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let enabledKey = "trackingHotKeyEnabled"

    var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    var displayName: String { "⌥⌘T" }

    init() {
        Self.shared = self
        installHandler()
        if isEnabled { register() }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        enabled ? register() : unregister()
    }

    private func installHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        _ = InstallEventHandler(GetApplicationEventTarget(), appTimerHotKeyHandler, 1, &type, nil, &handler)
    }

    private func register() {
        guard reference == nil else { return }
        var newReference: EventHotKeyRef?
        let id = EventHotKeyID(signature: appTimerHotKeySignature, id: appTimerHotKeyIdentifier)
        guard RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &newReference) == noErr else { return }
        reference = newReference
    }

    private func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }
}
