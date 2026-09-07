import SwiftUI
import AppKit

/// Project glyph: custom image if there is one, otherwise the emoji from the table.
struct ProjectGlyph: View {
    let project: Project?

    var body: some View {
        if let image = ProjectIcon.image(for: project?.iconPath) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 19, height: 19)
                .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
        } else {
            Text(project?.emoji ?? ProjectMatching.defaultEmoji)
                .font(.system(size: 16))
                .frame(width: 19, height: 19)
        }
    }
}

struct MenuView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let blocks = nonEmptyBlocks
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                if index > 0 {
                    Divider().padding(.vertical, 5).padding(.horizontal, 8)
                }
                block
            }
        }
        .padding(5)
        .frame(width: 300)
    }

    private var nonEmptyBlocks: [AnyView] {
        var out: [AnyView] = []
        func add(_ view: some View) { out.append(AnyView(view)) }

        if !model.waiting.isEmpty      { add(sessions(model.waiting)) }
        if !model.finished.isEmpty     { add(sessions(model.finished)) }
        if !model.working.isEmpty      { add(sessions(model.working)) }
        if !model.idleProjects.isEmpty { add(projects(model.idleProjects)) }
        // Pinned projects close the menu, and only the quiet ones: a pinned
        // project with a live session is already in a group above.
        if !model.pinnedProjects.isEmpty { add(pinned(model.pinnedProjects)) }
        if let limits = model.limits   { add(LimitsBlock(limits: limits)) }
        if out.isEmpty                 { add(emptyState()) }
        add(footer())
        return out
    }

    /// The menu with nothing in it at all. Without this block a fresh install
    /// opens on Settings… and Quit alone, which reads as broken rather than as
    /// empty — and says nothing about the one setup step that may be missing.
    ///
    /// The mark is Aikon's own, not Claude's: pointing at compatibility with
    /// someone else's logo is a trademark question this app doesn't need to
    /// open, and the body text already names Claude Code in words.
    private func emptyState() -> some View {
        VStack(spacing: 0) {
            BrandMark(size: 40, cornerRadius: Theme.Radius.lg, markSize: 17)

            Text(L.string("menu.empty.title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, Theme.Spacing.md)

            Text(L.string("menu.empty.body"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xs)

            if model.needsHookSetup {
                Button {
                    NSApp.keyWindow?.close()
                    NotificationCenter.default.post(name: .aikonOpenSettings, object: nil)
                } label: {
                    Text(L.string("menu.empty.installHook"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Spacing.md)
            }

            // A footnote to the empty state, not a section of its own: no
            // divider above it, and dimmer than the sentence it sits under.
            // It answers "will it see my editor?" without a trip to Settings.
            Text(L.string("menu.empty.editors"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    /// Settings… and Quit always sit at the very bottom, regardless of
    /// what else the menu is showing right now.
    private func footer() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let version = model.availableUpdate {
                Button {
                    NSApp.keyWindow?.close()
                    NSWorkspace.shared.open(UpdateChecker.releasePageURL)
                } label: {
                    Text(L.format("menu.updateAvailable", version))
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .modifier(FooterRowSkin())
            }

            Button {
                // `MenuBarExtra(.window)` has no SwiftUI-native way to dismiss
                // its own popover on macOS 14. Three options were checked and
                // rejected before this one:
                // - `@Environment(\.dismiss)` only closes a modal presentation
                //   (sheet/popover/fullScreenCover) or a `Window` scene reached
                //   through `openWindow`. The menu bar popover isn't presented
                //   through either path, so it's a silent no-op here.
                // - `@Environment(\.dismissWindow)` targets a `Window` scene by
                //   its `id`. `MenuBarExtra` doesn't expose an id to target —
                //   there's nothing to pass it.
                // - `MenuBarExtra(isInserted:)` toggles the status *item*
                //   itself (the icon in the menu bar), not the popover. Using
                //   it here would make the icon blink away and reappear,
                //   which is worse than the popover staying open.
                // What actually works: the instant this action runs, the
                // click that fired it landed on this popover, so it's
                // guaranteed to be `NSApp.keyWindow` right now. Closing that
                // is plain public AppKit — no guessing at SwiftUI's internal
                // window class name, and a harmless no-op on the (never
                // expected) case there's no key window. Closing it before
                // posting the notification means the popover is gone before
                // Settings opens, not after, so there's no visible flash of
                // both windows at once.
                NSApp.keyWindow?.close()
                NotificationCenter.default.post(name: .aikonOpenSettings, object: nil)
            } label: {
                Text(L.string("menu.settings"))
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .modifier(FooterRowSkin())

            Button {
                NSApp.terminate(nil)
            } label: {
                Text(L.string("menu.quit"))
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .modifier(FooterRowSkin())
        }
    }

    /// Pinned projects close the menu, below everything that's actually
    /// happening. Only the quiet ones land here: a pinned project with a live
    /// session is already in a group above and must not be listed twice. No pin
    /// glyph on the row itself — the group they're in already says it.
    private func pinned(_ list: [Project]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.string("pinned.title"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .opacity(0.42)
                .padding(.horizontal, 7)
                .padding(.bottom, 2)
            ForEach(list, id: \.path) { ProjectRow(project: $0) }
        }
    }

    private func sessions(_ list: [Session]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(list) { session in
                SessionRow(session: session,
                           unread: model.isUnread(session),
                           onOpen: {
                               model.markSeen(session)
                               Opener.reveal(path: session.path)
                           })
            }
        }
    }

    private func projects(_ list: [Project]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(list, id: \.path) { ProjectRow(project: $0) }
        }
    }
}

/// Shared row background: hover, rounded corners, click.
private struct RowSkin: ViewModifier {
    let onClick: () -> Void
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(hovered ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(hovered ? Color.white : Color.primary)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onTapGesture(perform: onClick)
    }
}

/// Same look as `RowSkin` (hover highlight, rounded corners) but without its
/// own tap handling — footer rows are real buttons/links that already
/// handle their own taps, so adding another `onTapGesture` on top would
/// fire alongside (and race) the button's own action.
private struct FooterRowSkin: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(hovered ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(hovered ? Color.white : Color.primary)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

struct SessionRow: View {
    let session: Session
    let unread: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: session.status.symbolName)
                .font(.system(size: session.status == .working ? 7 : 13))
                .foregroundStyle(session.status.symbolColor)
                .opacity(session.status == .working ? 0.75 : 1)
                .frame(width: 20)

            ProjectGlyph(project: session.project)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(session.project?.name
                         ?? URL(fileURLWithPath: session.path).lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let branch = session.branch {
                        Text("· \(branch)")
                            .font(.system(size: 12))
                            .opacity(0.62)
                            .lineLimit(1)
                    }
                }
                Text("\(session.status.words) · \(Age.words(since: session.since))")
                    .font(.system(size: 11))
                    .opacity(0.62)
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            // Done, but not opened yet — like an unread letter.
            if unread {
                Circle()
                    .fill(Color.themed(light: 0x1c6cf0, dark: 0x4f9bff))
                    .frame(width: 7, height: 7)
            }
        }
        .modifier(RowSkin(onClick: onOpen))
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            // empty status column — so names line up with active rows
            Color.clear.frame(width: 20, height: 19)
            ProjectGlyph(project: project)
            Text(project.name).font(.system(size: 13)).opacity(0.62).lineLimit(1)
        }
        .modifier(RowSkin { Opener.revealProject(project) })
    }
}

struct LimitsBlock: View {
    let limits: Limits

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L.string("limits.title"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .opacity(0.42)
                .padding(.bottom, -2)

            bar("limits.session", limits.fiveHourPercent, limits.fiveHourResetsAt)
            bar("limits.week", limits.sevenDayPercent, limits.sevenDayResetsAt)
        }
        .padding(.horizontal, 7)
        .padding(.top, 3)
        .padding(.bottom, 4)
    }

    private func bar(_ labelKey: String, _ percent: Int, _ resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L.string(labelKey)).font(.system(size: 12)).opacity(0.62)
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.14))
                    Capsule()
                        .fill(color(percent))
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, percent))) / 100)
                }
            }
            .frame(height: 4)

            if let resetsAt {
                Text(L.format("limits.resetsIn", Age.words(since: Date(), now: resetsAt)))
                    .font(.system(size: 10))
                    .opacity(0.42)
                    .monospacedDigit()
            }
        }
    }

    /// Thresholds and colors match the design mockup, including separate
    /// values for light and dark mode.
    private func color(_ percent: Int) -> Color {
        if percent >= 85 { return .themed(light: 0xd8412f, dark: 0xff6b5c) }
        if percent >= 60 { return .themed(light: 0xd98b0a, dark: 0xf0b429) }
        return .themed(light: 0x1c6cf0, dark: 0x4f9bff)
    }
}

extension Color {
    /// A color that switches automatically with the system appearance.
    static func themed(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
                  green:   CGFloat((rgb >> 8)  & 0xff) / 255,
                  blue:    CGFloat(rgb & 0xff) / 255,
                  alpha: 1)
    }
}
