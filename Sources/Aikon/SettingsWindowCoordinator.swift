import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted by the menu's "Settings…" row instead of using `SettingsLink`
    /// directly. Aikon is `LSUIElement` — it has no Dock icon — so nothing
    /// can hand a freshly opened Settings window keyboard focus on its own.
    /// See `SettingsWindowCoordinator` for the fix.
    static let aikonOpenSettings = Notification.Name("aikonOpenSettings")
    /// Asks the menu to close itself — posted by rows that are about to
    /// open a window, handled in `StatusBarController`.
    static let aikonClosePanel = Notification.Name("aikonClosePanel")
}

/// Brings the Settings window forward reliably from an `LSUIElement` app,
/// and puts the app back the way it was once that window closes.
///
/// The known-working recipe (see steipete.me, "Showing Settings From macOS
/// Menu Bar Items", and the related Apple Developer Forums thread): switch
/// the activation policy to `.regular` just long enough to open and focus
/// the window, then switch back to `.accessory` when it's closed. A plain
/// `SettingsLink` + `NSApp.activate` doesn't work here because an accessory
/// app has no Dock icon to hand focus to.
@MainActor
final class SettingsWindowCoordinator {
    static let shared = SettingsWindowCoordinator()

    private var closeObserver: NSObjectProtocol?

    func present(openSettings: @escaping () -> Void) {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()

        // The Settings window is created synchronously on macOS 14 in
        // practice, but waiting a tick keeps this correct even if a future
        // OS defers it.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            guard let window = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) })
            else { return }
            window.makeKeyAndOrderFront(nil)
            self.watch(window)
        }
    }

    /// Reverts to `.accessory` the moment the Settings window closes — not
    /// on losing focus, so switching to another app while Settings stays
    /// open doesn't prematurely hide the Dock icon it needs to stay key.
    private func watch(_ window: NSWindow) {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            // `queue: .main` above already guarantees this runs on the main
            // thread — `assumeIsolated` tells the compiler what's already
            // true instead of hopping through another `Task`.
            MainActor.assumeIsolated {
                self?.closeObserver = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

/// Invisible host for `@Environment(\.openSettings)`. That environment
/// value only exists inside a `View` — there's no free function for it —
/// so this view exists purely to read it and hand it to the coordinator.
/// It lives in its own `Window` scene, declared before `Settings` in
/// `AikonApp`, and hides itself immediately so it never visibly flashes.
struct SettingsWindowOpener: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(WindowAutoHider())
            .onReceive(NotificationCenter.default.publisher(for: .aikonOpenSettings)) { _ in
                SettingsWindowCoordinator.shared.present { openSettings() }
            }
    }
}

/// Orders its own window out the instant it appears. The window it's
/// attached to exists only so `SettingsWindowOpener` has an environment to
/// read `openSettings` from — it's never meant to be seen.
private struct WindowAutoHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { view.window?.orderOut(nil) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
