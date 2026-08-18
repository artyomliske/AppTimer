// AppTimer launch-at-login: explicit user-controlled registration through ServiceManagement.
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    var errorMessage: String?

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = L10n.format("error.launch_at_login", error.localizedDescription)
        }
    }
}
