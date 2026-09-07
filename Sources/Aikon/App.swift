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

// Not `@main` — entry is `main.swift`, which checks for the hidden
// `--render-screenshot` flag before handing off to `AikonApp.main()` below
// (the default the `App` protocol provides). Checking there, rather than
// here, matters: by the time any of `AikonApp`'s own code could run, SwiftUI
// has already built the `MenuBarExtra` scene and put an icon in the menu bar.
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
            // A drawn image, not the view itself: MenuBarExtra reduces a
            // composed label and strips its colour. See `StatusItemLabel`.
            if let image = model.statusImage {
                Image(nsImage: image)
            } else {
                Text("\(model.counts.waiting)  \(model.counts.done)  \(model.counts.busy)")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(configStore: model.configStore)
        }
    }
}
