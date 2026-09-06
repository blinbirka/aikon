import Foundation
import ServiceManagement

/// Whether Aikon starts automatically on login. Backed by
/// `SMAppService.mainApp` — the standard macOS 13+ way to register a login
/// item without a `~/Library/LaunchAgents` plist.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
