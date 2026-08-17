// AppTimer workspace monitor: event-driven frontmost-app context without inspecting windows or input.
import AppKit
import Foundation

struct ActiveApplicationInfo: Equatable, Sendable {
    let bundleIdentifier: String
    let name: String
}

@MainActor
final class WorkspaceMonitor {
    var onApplicationChange: ((ActiveApplicationInfo?) -> Void)?
    var onSystemPause: (() -> Void)?
    private var observerTokens: [NSObjectProtocol] = []

    func start() {
        guard observerTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        observerTokens.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let info = Self.info(from: application)
            Task { @MainActor [weak self] in
                self?.onApplicationChange?(info)
            }
        })

        observerTokens.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onSystemPause?()
            }
        })

        observerTokens.append(center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onSystemPause?()
            }
        })

        onApplicationChange?(currentApplication)
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observerTokens.forEach(center.removeObserver)
        observerTokens.removeAll()
    }

    var currentApplication: ActiveApplicationInfo? {
        Self.info(from: NSWorkspace.shared.frontmostApplication)
    }

    private nonisolated static func info(from application: NSRunningApplication?) -> ActiveApplicationInfo? {
        guard let application,
              let bundleIdentifier = application.bundleIdentifier,
              let name = application.localizedName else { return nil }
        return ActiveApplicationInfo(bundleIdentifier: bundleIdentifier, name: name)
    }
}
