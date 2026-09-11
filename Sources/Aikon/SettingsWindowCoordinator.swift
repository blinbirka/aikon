import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted by the menu's "Settings…" row (and the ⌘, command) and handled
    /// by `SettingsWindowCoordinator`, which owns the Settings window.
    static let aikonOpenSettings = Notification.Name("aikonOpenSettings")
    /// Asks the menu to close itself — posted by rows that are about to
    /// open a window, handled in `StatusBarController`.
    static let aikonClosePanel = Notification.Name("aikonClosePanel")
}

/// Owns the Settings window, built in AppKit like the status item.
///
/// It used to be SwiftUI's `Settings` scene, opened through `openSettings`
/// read off an invisible `Window` scene. That held only while the invisible
/// window was alive and SwiftUI agreed to show its Settings window again:
/// in practice Settings opened once per launch and never after it was
/// closed, and a copy that had been running for two days had lost the
/// invisible window altogether. Owning the window outright leaves nothing
/// to lose.
///
/// Aikon is `LSUIElement`, with no Dock icon, and an accessory app can't
/// hand a window keyboard focus. So the activation policy goes to `.regular`
/// while the window is open and back to `.accessory` once it closes.
@MainActor
final class SettingsWindowCoordinator: NSObject, NSWindowDelegate {
    private let configStore: ConfigStore
    private var window: NSWindow?
    private var observer: NSObjectProtocol?

    init(configStore: ConfigStore) {
        self.configStore = configStore
        super.init()
        observer = NotificationCenter.default.addObserver(
            forName: .aikonOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Reverts to `.accessory` the moment the window closes — not on losing
    /// focus, so switching to another app while Settings stays open doesn't
    /// hide the Dock icon it needs to stay key.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(configStore: configStore))
        // The view fixes its own size; the window follows it rather than
        // offering a resize handle that would only reveal empty space.
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = L.string("settings.window.title")
        // Kept after closing so the next open is the same window, where it
        // was left, with the section that was showing.
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        return window
    }

    static let frameName = "aikon-settings"
}

extension NSOpenPanel {
    /// Shows the panel as a sheet on the Settings window, or free-standing
    /// if that window isn't there. Free-standing, it opened behind other
    /// apps whenever Aikon had lost frontmost status by then, and was
    /// reported doing exactly that; a sheet hangs off its window and can't
    /// get lost behind anything.
    func beginOnSettingsWindow(_ completion: @escaping @MainActor (URL?) -> Void) {
        guard let window = NSApp.windows.first(where: {
            $0.frameAutosaveName == SettingsWindowCoordinator.frameName
        }) else {
            completion(runModal() == .OK ? url : nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        beginSheetModal(for: window) { response in
            completion(response == .OK ? self.url : nil)
        }
    }
}
