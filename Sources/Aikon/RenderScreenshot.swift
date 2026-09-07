import SwiftUI
import AppKit

/// Draws the menu with made-up demo data and saves it as a PNG, so the
/// screenshot in `README.md`/`README.ru.md` never shows the author's real
/// projects. Reached from `main.swift` when the process is launched as
/// `Aikon --render-screenshot <path>` — before SwiftUI's own `App.main()`
/// runs, so nothing ever puts an icon in the menu bar or opens a window.
enum RenderScreenshot {
    /// The path after `--render-screenshot`, or `nil` when the flag isn't
    /// present — the normal, everyday way to launch the app.
    static func outputPath(in arguments: [String] = CommandLine.arguments) -> String? {
        guard let flagIndex = arguments.firstIndex(of: "--render-screenshot"),
              arguments.count > flagIndex + 1 else { return nil }
        return arguments[flagIndex + 1]
    }

    /// Renders `ScreenshotComposition` and writes it to `path`, then exits
    /// the process — this mode never falls through to the normal app.
    @MainActor
    static func run(to path: String) {
        L.language = .en // the README screenshot is always in English

        let model = PanelModel.renderPreview()
        let composition = ScreenshotComposition(model: model)

        guard let png = render(composition, width: ScreenshotComposition.canvasWidth) else {
            FileHandle.standardError.write(Data("render-screenshot: failed to draw the menu\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("render-screenshot: couldn't write \(path): \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }

    /// Off-screen render of `view` at `width` logical points, as tall as its
    /// content turns out to be, at 4x pixel density: the shot is a hero image
    /// people zoom into.
    ///
    /// This used to lay the view out in an `NSHostingView` and call
    /// `cacheDisplay(in:to:)` into a hand-built `NSBitmapImageRep` sized at
    /// `scale` times the logical size, on the assumption that AppKit reads that
    /// ratio and rasterizes at 4x. It does not: an off-screen view has no
    /// window and so a backing scale factor of 1, and the text came out soft
    /// while the image was nominally 2480px wide. Measured on the same
    /// composition, the share of hard edges in the menu rose from 0.36% to
    /// 2.74% when this switched to `ImageRenderer`, which takes the scale as an
    /// explicit input instead of inferring it.
    ///
    /// The trade `ImageRenderer` makes: it draws only what SwiftUI itself
    /// draws. An AppKit-backed view — a representable, a real material — comes
    /// out as a placeholder rather than an error. Everything `MenuView` uses
    /// today is text, shapes and images, so this is a constraint on what the
    /// menu may grow into, not a problem it has.
    @MainActor
    private static func render(_ view: some View, width: CGFloat, scale: CGFloat = 4) -> Data? {
        // `Theme`'s colors are `NSColor(name:dynamicProvider:)`, resolved against
        // whatever drawing appearance is current — and `ImageRenderer` does not
        // inherit one from a view the way `NSHostingView.appearance` did. Without
        // both of these the menu renders its light-mode text on its dark-mode
        // background: near-invisible grey on grey.
        guard let dark = NSAppearance(named: .darkAqua) else { return nil }
        var png: Data?
        dark.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(
                content: view
                    .frame(width: width)
                    .environment(\.colorScheme, .dark)
            )
            renderer.scale = scale
            // Nothing behind the menu: the PNG keeps an alpha channel so it sits
            // on whatever colour the page around it happens to be. The height is
            // whatever the laid-out content needs — `ImageRenderer` sizes to the
            // content, so there is no fixed canvas to leave empty space in.
            renderer.isOpaque = false
            if let cgImage = renderer.cgImage {
                png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
            }
        }
        return png
    }
}

/// The full picture: a slice of the macOS menu bar (icon + counts, like the
/// real status item) sitting above the menu itself — reproducing the
/// rounded corners and drop shadow that a real `MenuBarExtra` popover gets
/// for free from the system, since here the menu is drawn standalone, with
/// no real popover behind it. Drawn on transparency and cropped to its own
/// content, so the PNG carries no empty space and no background colour of its
/// own into whatever page it lands on.
struct ScreenshotComposition: View {
    let model: PanelModel

    /// Logical points; the PNG is `scale` times this wide (4x by default), and
    /// the height is whatever the content needs. The menu bar strip spans the
    /// full width while the menu below is 300pt and right-aligned — the room to
    /// the left of it is deliberate, it's what makes the strip read as a menu
    /// bar rather than as a title bar.
    static let canvasWidth: CGFloat = 620

    private let margin: CGFloat = 32
    private let stripHeight: CGFloat = 30
    private let gap: CGFloat = 22

    // Deliberately not from `Theme`: those tokens are tuned for a real
    // window's content area, not a standalone hero shot.
    private let stripColor = Color(nsColor: NSColor(rgb: 0x1C1C1F))
    private let cardColor = Color(nsColor: NSColor(rgb: 0x242429))

    var body: some View {
        VStack(alignment: .trailing, spacing: gap) {
            menuBarStrip
            MenuView(model: model)
                .background(cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
        // The margin is what keeps the shadow from being clipped off now that
        // the image is cropped to the content.
        .padding(margin)
        .frame(width: Self.canvasWidth)
        .preferredColorScheme(.dark)
    }

    /// Stands in for the real menu bar: the brand mark on the left, the same
    /// `StatusItemLabel` the live app shows on the right — so the numbers
    /// here can never drift from the ones in the actual menu below.
    private var menuBarStrip: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: NSColor(rgb: 0xFF8A4C)))
                .frame(width: 18, height: 18)
                .overlay(
                    DiamondShape()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                )
            Spacer(minLength: 12)
            StatusItemLabel(counts: model.counts)
                .font(.system(size: 13))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(height: stripHeight)
        .frame(maxWidth: .infinity)
        .background(stripColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
