import AppKit
import SwiftUI

/// The 28×28 icon square in a project row, backed by a real `NSImageView`
/// in `isEditable` mode. That gets Finder drag-and-drop, paste, and Delete
/// for free — the same "image well" behavior AppKit controls have always
/// had — instead of hand-rolling any of it in SwiftUI. A click that isn't a
/// drag opens the small icon picker menu (emoji / picture / remove); every
/// other way the image changes is reported back through `onImageChange`.
struct ProjectImageWell: NSViewRepresentable {
    var imagePath: String?
    var cornerRadius: CGFloat
    var onImageChange: (NSImage?) -> Void
    var onClick: () -> Void

    func makeNSView(context: Context) -> ImageWellView {
        let view = ImageWellView()
        view.isEditable = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.onChange = onImageChange
        view.onClick = onClick
        view.setImageProgrammatically(ProjectIcon.image(for: imagePath))
        return view
    }

    func updateNSView(_ nsView: ImageWellView, context: Context) {
        nsView.onChange = onImageChange
        nsView.onClick = onClick
        nsView.layer?.cornerRadius = cornerRadius
        let expected = ProjectIcon.image(for: imagePath)
        if !nsView.currentImageMatches(expected) {
            nsView.setImageProgrammatically(expected)
        }
    }
}

/// Custom subclass purely to (a) intercept a plain click to open the picker
/// menu instead of just selecting the view, and (b) report every other way
/// its `image` can change — drop, paste, Delete — without SwiftUI having to
/// poll it.
final class ImageWellView: NSImageView {
    var onChange: ((NSImage?) -> Void)?
    var onClick: (() -> Void)?
    private var suppressChange = false
    private var lastKnownImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleClick() { onClick?() }

    /// Sets the image without treating it as a user edit — used whenever
    /// SwiftUI hands this view a new `imagePath` to display.
    func setImageProgrammatically(_ newImage: NSImage?) {
        suppressChange = true
        image = newImage
        lastKnownImage = newImage
        suppressChange = false
    }

    func currentImageMatches(_ other: NSImage?) -> Bool {
        lastKnownImage === other || (lastKnownImage == nil && other == nil)
    }

    override var image: NSImage? {
        didSet {
            guard !suppressChange else { return }
            lastKnownImage = image
            onChange?(image)
        }
    }
}
