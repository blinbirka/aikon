import AppKit
import SwiftUI
import Combine

/// Owns the menu bar: the status item, the live label inside it, and the
/// popover that hangs off it.
///
/// This replaced `MenuBarExtra`, and the reason is entirely about the label —
/// see `StatusItemLabel` for what a `MenuBarExtra` label can and cannot hold.
/// The popover here is doing the same job `.menuBarExtraStyle(.window)` did.
@MainActor
final class StatusBarController {
    private let model: PanelModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let hosting: NSHostingView<StatusItemLabelHost>
    /// Measures, and is never added to anything. A view that already sits in
    /// the button has been given the button's width, and answers `fittingSize`
    /// with that — the width being computed from it. Detached, it answers with
    /// the width the label actually needs.
    private let sizer = NSHostingView(rootView: StatusItemLabel(counts: Counts()))
    private var cancellables: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?

    private static let slack: CGFloat = 2

    /// White on a dark bar, black on a light one — read off the button, the
    /// only object in the app that is told which one the system drew.
    private var numberColour: Color {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark ? .white : .black
    }

    private func repaint(counts: Counts? = nil) {
        hosting.rootView = StatusItemLabelHost(model: model, numberColour: numberColour)
        resize(counts: counts ?? model.counts)
    }

    init(model: PanelModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hosting = PassthroughHostingView(rootView: StatusItemLabelHost(model: model, numberColour: .primary))

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuView(model: model))

        if let button = statusItem.button {
            button.addSubview(hosting)
            button.target = self
            button.action = #selector(toggle)
            // macOS 14 flipped the default for `clipsToBounds`, so whether a
            // too-narrow button hides its content or lets it spill depends on
            // which SDK the app was linked against. Said out loud here so the
            // behaviour is the same everywhere.
            button.clipsToBounds = false
        }
        repaint()

        // The label is as wide as its digits, so the status item has to be
        // told a new width whenever a count gains or loses one.
        model.$counts
            .removeDuplicates()
            .sink { [weak self] counts in
                // The counts come from the publisher, not from `model.counts`:
                // `@Published` announces a change *before* the property holds
                // the new value, so reading the model here measured the label
                // against the previous numbers. A count crossing from one digit
                // to two was then drawn in a box sized for one, and the second
                // digit was cut off.
                Task { @MainActor in self?.repaint(counts: counts) }
            }
            .store(in: &cancellables)

        // The menu bar can flip between light and dark without the app's own
        // appearance changing at all — over a dark desktop picture, say.
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.repaint() }
        }

        // Rows inside the menu ask for it to go away before they open a window
        // — see `MenuView`. With `MenuBarExtra` that meant closing the key
        // window; a popover can simply be told.

        NotificationCenter.default.publisher(for: .aikonClosePanel)
            .sink { [weak self] _ in
                // Closed here and now, not on the next turn of the run loop.
                // "Settings…" posts this and then asks for the window in the
                // same breath; with the close deferred, the window opened
                // while the popover still held focus and the first click
                // appeared to do nothing. `close()` rather than
                // `performClose(nil)` for the same reason — no animation to
                // wait out.
                MainActor.assumeIsolated { self?.popover.close() }
            }
            .store(in: &cancellables)
    }

    /// Gives the label its own size and makes the status item that wide.
    ///
    /// Deliberately frame-based. Pinning the label to the button's edges with
    /// constraints looked tidier and clipped the last digit: the button is as
    /// wide as `statusItem.length`, `length` came from asking the label how
    /// wide it wanted to be, and a label already stretched to the button
    /// answers with the width it was given. Unattached to the button's width,
    /// it answers with the width it needs.
    private func resize(counts: Counts) {
        sizer.rootView = StatusItemLabel(counts: counts, numberColour: numberColour)
        sizer.layoutSubtreeIfNeeded()
        let size = sizer.fittingSize
        // Two points of slack. Every way of measuring this label agrees on the
        // same width, and at exactly that width SwiftUI still truncated the
        // last digit: laying text out in a box its own ideal size leaves
        // sub-pixel rounding nowhere to go.
        let width = ceil(size.width) + Self.slack
        // Full button height and origin zero, rather than a box the height of
        // the text centred by hand: the menu bar's height is fixed, and letting
        // SwiftUI centre inside it is one less number to keep in step.
        statusItem.length = width
        let height = statusItem.button?.bounds.height ?? size.height
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }



    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            // Without this the popover opens behind whatever app is in front,
            // and its first click is spent activating Aikon instead of hitting
            // the row the pointer is actually over.
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// The label has to draw, but never to take the click: a hosting view laid over
/// the status item's button would swallow the press, and the button is what
/// opens the popover.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @MainActor required init(rootView: Content) { super.init(rootView: rootView) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }
}
