import SwiftUI
import AppKit

/// Single source of truth for the settings window's look: the "Graphite"
/// palette (dark + light) and the spacing/type/radius scales. Nothing in
/// `SettingsView` should reach for a raw color, point size, or corner
/// radius that isn't defined here.
enum Theme {

    // MARK: - Colors

    static let windowBackground = dynamic(dark: 0x1C1C1E, light: 0xF2F1EF)
    static let sidebarBackground = dynamic(dark: 0x161618, light: 0xEAE9E6)
    static let contentBackground = dynamic(dark: 0x202023, light: 0xFAFAF9)
    static let cardBackground = dynamic(dark: 0x2A2B2E, light: 0xFFFFFF)

    static let textPrimary = dynamic(dark: 0xF2F2F4, light: 0x1B1B1D)
    static let textDim = dynamic(dark: 0xA2A2AA, light: 0x5F5F66)
    static let textFaint = dynamic(dark: 0x71717A, light: 0x8E8E96)

    /// Same hex in both modes — the accent doesn't shift with appearance.
    static let accent = Color(nsColor: NSColor(rgb: 0xFF8A4C))
    static let textOnAccent = dynamic(dark: 0x25120A, light: 0xFFFFFF)

    /// Hairlines and highlights aren't separate hues — they're the primary
    /// text color at increasing transparency, same as the approved mockup
    /// (`color-mix(in srgb, var(--text) N%, transparent)`).
    static let line = textPrimary.opacity(0.10)
    static let hover = textPrimary.opacity(0.07)
    static let sunk = textPrimary.opacity(0.04)

    /// Track for the "what to show in the menu" segmented switch — a
    /// deliberately darker surface, not a text-opacity tint like `hover`/
    /// `sunk` above. An earlier version used a text tint here and the
    /// contrast was rejected as too subtle. Same recipe as the approved
    /// mockup's `.mseg` (`color-mix(in srgb, #000 26%, var(--content))`
    /// dark / 8% light, mixed into the content background).
    static let segmentTrack = dynamic(
        dark: mixed(0x202023, toward: 0x000000, by: 0.26),
        light: mixed(0xFAFAF9, toward: 0x000000, by: 0.08))

    /// The selected pill inside that switch — card surface lifted toward
    /// the text color (dark), or plain white (light). Matches the mockup.
    static let segmentSelected = dynamic(
        dark: mixed(0x2A2B2E, toward: 0xF2F2F4, by: 0.16),
        light: 0xFFFFFF)

    /// Subtle accent wash behind the hook banner in Projects — the accent
    /// color mixed into the content background, same recipe as the
    /// mockup's `--tint` (`color-mix(in srgb, var(--accent) 16%, var(--content))`).
    static let bannerTint = dynamic(
        dark: mixed(0x202023, toward: 0xFF8A4C, by: 0.16),
        light: mixed(0xFAFAF9, toward: 0xFF8A4C, by: 0.16))

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }

    /// Linear channel-wise blend of two hex colors — the same shape as CSS's
    /// `color-mix(in srgb, ...)`, which is what the approved mockup uses for
    /// every derived surface color above.
    private static func mixed(_ base: UInt32, toward: UInt32, by amount: Double) -> UInt32 {
        func channel(_ shift: Int) -> UInt32 {
            let b = Double((base >> shift) & 0xff)
            let t = Double((toward >> shift) & 0xff)
            return UInt32((b + (t - b) * amount).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    // MARK: - Scales — nothing outside these values

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum FontSize {
        static let caption: CGFloat = 11
        static let small: CGFloat = 12
        static let body: CGFloat = 13
        static let title: CGFloat = 15
        static let hero: CGFloat = 20
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }
}
