// AppTimer Dashboard panel: an on-demand AppKit window for a dockless menu-bar application.
import AppKit
import SwiftData
import SwiftUI

@MainActor
final class DashboardPanelController {
    private var panel: NSPanel?

    func show(store: AppTimerStore, modelContainer: ModelContainer) {
        if panel == nil {
            let rootView = DashboardView()
                .environment(store)
                .modelContainer(modelContainer)
            let hostingController = NSHostingController(rootView: rootView)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 650),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hostingController
            panel.title = "AppTimer"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.center()
            self.panel = panel
        }

        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}
