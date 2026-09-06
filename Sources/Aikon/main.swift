import Foundation

// `Aikon --render-screenshot <path>` draws the menu with demo data and exits
// — see `RenderScreenshot`. Checked here, before `AikonApp.main()`, so a
// render never puts an icon in the menu bar or opens a window in the first
// place, rather than opening one and closing it again.
if let path = RenderScreenshot.outputPath() {
    RenderScreenshot.run(to: path)
} else {
    AikonApp.main()
}
