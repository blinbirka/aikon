import SwiftUI
import AppKit

/// Sets the Dock icon the moment the app finishes launching, so the brief
/// window where `SettingsWindowCoordinator` flips Aikon to `.regular` (to
/// show the Settings window) shows the drawn mark instead of a blank
/// generic icon — see `AppIcon`.
final class AikonAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIcon.image
    }
}

@main
struct AikonApp: App {
    @NSApplicationDelegateAdaptor(AikonAppDelegate.self) private var appDelegate
    @StateObject private var model = PanelModel()

    var body: some Scene {
        // Exists only to host `@Environment(\.openSettings)` — see
        // `SettingsWindowCoordinator`. Must be declared before `Settings`
        // below so the environment value is available by the time the
        // menu's "Settings…" row can ask for it.
        Window("", id: "aikon-settings-opener") {
            SettingsWindowOpener()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)

        MenuBarExtra {
            MenuView(model: model)
        } label: {
            StatusItemLabel(counts: model.counts)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(configStore: model.configStore)
        }
    }
}
