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

    /// Off-screen, retina (2x) render of `view` at `width` logical points, as
    /// tall as its content turns out to be.
    /// The bitmap is built by hand at 2x pixel dimensions — rather than
    /// asking `bitmapImageRepForCachingDisplay(in:)` to pick a scale — so the
    /// output is always retina, whether or not this process has an attached
    /// screen at all (it doesn't, in the CI/script use case this exists for).
    @MainActor
    private static func render(_ view: some View, width: CGFloat, scale: CGFloat = 2) -> Data? {
        let hostingView = NSHostingView(rootView: view.frame(width: width))
        // Forces every appearance-dependent color in the app (see
        // `Color.themed` in `MenuView.swift`, and `Theme.swift`) to resolve
        // the same way regardless of the machine's actual system setting —
        // the screenshot must look identical everywhere it's generated.
        hostingView.appearance = NSAppearance(named: .darkAqua)
        // Nothing behind the menu: the PNG keeps an alpha channel so it sits on
        // whatever colour the page around it happens to be.
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        // Height comes from the laid-out content rather than a fixed canvas.
        // The fixed canvas was 900x1100 with the menu floating in the middle of
        // it, so most of the image was empty space.
        var size = hostingView.fittingSize
        size.width = width
        guard size.height > 0 else { return nil }
        hostingView.setFrameSize(size)
        hostingView.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        // The pixel count above is 2x `size`; telling the rep its logical
        // size is still `size` is what makes those extra pixels "retina"
        // rather than just a bigger image — `cacheDisplay` reads this ratio
        // to pick its rendering scale.
        rep.size = size

        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
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

    /// Logical points; the image is twice this wide, since it always renders
    /// at 2x. The height is whatever the content needs.
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
