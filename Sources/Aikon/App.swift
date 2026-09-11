import SwiftUI
import AppKit

/// Sets the Dock icon the moment the app finishes launching, so the brief
/// window where `SettingsWindowCoordinator` flips Aikon to `.regular` (to
/// show the Settings window) shows the drawn mark instead of a blank
/// generic icon — see `AppIcon`.
@MainActor
final class AikonAppDelegate: NSObject, NSApplicationDelegate {
    /// The model lives here rather than in `AikonApp`, because the menu bar is
    /// built from AppKit now and needs it before any scene exists.
    let model = PanelModel()
    private var statusBar: StatusBarController?
    private var settings: SettingsWindowCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIcon.image
        settings = SettingsWindowCoordinator(configStore: model.configStore)
        statusBar = StatusBarController(model: model)
    }

    /// Aikon lives in the menu bar and often has no window open at all. While
    /// `MenuBarExtra` was the scene holding the app up, that was implicit;
    /// with the status item built in AppKit, closing the last window would
    /// otherwise quit the app the moment Settings is dismissed — or the
    /// instant it launches, which is what it did.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// Not `@main` — entry is `main.swift`, which checks for the hidden
// `--render-screenshot` flag before handing off to `AikonApp.main()` below
// (the default the `App` protocol provides). Checking there, rather than
// here, matters: by the time any of `AikonApp`'s own code could run, the
// delegate has already put an icon in the menu bar.
struct AikonApp: App {
    @NSApplicationDelegateAdaptor(AikonAppDelegate.self) private var appDelegate

    var body: some Scene {
        // No `MenuBarExtra`: its label cannot hold coloured symbols next to
        // numbers, and no arrangement of images or text gets around that —
        // see `StatusItemLabel`. `StatusBarController` puts a live view in a
        // status item of its own instead, from `applicationDidFinishLaunching`.

        // No real scene either: the Settings window is AppKit's too — see
        // `SettingsWindowCoordinator`. An `App` needs one scene, and an empty
        // `Settings` is the one that shows nothing; its menu item is replaced
        // so ⌘, reaches the real window while Settings is open.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button(L.string("menu.settings")) {
                        NotificationCenter.default.post(name: .aikonOpenSettings, object: nil)
                    }
                    .keyboardShortcut(",")
                }
            }
    }
}
