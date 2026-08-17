// AppTimer app shell: a dockless local SwiftData application with Menu Bar and on-demand Dashboard.
import SwiftData
import SwiftUI

@main
struct AppTimerApp: App {
    @State private var store = AppTimerStore()
    @State private var dashboardController = DashboardPanelController()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            WorkSession.self,
            SessionProjectAllocation.self,
            AppSegment.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Не удалось открыть локальное хранилище AppTimer: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra("AppTimer", systemImage: store.isTracking ? "timer.circle.fill" : "timer.circle") {
            MenuBarRootView {
                dashboardController.show(store: store, modelContainer: sharedModelContainer)
            }
                .environment(store)
                .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTimerStore.self) private var store
    let showDashboard: () -> Void

    var body: some View {
        MenuBarView(onShowDashboard: showDashboard)
            .task { store.configure(with: modelContext) }
    }
}
